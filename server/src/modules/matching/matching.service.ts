import { DataSource, Not } from 'typeorm';
import { Queue } from 'bullmq';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { wktPoint } from '../../shared/utils/geo.js';
import { updateGlicko2 } from '../../shared/utils/glicko2.js';
import type { Glicko2Rating, Glicko2Result } from '../../shared/utils/glicko2.js';
import type {
  CreateMatchRequestDto,
  InstantMatchDto,
  ListMatchRequestsQuery,
  ListMatchesQuery,
  ConfirmMatchDto,
  CancelMatchDto,
} from './matching.schema.js';
import type { INotificationService, MatchAcceptTimeoutJobData } from '../../shared/types/index.js';
import { bullmqRedis } from '../../config/redis.js';
import {
  User,
  SportsProfile,
  Match,
  MatchRequest,
  MatchAcceptance,
  ChatRoom,
  Game,
  Message,
  ScoreHistory,
} from '../../entities/index.js';
import { MatchRequestStatus, RequestType, ScoreChangeType } from '../../entities/index.js';

// ─────────────────────────────────────
// 나이 계산 헬퍼
// ─────────────────────────────────────

function calculateAge(birthDate: Date): number {
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  const m = today.getMonth() - birthDate.getMonth();
  if (m < 0 || (m === 0 && today.getDate() < birthDate.getDate())) {
    age--;
  }
  return age;
}

export class MatchingService {
  private matchAcceptTimeoutQueue: Queue<MatchAcceptTimeoutJobData>;
  private userRepo;
  private sportsProfileRepo;
  private matchRepo;
  private matchRequestRepo;
  private matchAcceptanceRepo;
  private chatRoomRepo;
  private gameRepo;
  private messageRepo;

  constructor(
    private dataSource: DataSource,
    private notificationService?: INotificationService,
  ) {
    this.matchAcceptTimeoutQueue = new Queue<MatchAcceptTimeoutJobData>(
      'match-accept-timeout',
      { connection: bullmqRedis },
    );
    this.userRepo = dataSource.getRepository(User);
    this.sportsProfileRepo = dataSource.getRepository(SportsProfile);
    this.matchRepo = dataSource.getRepository(Match);
    this.matchRequestRepo = dataSource.getRepository(MatchRequest);
    this.matchAcceptanceRepo = dataSource.getRepository(MatchAcceptance);
    this.chatRoomRepo = dataSource.getRepository(ChatRoom);
    this.gameRepo = dataSource.getRepository(Game);
    this.messageRepo = dataSource.getRepository(Message);
  }

  // ─────────────────────────────────────
  // 매칭 요청 생성
  // ─────────────────────────────────────

  async createMatchRequest(userId: string, dto: CreateMatchRequestDto) {
    // 거절 쿨다운 체크
    const user = await this.userRepo.findOne({
      where: { id: userId },
      select: {
        id: true,
        gender: true,
        birthDate: true,
        rejectionCount: true,
        rejectionCooldownUntil: true,
      } as any,
    });

    if (!user) {
      throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
    }

    if ((user as any).rejectionCooldownUntil && (user as any).rejectionCooldownUntil > new Date()) {
      const remainingMs = (user as any).rejectionCooldownUntil.getTime() - Date.now();
      const remainingMinutes = Math.ceil(remainingMs / (60 * 1000));
      throw AppError.badRequest(
        ErrorCode.MATCH_REJECTION_COOLDOWN,
        `거절 쿨다운 중입니다. ${remainingMinutes}분 후에 다시 시도해 주세요.`,
        { cooldownUntil: (user as any).rejectionCooldownUntil, remainingMinutes },
      );
    }

    // 노쇼 밴 체크: 해당 종목 스포츠 프로필의 matchBanUntil 확인
    const bannedProfileRows = await this.dataSource.query(
      `SELECT match_ban_until FROM sports_profiles WHERE user_id = $1::uuid AND sport_type = $2::"SportType" AND is_active = true LIMIT 1`,
      [userId, dto.sportType],
    );
    if (bannedProfileRows.length > 0 && bannedProfileRows[0].match_ban_until) {
      const banUntil = new Date(bannedProfileRows[0].match_ban_until);
      if (banUntil > new Date()) {
        const remainingMs = banUntil.getTime() - Date.now();
        const remainingHours = Math.ceil(remainingMs / (60 * 60 * 1000));
        throw AppError.badRequest(
          ErrorCode.MATCH_REJECTION_COOLDOWN,
          `노쇼 패널티로 인해 매칭이 제한되었습니다. ${remainingHours}시간 후에 다시 시도해 주세요.`,
          { banUntil, remainingHours },
        );
      }
    }

    // 활성 스포츠 프로필 확인 — 없으면 자동 생성
    const spRows = await this.dataSource.query(
      `SELECT * FROM sports_profiles WHERE user_id = $1::uuid AND sport_type = $2::"SportType" AND is_active = true LIMIT 1`,
      [userId, dto.sportType],
    );
    let sportsProfile = spRows.length > 0
      ? this.sportsProfileRepo.create({
          id: spRows[0].id,
          userId: spRows[0].user_id,
          sportType: spRows[0].sport_type,
          currentScore: spRows[0].current_score,
          initialScore: spRows[0].initial_score,
          displayName: spRows[0].display_name,
          tier: spRows[0].tier,
          gHandicap: spRows[0].g_handicap,
          isActive: spRows[0].is_active,
          gamesPlayed: spRows[0].games_played,
          wins: spRows[0].wins,
          losses: spRows[0].losses,
        })
      : null;

    if (!sportsProfile) {
      sportsProfile = this.sportsProfileRepo.create({
        userId,
        sportType: dto.sportType as any,
        displayName: user.nickname,
        initialScore: 1000,
        currentScore: 1000,
        tier: 'BRONZE' as any,
        isActive: true,
      });
      await this.sportsProfileRepo.save(sportsProfile);
    }

    // ─── 날짜 제한 체크: 오늘 또는 내일만 가능 ───
    const desiredDate = dto.desiredDate;
    if (desiredDate) {
      const today = new Date().toISOString().split('T')[0];
      const tomorrow = new Date(Date.now() + 86400000).toISOString().split('T')[0];
      if (desiredDate !== today && desiredDate !== tomorrow) {
        throw AppError.badRequest(
          ErrorCode.VALIDATION_ERROR,
          '매칭은 오늘 또는 내일만 신청할 수 있습니다.',
        );
      }

      // 같은 날짜에 WAITING/MATCHED 요청 있는지
      const existingRequestForDate = await this.matchRequestRepo
        .createQueryBuilder('mr')
        .where('mr.requester_id = :userId', { userId })
        .andWhere('mr.desired_date = :date', { date: desiredDate })
        .andWhere('mr.status IN (:...statuses)', { statuses: ['WAITING', 'MATCHED'] })
        .getOne();

      if (existingRequestForDate) {
        throw AppError.conflict(
          ErrorCode.MATCH_ALREADY_EXISTS,
          '해당 날짜에 이미 매칭 요청이 있습니다.',
        );
      }

      // 같은 날짜에 활성 매칭 있는지 (PENDING_ACCEPT, CHAT, CONFIRMED)
      const activeMatchForDate = await this.matchRepo
        .createQueryBuilder('m')
        .leftJoin('m.requesterProfile', 'rp')
        .leftJoin('m.opponentProfile', 'op')
        .where('(rp.userId = :userId OR op.userId = :userId)', { userId })
        .andWhere('m.scheduled_date = :date', { date: desiredDate })
        .andWhere('m.status IN (:...statuses)', { statuses: ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'] })
        .getOne();

      if (activeMatchForDate) {
        throw AppError.conflict(
          ErrorCode.MATCH_ALREADY_EXISTS,
          '해당 날짜에 이미 진행 중인 매칭이 있습니다.',
        );
      }
    }

    // ─── 총 활성 매칭/요청 2개 제한 ───
    const totalActiveRequests = await this.matchRequestRepo
      .createQueryBuilder('mr')
      .where('mr.requester_id = :userId', { userId })
      .andWhere('mr.status IN (:...statuses)', { statuses: ['WAITING', 'MATCHED'] })
      .getCount();

    const totalActiveMatches = await this.matchRepo
      .createQueryBuilder('m')
      .leftJoin('m.requesterProfile', 'rp')
      .leftJoin('m.opponentProfile', 'op')
      .where('(rp.userId = :userId OR op.userId = :userId)', { userId })
      .andWhere('m.status IN (:...statuses)', { statuses: ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'] })
      .getCount();

    if (totalActiveRequests + totalActiveMatches >= 2) {
      throw AppError.conflict(
        ErrorCode.MATCH_ALREADY_EXISTS,
        '최대 2개까지만 매칭 요청이 가능합니다. (오늘/내일)',
      );
    }

    // 캐주얼 모드 처리: isCasual이 true이면 requestType을 CASUAL로, MMR 범위를 ±300으로 설정
    const isCasual = (dto as any).isCasual === true;
    if (isCasual) {
      (dto as any).requestType = RequestType.CASUAL;
      // 캐주얼은 더 넓은 MMR 범위 적용 (기본값 덮어쓰기)
      if (dto.minOpponentScore === 800 && dto.maxOpponentScore === 1200) {
        dto.minOpponentScore = Math.max(100, sportsProfile.currentScore - 300);
        dto.maxOpponentScore = sportsProfile.currentScore + 300;
      }
    }

    // 만료 시간 설정 (SCHEDULED: 요청 날짜 자정, INSTANT: 2시간 후, CASUAL: 2시간 후)
    let expiresAt: Date;
    if (dto.requestType === RequestType.INSTANT || (dto.requestType as string) === 'INSTANT') {
      expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
    } else if ((dto.requestType as string) === 'CASUAL') {
      expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
    } else if (dto.desiredDate) {
      expiresAt = new Date(`${dto.desiredDate}T23:59:59Z`);
    } else {
      expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7일
    }

    // Pin 조회 (pinId로 중심 좌표 가져오기)
    const pinRows = await this.dataSource.query(
      `SELECT id FROM pins WHERE id = $1::uuid`,
      [dto.pinId],
    );

    if (!pinRows || pinRows.length === 0) {
      throw AppError.notFound(ErrorCode.PIN_NOT_FOUND, '해당 핀을 찾을 수 없습니다.');
    }

    // Pin 중심 좌표에서 lat/lng 추출
    const pinCenter = await this.dataSource.query<Array<{ lat: number; lng: number }>>(
      `SELECT ST_Y(center::geometry) AS lat, ST_X(center::geometry) AS lng FROM pins WHERE id = $1::uuid`,
      [dto.pinId],
    );

    const lat = dto.latitude ?? pinCenter[0]?.lat;
    const lng = dto.longitude ?? pinCenter[0]?.lng;
    const hasCoords = lat !== undefined && lng !== undefined;
    const pointWkt = hasCoords ? wktPoint(lat, lng) : null;

    // 매칭 요청 생성 (Pin 기반)
    const request = await this.dataSource.query<Array<{ id: string }>>(
      `INSERT INTO match_requests (
        requester_id, sports_profile_id, pin_id, sport_type, request_type,
        desired_date, desired_time_slot, location_point, location_name,
        min_opponent_score, max_opponent_score,
        gender_preference, min_age, max_age,
        message, is_casual, status, expires_at
      ) VALUES (
        $1::uuid,
        $2::uuid,
        $3::uuid,
        $4::"SportType",
        $5::"RequestType",
        $6::date,
        $7::"TimeSlot",
        CASE WHEN $8::text IS NOT NULL THEN ST_GeogFromText($8) ELSE NULL END,
        $9,
        $10,
        $11,
        $12,
        $13::int,
        $14::int,
        $15,
        $16,
        'WAITING',
        $17
      )
      RETURNING id`,
      [
        userId,
        sportsProfile.id,
        dto.pinId,
        dto.sportType,
        dto.requestType,
        dto.desiredDate ? new Date(dto.desiredDate) : null,
        dto.desiredTimeSlot ?? null,
        pointWkt,
        dto.locationName ?? null,
        dto.minOpponentScore,
        dto.maxOpponentScore,
        dto.genderPreference ?? 'ANY',
        dto.minAge ?? null,
        dto.maxAge ?? null,
        dto.message ?? null,
        isCasual,
        expiresAt,
      ],
    );

    const requestId = request[0].id;

    // 자동 매칭 시도
    const candidatesCount = await this.tryAutoMatch(requestId, {
      sportType: dto.sportType,
      pinId: dto.pinId,
      minOpponentScore: dto.minOpponentScore,
      maxOpponentScore: dto.maxOpponentScore,
      requesterScore: sportsProfile.currentScore,
      requesterUserId: userId,
      requesterGender: (user as any).gender,
      requesterBirthDate: (user as any).birthDate,
      genderPreference: dto.genderPreference ?? 'ANY',
      minAge: dto.minAge,
      maxAge: dto.maxAge,
    });

    // tryAutoMatch 성공 시 상태가 MATCHED로 변경될 수 있으므로 DB에서 최신 상태 재조회
    const updatedRequest = await this.matchRequestRepo.findOne({
      where: { id: requestId },
      select: { status: true } as any,
    });

    return {
      id: requestId,
      status: (updatedRequest?.status ?? 'WAITING') as MatchRequestStatus,
      expiresAt,
      candidatesCount,
    };
  }

  // ─────────────────────────────────────
  // 즉시 매칭 (오늘 대결)
  // ─────────────────────────────────────

  async createInstantMatch(userId: string, dto: InstantMatchDto) {
    return this.createMatchRequest(userId, {
      sportType: dto.sportType,
      requestType: RequestType.INSTANT,
      pinId: dto.pinId,
      minOpponentScore: 800,
      maxOpponentScore: 1200,
      genderPreference: 'ANY',
      isCasual: false,
    } as any);
  }

  // ─────────────────────────────────────
  // 자동 매칭 시도 (전면 개편)
  // ─────────────────────────────────────

  private async tryAutoMatch(
    requestId: string,
    opts: {
      sportType: string;
      pinId: string;
      minOpponentScore: number;
      maxOpponentScore: number;
      requesterScore: number;
      requesterUserId: string;
      requesterGender: string | null;
      requesterBirthDate: Date | null;
      genderPreference: string;
      minAge?: number;
      maxAge?: number;
    },
  ): Promise<number> {
    // 1) 같은 Pin + 같은 종목 + WAITING 상태 + 점수 범위 내 후보 조회
    const rawCandidates = await this.dataSource.query<
      Array<{
        id: string;
        userId: string;
        currentScore: number;
        sportsProfileId: string;
        gender: string | null;
        birthDate: Date | null;
        nickname: string;
        matchRequestId: string;
        genderPreference: string;
        minAge: number | null;
        maxAge: number | null;
      }>
    >(
      `SELECT
        sp.id,
        sp.user_id AS "userId",
        sp.current_score AS "currentScore",
        sp.id AS "sportsProfileId",
        u.gender,
        u.birth_date AS "birthDate",
        u.nickname,
        mr.id AS "matchRequestId",
        mr.gender_preference AS "genderPreference",
        mr.min_age AS "minAge",
        mr.max_age AS "maxAge"
      FROM match_requests mr
      JOIN sports_profiles sp ON sp.id = mr.sports_profile_id
      JOIN users u ON u.id = mr.requester_id
      WHERE mr.pin_id = $1::uuid
        AND mr.sport_type = $2::"SportType"
        AND mr.status = 'WAITING'
        AND mr.requester_id != $3::uuid
        AND mr.expires_at > NOW()
        AND sp.current_score >= $4
        AND sp.current_score <= $5
      ORDER BY ABS(sp.current_score - $6) ASC
      LIMIT 50`,
      [
        opts.pinId,
        opts.sportType,
        opts.requesterUserId,
        opts.minOpponentScore,
        opts.maxOpponentScore,
        opts.requesterScore,
      ],
    );

    if (rawCandidates.length === 0) return 0;

    const requesterAge = opts.requesterBirthDate
      ? calculateAge(opts.requesterBirthDate)
      : null;

    // 2) 필터링: 성별 조건 + 나이 조건 (양방향)
    const filteredCandidates = rawCandidates.filter((candidate) => {
      // --- 성별 조건 ---
      if (opts.genderPreference === 'SAME') {
        if (!opts.requesterGender || !candidate.gender) return false;
        if (candidate.gender !== opts.requesterGender) return false;
      }
      if (candidate.genderPreference === 'SAME') {
        if (!opts.requesterGender || !candidate.gender) return false;
        if (opts.requesterGender !== candidate.gender) return false;
      }

      // --- 나이 조건 ---
      const candidateAge = candidate.birthDate
        ? calculateAge(new Date(candidate.birthDate))
        : null;

      if (opts.minAge !== undefined && opts.minAge !== null) {
        if (candidateAge === null || candidateAge < opts.minAge) return false;
      }
      if (opts.maxAge !== undefined && opts.maxAge !== null) {
        if (candidateAge === null || candidateAge > opts.maxAge) return false;
      }

      if (candidate.minAge !== null && candidate.minAge !== undefined) {
        if (requesterAge === null || requesterAge < candidate.minAge) return false;
      }
      if (candidate.maxAge !== null && candidate.maxAge !== undefined) {
        if (requesterAge === null || requesterAge > candidate.maxAge) return false;
      }

      return true;
    });

    if (filteredCandidates.length === 0) return 0;

    // 3) 점수 차이 계산
    const candidatesWithDiff = filteredCandidates.map((c) => ({
      ...c,
      scoreDiff: Math.abs(c.currentScore - opts.requesterScore),
    }));

    candidatesWithDiff.sort((a, b) => a.scoreDiff - b.scoreDiff);

    const bestCandidate = candidatesWithDiff[0];

    // 4~6) 점수 차이에 따른 즉시 매칭 or 지연 매칭
    if (bestCandidate.scoreDiff <= 50) {
      // 4) 점수차 50 이내 → 즉시 매칭
      await this.createMatch(requestId, bestCandidate, opts);
    } else if (bestCandidate.scoreDiff <= 150) {
      // 5) 점수차 50~150 → 3분 대기 후 매칭
      await this.matchAcceptTimeoutQueue.add(
        'delayed-match',
        {
          matchId: '',
          requesterUserId: opts.requesterUserId,
          opponentUserId: bestCandidate.userId,
          requesterRequestId: requestId,
          opponentRequestId: bestCandidate.matchRequestId,
        },
        { delay: 3 * 60 * 1000, jobId: `delayed-match-${requestId}` },
      );
    } else {
      // 6) 점수차 150 이상 → 5분 대기 후 매칭
      await this.matchAcceptTimeoutQueue.add(
        'delayed-match',
        {
          matchId: '',
          requesterUserId: opts.requesterUserId,
          opponentUserId: bestCandidate.userId,
          requesterRequestId: requestId,
          opponentRequestId: bestCandidate.matchRequestId,
        },
        { delay: 5 * 60 * 1000, jobId: `delayed-match-${requestId}` },
      );
    }

    return filteredCandidates.length;
  }

  // ─────────────────────────────────────
  // 매칭 성사 처리 (PENDING_ACCEPT 플로우)
  // ─────────────────────────────────────

  async createMatch(
    requestId: string,
    bestCandidate: {
      id: string;
      userId: string;
      currentScore: number;
      nickname: string;
      gender: string | null;
      birthDate: Date | null;
      matchRequestId: string;
    },
    opts: {
      sportType: string;
      requesterUserId: string;
      pinId?: string;
    },
  ): Promise<void> {
    await this.dataSource.transaction(async (manager) => {
      // 요청자 프로필 가져오기
      const requesterProfile = await manager.findOne(SportsProfile, {
        where: { userId: opts.requesterUserId, sportType: opts.sportType as any },
      });

      if (!requesterProfile) return;

      // pinId가 없으면 매칭 요청에서 가져오기
      let pinId = opts.pinId;
      if (!pinId) {
        const matchRequest = await manager.findOne(MatchRequest, {
          where: { id: requestId },
          select: { pinId: true } as any,
        });
        pinId = matchRequest?.pinId ?? undefined;
      }

      // 요청자 정보 (알림용)
      const requester = await manager.findOne(User, {
        where: { id: opts.requesterUserId },
        select: { nickname: true, gender: true, birthDate: true } as any,
      });

      // 매칭 생성 (ChatRoom 없이 PENDING_ACCEPT 상태)
      const match = manager.create(Match, {
        matchRequestId: requestId,
        requesterProfileId: requesterProfile.id,
        opponentProfileId: bestCandidate.id,
        pinId: pinId ?? null,
        sportType: opts.sportType as any,
        status: 'PENDING_ACCEPT' as any,
      });
      const savedMatch = await manager.save(Match, match);

      const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10분 후

      // MatchAcceptance 레코드 2개 생성 (양측)
      await manager.save(MatchAcceptance, [
        manager.create(MatchAcceptance, {
          matchId: savedMatch.id,
          userId: opts.requesterUserId,
          accepted: null,
          expiresAt,
        }),
        manager.create(MatchAcceptance, {
          matchId: savedMatch.id,
          userId: bestCandidate.userId,
          accepted: null,
          expiresAt,
        }),
      ]);

      // 매칭 요청 상태를 MATCHED로 변경 (양측)
      await manager
        .createQueryBuilder()
        .update(MatchRequest)
        .set({ status: MatchRequestStatus.MATCHED })
        .where('id IN (:...ids)', { ids: [requestId, bestCandidate.matchRequestId] })
        .execute();

      // 10분 타임아웃 BullMQ delayed job 등록
      await this.matchAcceptTimeoutQueue.add(
        'accept-timeout',
        {
          matchId: savedMatch.id,
          requesterUserId: opts.requesterUserId,
          opponentUserId: bestCandidate.userId,
          requesterRequestId: requestId,
          opponentRequestId: bestCandidate.matchRequestId,
        },
        {
          delay: 10 * 60 * 1000,
          jobId: `accept-timeout-${savedMatch.id}`,
        },
      );

      // 양측에 알림 발송
      if (this.notificationService) {
        const requesterAge = (requester as any)?.birthDate
          ? calculateAge(new Date((requester as any).birthDate))
          : null;
        const opponentAge = bestCandidate.birthDate
          ? calculateAge(new Date(bestCandidate.birthDate))
          : null;

        await this.notificationService.sendBulk([
          {
            userId: opts.requesterUserId,
            type: 'MATCH_PENDING_ACCEPT',
            title: '매칭 상대를 찾았습니다!',
            body: `상대: ${bestCandidate.nickname}${bestCandidate.gender ? `/${bestCandidate.gender}` : ''}${opponentAge !== null ? `/${opponentAge}세` : ''}. 수락하시겠습니까?`,
            data: {
              matchId: savedMatch.id,
              opponentNickname: bestCandidate.nickname,
              opponentGender: bestCandidate.gender ?? '',
              opponentAge: opponentAge !== null ? String(opponentAge) : '',
              deepLink: `/match/${savedMatch.id}/accept`,
            },
          },
          {
            userId: bestCandidate.userId,
            type: 'MATCH_PENDING_ACCEPT',
            title: '매칭 상대를 찾았습니다!',
            body: `상대: ${(requester as any)?.nickname ?? ''}${(requester as any)?.gender ? `/${(requester as any).gender}` : ''}${requesterAge !== null ? `/${requesterAge}세` : ''}. 수락하시겠습니까?`,
            data: {
              matchId: savedMatch.id,
              opponentNickname: (requester as any)?.nickname ?? '',
              opponentGender: (requester as any)?.gender ?? '',
              opponentAge: requesterAge !== null ? String(requesterAge) : '',
              deepLink: `/match/${savedMatch.id}/accept`,
            },
          },
        ]);
      }
    });
  }

  // ─────────────────────────────────────
  // 매칭 수락
  // ─────────────────────────────────────

  async acceptMatch(userId: string, matchId: string) {
    // 1) MatchAcceptance 찾기
    const acceptance = await this.matchAcceptanceRepo.findOne({
      where: { matchId, userId },
    });

    if (!acceptance) {
      throw AppError.notFound(ErrorCode.MATCH_NOT_FOUND, '매칭 수락 정보를 찾을 수 없습니다.');
    }

    // 2) 이미 응답했으면 에러
    if (acceptance.accepted !== null) {
      throw AppError.badRequest(
        ErrorCode.MATCH_ALREADY_RESPONDED,
        '이미 응답한 매칭입니다.',
      );
    }

    // 3) 만료 여부 체크
    if (new Date() > acceptance.expiresAt) {
      throw AppError.badRequest(
        ErrorCode.MATCH_ACCEPT_EXPIRED,
        '매칭 수락 시간이 만료되었습니다.',
      );
    }

    // 4) 수락 처리
    await this.matchAcceptanceRepo.update(acceptance.id, {
      accepted: true,
      respondedAt: new Date(),
    });

    // 5) 상대방 MatchAcceptance 확인
    const opponentAcceptance = await this.matchAcceptanceRepo.findOne({
      where: { matchId, userId: Not(userId) },
    });

    if (opponentAcceptance?.accepted === true) {
      // 양측 수락! → Match status를 CHAT으로, ChatRoom 생성
      await this.dataSource.transaction(async (manager) => {
        // ChatRoom 생성
        const chatRoom = manager.create(ChatRoom, { roomType: 'MATCH' as any });
        const savedChatRoom = await manager.save(ChatRoom, chatRoom);

        // Match 상태 CHAT으로 변경 + chatRoomId 연결
        await manager.update(Match, matchId, {
          status: 'CHAT' as any,
          chatRoomId: savedChatRoom.id,
        });

        // Match 정보 (알림용) 조회
        const match = await manager.findOne(Match, {
          where: { id: matchId },
          relations: {
            requesterProfile: { user: true } as any,
            opponentProfile: { user: true } as any,
          },
        });

        // ChatRoom에 matchId 연결
        await manager.update(ChatRoom, savedChatRoom.id, { matchId } as any);

        // 게임 레코드 생성 (결과 입력 기한: 72시간)
        const resultInputDeadline = new Date(Date.now() + 72 * 60 * 60 * 1000);
        await manager.save(Game, manager.create(Game, {
          matchId,
          sportType: match?.sportType,
          resultStatus: 'PENDING' as any,
          resultInputDeadline,
        }));

        // 시스템 메시지 삽입
        await manager.save(Message, manager.create(Message, {
          chatRoomId: savedChatRoom.id,
          senderId: match?.requesterProfile?.userId,
          messageType: 'SYSTEM' as any,
          content: '매칭이 성사되었습니다! 상대방과 경기 일정을 조율해 보세요.',
        }));

        // 양측 알림
        if (this.notificationService && match) {
          await this.notificationService.sendBulk([
            {
              userId: (match.requesterProfile as any).userId,
              type: 'MATCH_BOTH_ACCEPTED',
              title: '매칭이 확정되었습니다!',
              body: `${(match.opponentProfile as any).user?.nickname ?? ''}님과의 매칭이 확정되었습니다.`,
              data: { matchId, chatRoomId: savedChatRoom.id, deepLink: `/match/${matchId}/chat` },
            },
            {
              userId: (match.opponentProfile as any).userId,
              type: 'MATCH_BOTH_ACCEPTED',
              title: '매칭이 확정되었습니다!',
              body: `${(match.requesterProfile as any).user?.nickname ?? ''}님과의 매칭이 확정되었습니다.`,
              data: { matchId, chatRoomId: savedChatRoom.id, deepLink: `/match/${matchId}/chat` },
            },
          ]);
        }
      });

      return { status: 'MATCHED', message: '매칭이 확정되었습니다!' };
    }

    // 상대가 아직 응답 안 했으면 대기 알림
    if (this.notificationService) {
      await this.notificationService.send({
        userId,
        type: 'MATCH_WAITING_OPPONENT',
        title: '수락 완료',
        body: '수락 완료. 상대의 응답을 기다리고 있습니다.',
        data: { matchId, deepLink: `/match/${matchId}/status` },
      });
    }

    return { status: 'WAITING_OPPONENT', message: '수락 완료. 상대의 응답을 기다리고 있습니다.' };
  }

  // ─────────────────────────────────────
  // 매칭 거절
  // ─────────────────────────────────────

  async rejectMatch(userId: string, matchId: string) {
    // 1) MatchAcceptance 찾기
    const acceptance = await this.matchAcceptanceRepo.findOne({
      where: { matchId, userId },
      relations: { match: true },
    });

    if (!acceptance) {
      throw AppError.notFound(ErrorCode.MATCH_NOT_FOUND, '매칭 수락 정보를 찾을 수 없습니다.');
    }

    if (acceptance.accepted !== null) {
      throw AppError.badRequest(
        ErrorCode.MATCH_ALREADY_RESPONDED,
        '이미 응답한 매칭입니다.',
      );
    }

    // 상대방 MatchAcceptance 조회
    const opponentAcceptance = await this.matchAcceptanceRepo.findOne({
      where: { matchId, userId: Not(userId) },
    });

    // 거절자의 스포츠 프로필 조회 (패널티 적용용)
    const matchForReject = await this.matchRepo.findOne({
      where: { id: matchId },
      relations: {
        requesterProfile: true,
        opponentProfile: true,
      } as any,
    });

    await this.dataSource.transaction(async (manager) => {
      // 2) 거절 처리
      await manager.update(MatchAcceptance, acceptance.id, {
        accepted: false,
        respondedAt: new Date(),
      });

      // 3) Match status를 CANCELLED로
      await manager.update(Match, matchId, {
        status: 'CANCELLED' as any,
        cancelledBy: userId,
      });

      // 4) 양측 매칭 요청 WAITING으로 복구
      // 거절한 유저의 matchRequest
      const rejecterMatchRequest = await manager
        .createQueryBuilder(MatchRequest, 'mr')
        .leftJoin('mr.sportsProfile', 'sp')
        .where('sp.userId = :userId AND mr.status = :status', {
          userId,
          status: MatchRequestStatus.MATCHED,
        })
        .orderBy('mr.updatedAt', 'DESC')
        .getOne();

      if (rejecterMatchRequest) {
        await manager.update(MatchRequest, rejecterMatchRequest.id, {
          status: MatchRequestStatus.WAITING,
        });
      }

      // 상대방의 matchRequest (수락했다면 재매칭 가능 상태 유지)
      if (opponentAcceptance) {
        const opponentMatchRequest = await manager
          .createQueryBuilder(MatchRequest, 'mr')
          .leftJoin('mr.sportsProfile', 'sp')
          .where('sp.userId = :userId AND mr.status = :status', {
            userId: opponentAcceptance.userId,
            status: MatchRequestStatus.MATCHED,
          })
          .orderBy('mr.updatedAt', 'DESC')
          .getOne();

        if (opponentMatchRequest) {
          await manager.update(MatchRequest, opponentMatchRequest.id, {
            status: MatchRequestStatus.WAITING,
          });
        }
      }

      // 5) 거절한 유저의 rejectionCount + 1
      await manager
        .createQueryBuilder()
        .update(User)
        .set({ rejectionCount: () => 'rejection_count + 1' })
        .where('id = :id', { id: userId })
        .execute();

      const updatedUser = await manager.findOne(User, {
        where: { id: userId },
        select: { rejectionCount: true } as any,
      });

      // 6) 거절 쿨다운 적용
      let cooldownHours = 0;
      const rejectionCount = (updatedUser as any)?.rejectionCount ?? 0;
      if (rejectionCount >= 20) {
        cooldownHours = 6;
      } else if (rejectionCount >= 10) {
        cooldownHours = 2;
      } else if (rejectionCount >= 5) {
        cooldownHours = 0.5; // 30분
      }

      if (cooldownHours > 0) {
        const cooldownUntil = new Date(Date.now() + cooldownHours * 60 * 60 * 1000);
        await manager
          .createQueryBuilder()
          .update(User)
          .set({ rejectionCooldownUntil: cooldownUntil } as any)
          .where('id = :id', { id: userId })
          .execute();
      }

      // 7) 거절자 -15 displayScore 패널티 (glickoRating은 변경하지 않음)
      //    수락자에게 +5 displayScore 보상
      if (matchForReject) {
        const isRequester = (matchForReject.requesterProfile as any).userId === userId;
        const rejecterProfile = isRequester
          ? matchForReject.requesterProfile
          : matchForReject.opponentProfile;
        const acceptorProfile = isRequester
          ? matchForReject.opponentProfile
          : matchForReject.requesterProfile;

        // 거절자 패널티: displayScore -15, currentScore -15 (glickoRating 불변)
        if (rejecterProfile) {
          const scoreBefore = (rejecterProfile as any).displayScore
            ?? (rejecterProfile as any).currentScore
            ?? 1000;
          const newScore = Math.max(100, scoreBefore - 15);

          await manager
            .createQueryBuilder()
            .update(SportsProfile)
            .set({
              displayScore: newScore,
              currentScore: newScore,
            })
            .where('id = :id', { id: (rejecterProfile as any).id })
            .execute();

          await manager.save(ScoreHistory, manager.create(ScoreHistory, {
            sportsProfileId: (rejecterProfile as any).id,
            gameId: null,
            changeType: ScoreChangeType.NO_SHOW_PENALTY,
            scoreBefore,
            scoreChange: -15,
            scoreAfter: newScore,
          }));
        }

        // 수락자 보상: displayScore +5 (상대가 수락한 경우에만 — opponentAcceptance.accepted === true)
        if (acceptorProfile && opponentAcceptance && opponentAcceptance.accepted === true) {
          const acceptorScoreBefore = (acceptorProfile as any).displayScore
            ?? (acceptorProfile as any).currentScore
            ?? 1000;
          const acceptorNewScore = acceptorScoreBefore + 5;

          await manager
            .createQueryBuilder()
            .update(SportsProfile)
            .set({
              displayScore: acceptorNewScore,
              currentScore: acceptorNewScore,
            })
            .where('id = :id', { id: (acceptorProfile as any).id })
            .execute();

          await manager.save(ScoreHistory, manager.create(ScoreHistory, {
            sportsProfileId: (acceptorProfile as any).id,
            gameId: null,
            changeType: ScoreChangeType.NO_SHOW_PENALTY,
            scoreBefore: acceptorScoreBefore,
            scoreChange: 5,
            scoreAfter: acceptorNewScore,
          }));
        }

        // 수락자의 MatchRequest는 WAITING으로 복구 (재매칭 가능)
        // (위 4)번 코드에서 이미 WAITING으로 변경됨 — acceptorMatchRequest 별도 처리 불필요)
      }
    });

    // 8) 양측 알림
    if (this.notificationService && opponentAcceptance) {
      await this.notificationService.sendBulk([
        {
          userId,
          type: 'MATCH_REJECTED',
          title: '매칭 거절 완료',
          body: '매칭을 거절했습니다. -15점 패널티가 적용되었습니다.',
          data: { matchId },
        },
        {
          userId: opponentAcceptance.userId,
          type: 'MATCH_REJECTED',
          title: '매칭이 취소되었습니다',
          body: '상대방이 매칭을 거절했습니다. 다시 매칭을 시도해 보세요.',
          data: { matchId },
        },
      ]);
    } else if (this.notificationService) {
      await this.notificationService.send({
        userId,
        type: 'MATCH_REJECTED',
        title: '매칭 거절 완료',
        body: '매칭을 거절했습니다. -15점 패널티가 적용되었습니다.',
        data: { matchId },
      });
    }

    return { status: 'CANCELLED', message: '매칭을 거절했습니다.' };
  }

  // ─────────────────────────────────────
  // 매칭 수락 상태 조회
  // ─────────────────────────────────────

  async getMatchAcceptStatus(userId: string, matchId: string) {
    const match = await this.matchRepo.findOne({
      where: { id: matchId },
      relations: {
        acceptances: true,
        requesterProfile: { user: true } as any,
        opponentProfile: { user: true } as any,
      } as any,
    });

    if (!match) {
      throw AppError.notFound(ErrorCode.MATCH_NOT_FOUND);
    }

    // 참여자 확인
    const isParticipant =
      (match.requesterProfile as any).userId === userId ||
      (match.opponentProfile as any).userId === userId;

    if (!isParticipant) {
      throw AppError.forbidden(ErrorCode.MATCH_NOT_PARTICIPANT);
    }

    const acceptances = (match as any).acceptances ?? [];
    const myAcceptance = acceptances.find((a: any) => a.userId === userId);
    const opponentAcceptance = acceptances.find((a: any) => a.userId !== userId);

    return {
      matchId,
      status: match.status,
      myAcceptance: myAcceptance
        ? {
            accepted: myAcceptance.accepted,
            respondedAt: myAcceptance.respondedAt,
            expiresAt: myAcceptance.expiresAt,
          }
        : null,
      opponentAcceptance: opponentAcceptance
        ? {
            accepted: opponentAcceptance.accepted,
            respondedAt: opponentAcceptance.respondedAt,
          }
        : null,
    };
  }

  // ─────────────────────────────────────
  // 내 매칭 요청 목록
  // ─────────────────────────────────────

  async listMatchRequests(userId: string, query: ListMatchRequestsQuery) {
    const { status, sportType, cursor, limit } = query;

    const qb = this.matchRequestRepo
      .createQueryBuilder('mr')
      .leftJoinAndSelect('mr.sportsProfile', 'sp')
      .where('mr.requesterId = :userId', { userId });

    if (status) qb.andWhere('mr.status = :status', { status });
    if (sportType) qb.andWhere('mr.sportType = :sportType', { sportType });
    if (cursor) qb.andWhere('mr.createdAt < :cursor', { cursor: new Date(cursor) });

    qb.orderBy('mr.createdAt', 'DESC').take(limit + 1);

    const requests = await qb.getMany();

    const hasMore = requests.length > limit;
    const items = hasMore ? requests.slice(0, limit) : requests;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 내 매칭 목록
  // ─────────────────────────────────────

  async listMatches(userId: string, query: ListMatchesQuery) {
    const { status, cursor, limit } = query;

    const qb = this.matchRepo
      .createQueryBuilder('match')
      .leftJoinAndSelect('match.requesterProfile', 'rp')
      .leftJoinAndSelect('rp.user', 'rpUser')
      .leftJoinAndSelect('match.opponentProfile', 'op')
      .leftJoinAndSelect('op.user', 'opUser')
      .leftJoin(MatchRequest, 'mr', 'mr.id = match.matchRequestId')
      .addSelect('mr.isCasual', 'isCasual')
      .where('(rp.userId = :userId OR op.userId = :userId)', { userId });

    if (status) qb.andWhere('match.status = :status', { status });
    if (cursor) qb.andWhere('match.createdAt < :cursor', { cursor: new Date(cursor) });

    qb.orderBy('match.createdAt', 'DESC').take(limit + 1);

    const rawAndEntities = await qb.getRawAndEntities();
    const matches = rawAndEntities.entities;
    const rawRows = rawAndEntities.raw;

    const hasMore = matches.length > limit;
    const items = hasMore ? matches.slice(0, limit) : matches;
    const rawItems = hasMore ? rawRows.slice(0, limit) : rawRows;

    // 각 매칭에서 상대방 정보 추출
    const result = items.map((match, idx) => {
      const isRequester = (match.requesterProfile as any).userId === userId;
      const opponent = isRequester ? match.opponentProfile : match.requesterProfile;
      const isCasual = rawItems[idx]?.isCasual === true;

      return {
        id: match.id,
        status: match.status,
        sportType: match.sportType,
        isCasual,
        opponent: {
          id: (opponent as any).user?.id,
          nickname: (opponent as any).user?.nickname,
          profileImageUrl: (opponent as any).user?.profileImageUrl,
          tier: (opponent as any).tier,
          matchMessage: (opponent as any).matchMessage ?? null,
        },
        scheduledDate: match.scheduledDate,
        chatRoomId: match.chatRoomId,
        createdAt: match.createdAt,
      };
    });

    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;
    return { items: result, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 매칭 상세 조회
  // ─────────────────────────────────────

  async getMatch(userId: string, matchId: string) {
    const match = await this.matchRepo.findOne({
      where: { id: matchId },
      relations: {
        requesterProfile: { user: true } as any,
        opponentProfile: { user: true } as any,
      } as any,
    });

    if (!match) {
      throw AppError.notFound(ErrorCode.MATCH_NOT_FOUND);
    }

    // 참여자 확인
    const isParticipant =
      (match.requesterProfile as any).userId === userId ||
      (match.opponentProfile as any).userId === userId;

    if (!isParticipant) {
      throw AppError.forbidden(ErrorCode.MATCH_NOT_PARTICIPANT);
    }

    // 상대방 프로필에서 currentScore 제거 (점수 비공개 정책)
    const isRequester = (match.requesterProfile as any).userId === userId;
    const opponentProfile = isRequester ? match.opponentProfile : match.requesterProfile;
    const myProfile = isRequester ? match.requesterProfile : match.opponentProfile;

    // matchRequest에서 isCasual 조회
    let isCasual = false;
    if (match.matchRequestId) {
      const mr = await this.matchRequestRepo.findOne({
        where: { id: match.matchRequestId },
        select: { isCasual: true } as any,
      });
      isCasual = (mr as any)?.isCasual === true;
    }

    // 수락 상태 정보 조회 (PENDING_ACCEPT 상태에서만 의미 있음)
    let myAcceptance: { accepted: boolean | null; expiresAt: Date } | null = null;
    let opponentAcceptance: { accepted: boolean | null } | null = null;
    let timeRemainingSeconds = 0;

    const acceptances = await this.matchAcceptanceRepo.find({
      where: { matchId },
    });

    const myAcceptanceRecord = acceptances.find((a) => a.userId === userId);
    const opponentAcceptanceRecord = acceptances.find((a) => a.userId !== userId);

    if (myAcceptanceRecord) {
      myAcceptance = {
        accepted: myAcceptanceRecord.accepted,
        expiresAt: myAcceptanceRecord.expiresAt,
      };
      timeRemainingSeconds = Math.max(
        0,
        Math.floor((myAcceptanceRecord.expiresAt.getTime() - Date.now()) / 1000),
      );
    }

    if (opponentAcceptanceRecord) {
      opponentAcceptance = {
        accepted: opponentAcceptanceRecord.accepted,
      };
    }

    return {
      ...match,
      isCasual,
      myAcceptance,
      opponentAcceptance,
      timeRemainingSeconds,
      requesterProfile: isRequester
        ? myProfile
        : { ...opponentProfile, currentScore: undefined },
      opponentProfile: isRequester
        ? { ...opponentProfile, currentScore: undefined }
        : myProfile,
      opponent: {
        id: (opponentProfile as any).user?.id,
        nickname: (opponentProfile as any).user?.nickname,
        profileImageUrl: (opponentProfile as any).user?.profileImageUrl,
        tier: (opponentProfile as any).tier,
        wins: (opponentProfile as any).wins,
        losses: (opponentProfile as any).losses,
        draws: (opponentProfile as any).draws,
        matchMessage: (opponentProfile as any).matchMessage ?? null,
        gamesPlayed: (opponentProfile as any).gamesPlayed ?? 0,
        sportType: (opponentProfile as any).sportType,
      },
    };
  }

  // ─────────────────────────────────────
  // 경기 확정
  // ─────────────────────────────────────

  async confirmMatch(userId: string, matchId: string, dto: ConfirmMatchDto) {
    const match = await this.getMatch(userId, matchId);

    if (match.status !== 'CHAT') {
      throw AppError.badRequest(
        ErrorCode.MATCH_INVALID_STATUS,
        '채팅 상태에서만 경기를 확정할 수 있습니다.',
      );
    }

    const updateData: any = {
      status: 'CONFIRMED',
      confirmedAt: new Date(),
    };

    if (dto.scheduledDate) updateData.scheduledDate = new Date(dto.scheduledDate);
    if (dto.scheduledTime) {
      const [h, m] = dto.scheduledTime.split(':').map(Number);
      const timeDate = new Date(2000, 0, 1, h, m);
      updateData.scheduledTime = timeDate;
    }
    if (dto.venueName) updateData.venueName = dto.venueName;

    await this.matchRepo.update(matchId, updateData);

    // 위치 업데이트 (PostGIS)
    if (dto.venueLatitude && dto.venueLongitude) {
      const pointWkt = wktPoint(dto.venueLatitude, dto.venueLongitude);
      await this.dataSource.query(
        `UPDATE matches SET venue_location = ST_GeogFromText($1) WHERE id = $2::uuid`,
        [pointWkt, matchId],
      );
    }

    return this.matchRepo.findOne({ where: { id: matchId } });
  }

  // ─────────────────────────────────────
  // 매칭 취소
  // ─────────────────────────────────────

  async cancelMatch(userId: string, matchId: string, dto: CancelMatchDto) {
    const match = await this.getMatch(userId, matchId);

    if (['COMPLETED', 'CANCELLED'].includes(match.status)) {
      throw AppError.badRequest(
        ErrorCode.MATCH_INVALID_STATUS,
        '이미 완료되었거나 취소된 매칭입니다.',
      );
    }

    // 경기 24시간 전까지만 취소 가능
    if (match.scheduledDate) {
      const scheduledDateTime = new Date(match.scheduledDate);
      const hoursUntilGame =
        (scheduledDateTime.getTime() - Date.now()) / (1000 * 60 * 60);
      if (hoursUntilGame < 24) {
        throw AppError.badRequest(ErrorCode.MATCH_CANCEL_TOO_LATE);
      }
    }

    // CONFIRMED 상태 매칭 취소 시 노쇼 패널티 적용
    const isConfirmed = match.status === 'CONFIRMED';

    await this.matchRepo.update(matchId, {
      status: 'CANCELLED' as any,
      cancelledBy: userId,
      cancelReason: dto.reason,
    });

    if (isConfirmed) {
      await this.applyNoShowPenalty(userId, matchId, match);
    }

    return this.matchRepo.findOne({ where: { id: matchId } });
  }

  // ─────────────────────────────────────
  // 노쇼 패널티 적용
  // ─────────────────────────────────────

  private async applyNoShowPenalty(
    cancellerUserId: string,
    matchId: string,
    match: any,
  ): Promise<void> {
    // 취소한 유저와 상대방 스포츠 프로필 식별
    const isRequester = (match.requesterProfile as any).userId === cancellerUserId;
    const cancellerProfile = isRequester ? match.requesterProfile : match.opponentProfile;
    const opponentProfile = isRequester ? match.opponentProfile : match.requesterProfile;

    if (!cancellerProfile || !opponentProfile) return;

    const cancellerProfileId: string = (cancellerProfile as any).id;
    const opponentProfileId: string = (opponentProfile as any).id;
    const cancellerCurrentScore: number = (cancellerProfile as any).currentScore ?? 1000;
    const opponentCurrentScore: number = (opponentProfile as any).currentScore ?? 1000;

    // 점수 조정: 취소자 -30, 상대방 +15 (최소 100 보장)
    const cancellerNewScore = Math.max(100, cancellerCurrentScore - 30);
    const opponentNewScore = opponentCurrentScore + 15;

    await this.dataSource.transaction(async (manager) => {
      // 취소자 점수 차감 및 noShowCount 증가
      await manager
        .createQueryBuilder()
        .update(SportsProfile)
        .set({ currentScore: cancellerNewScore })
        .where('id = :id', { id: cancellerProfileId })
        .execute();

      // noShowCount 증가 후 밴 기간 계산
      await manager
        .createQueryBuilder()
        .update(SportsProfile)
        .set({ noShowCount: () => 'no_show_count + 1' })
        .where('id = :id', { id: cancellerProfileId })
        .execute();

      // 업데이트된 noShowCount 조회
      const updatedProfile = await manager.findOne(SportsProfile, {
        where: { id: cancellerProfileId },
        select: ['noShowCount'],
      });
      const noShowCount = updatedProfile?.noShowCount ?? 1;

      // 밴 기간 결정: 3회→24h, 5회→3days, 10회→7days
      let banHours = 0;
      if (noShowCount >= 10) banHours = 7 * 24;
      else if (noShowCount >= 5) banHours = 3 * 24;
      else if (noShowCount >= 3) banHours = 24;

      if (banHours > 0) {
        const banUntil = new Date(Date.now() + banHours * 60 * 60 * 1000);
        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({ matchBanUntil: banUntil })
          .where('id = :id', { id: cancellerProfileId })
          .execute();
      }

      // 상대방 점수 보상
      await manager
        .createQueryBuilder()
        .update(SportsProfile)
        .set({ currentScore: opponentNewScore })
        .where('id = :id', { id: opponentProfileId })
        .execute();

      // 점수 히스토리 기록 (취소자)
      await manager.save(ScoreHistory, [
        manager.create(ScoreHistory, {
          sportsProfileId: cancellerProfileId,
          gameId: null,
          changeType: ScoreChangeType.NO_SHOW_PENALTY,
          scoreBefore: cancellerCurrentScore,
          scoreChange: cancellerNewScore - cancellerCurrentScore,
          scoreAfter: cancellerNewScore,
        }),
        // 상대방 보상 히스토리
        manager.create(ScoreHistory, {
          sportsProfileId: opponentProfileId,
          gameId: null,
          changeType: ScoreChangeType.NO_SHOW_COMPENSATION,
          scoreBefore: opponentCurrentScore,
          scoreChange: 15,
          scoreAfter: opponentNewScore,
        }),
      ]);
    });

    // 알림 발송
    if (this.notificationService) {
      const opponentUserId: string = (opponentProfile as any).userId;
      await this.notificationService.sendBulk([
        {
          userId: cancellerUserId,
          type: 'MATCH_NO_SHOW_PENALTY',
          title: '노쇼 패널티 적용',
          body: `확정된 매칭을 취소하여 점수 -30점 패널티가 적용되었습니다.`,
          data: { matchId },
        },
        {
          userId: opponentUserId,
          type: 'MATCH_NO_SHOW_COMPENSATION',
          title: '매칭 취소 보상',
          body: `상대방이 매칭을 취소하여 점수 +15점 보상이 지급되었습니다.`,
          data: { matchId },
        },
      ]);
    }
  }

  // ─────────────────────────────────────
  // 매칭 요청 취소
  // ─────────────────────────────────────

  async cancelMatchRequest(userId: string, requestId: string) {
    const request = await this.matchRequestRepo.findOne({
      where: { id: requestId, requesterId: userId },
    });

    if (!request) {
      throw AppError.notFound(ErrorCode.MATCH_REQUEST_NOT_FOUND);
    }

    if (request.status !== MatchRequestStatus.WAITING) {
      throw AppError.badRequest(
        ErrorCode.MATCH_INVALID_STATUS,
        '대기 중인 매칭 요청만 취소할 수 있습니다.',
      );
    }

    await this.matchRequestRepo.update(requestId, {
      status: MatchRequestStatus.CANCELLED,
    });
  }

  // ─────────────────────────────────────
  // 활성 매칭 조회 (앱 시작 시 리다이렉트용)
  // ─────────────────────────────────────

  async getActiveMatch(userId: string) {
    const match = await this.matchRepo
      .createQueryBuilder('match')
      .leftJoinAndSelect('match.requesterProfile', 'rp')
      .leftJoinAndSelect('rp.user', 'rpUser')
      .leftJoinAndSelect('match.opponentProfile', 'op')
      .leftJoinAndSelect('op.user', 'opUser')
      .where(
        '(rp.userId = :userId OR op.userId = :userId) AND match.status IN (:...statuses)',
        { userId, statuses: ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'] },
      )
      .orderBy('match.createdAt', 'DESC')
      .getOne();

    if (!match) return null;

    const isRequester = (match.requesterProfile as any).userId === userId;
    const opponentProfile = isRequester ? match.opponentProfile : match.requesterProfile;

    // 수락 상태 조회 (PENDING_ACCEPT 상태에서 필요)
    let myAcceptance: { accepted: boolean | null; expiresAt: Date } | null = null;
    let opponentAcceptance: { accepted: boolean | null } | null = null;
    let timeRemainingSeconds = 0;

    if ((match.status as string) === 'PENDING_ACCEPT') {
      const acceptances = await this.matchAcceptanceRepo.find({
        where: { matchId: match.id },
      });
      const myAcc = acceptances.find((a) => a.userId === userId);
      const oppAcc = acceptances.find((a) => a.userId !== userId);

      if (myAcc) {
        myAcceptance = { accepted: myAcc.accepted, expiresAt: myAcc.expiresAt };
        timeRemainingSeconds = Math.max(
          0,
          Math.floor((myAcc.expiresAt.getTime() - Date.now()) / 1000),
        );
      }
      if (oppAcc) {
        opponentAcceptance = { accepted: oppAcc.accepted };
      }
    }

    return {
      id: match.id,
      status: match.status,
      sportType: match.sportType,
      chatRoomId: match.chatRoomId,
      createdAt: match.createdAt,
      myAcceptance,
      opponentAcceptance,
      timeRemainingSeconds,
      opponent: {
        id: (opponentProfile as any).user?.id,
        nickname: (opponentProfile as any).user?.nickname,
        profileImageUrl: (opponentProfile as any).user?.profileImageUrl,
        tier: (opponentProfile as any).tier,
      },
    };
  }

  // ─────────────────────────────────────
  // 매칭 포기 (활성 매칭 중 포기 버튼)
  // ─────────────────────────────────────

  async forfeitMatch(userId: string, matchId: string) {
    // 1) 매칭 조회 및 참여자 확인
    const match = await this.matchRepo.findOne({
      where: { id: matchId },
      relations: {
        requesterProfile: true,
        opponentProfile: true,
      } as any,
    });

    if (!match) {
      throw AppError.notFound(ErrorCode.MATCH_NOT_FOUND);
    }

    const isRequester = (match.requesterProfile as any).userId === userId;
    const isOpponent = (match.opponentProfile as any).userId === userId;

    if (!isRequester && !isOpponent) {
      throw AppError.forbidden(ErrorCode.MATCH_NOT_PARTICIPANT);
    }

    // 2) CHAT/CONFIRMED 상태에서는 포기 불가 — 경기 결과(승/패/무)만 가능
    if (['CHAT', 'CONFIRMED'].includes(match.status as string)) {
      throw AppError.badRequest(
        ErrorCode.MATCH_INVALID_STATUS,
        '매칭 성사 후에는 포기할 수 없습니다. 승리/패배/무승부만 가능합니다.',
      );
    }

    // PENDING_ACCEPT 상태에서만 포기 가능
    if ((match.status as string) !== 'PENDING_ACCEPT') {
      throw AppError.badRequest(
        ErrorCode.MATCH_INVALID_STATUS,
        '수락 대기 상태의 매칭에서만 포기할 수 있습니다.',
      );
    }

    const forfeitProfile = isRequester ? match.requesterProfile : match.opponentProfile;
    const winnerProfile = isRequester ? match.opponentProfile : match.requesterProfile;

    const forfeitProfileId = (forfeitProfile as any).id as string;
    const winnerProfileId = (winnerProfile as any).id as string;

    // 3) Glicko-2 계산 (포기 = 완전 패배)
    const forfeitGlickoIn: Glicko2Rating = {
      rating: (forfeitProfile as any).glickoRating ?? 1000,
      rd: (forfeitProfile as any).glickoRd ?? 350,
      volatility: (forfeitProfile as any).glickoVolatility ?? 0.06,
    };
    const winnerGlickoIn: Glicko2Rating = {
      rating: (winnerProfile as any).glickoRating ?? 1000,
      rd: (winnerProfile as any).glickoRd ?? 350,
      volatility: (winnerProfile as any).glickoVolatility ?? 0.06,
    };

    const forfeitResults: Glicko2Result[] = [{
      opponentRating: winnerGlickoIn.rating,
      opponentRd: winnerGlickoIn.rd,
      score: 0.0, // 패배
    }];
    const winnerResults: Glicko2Result[] = [{
      opponentRating: forfeitGlickoIn.rating,
      opponentRd: forfeitGlickoIn.rd,
      score: 1.0, // 승리
    }];

    const forfeitGlickoOut = updateGlicko2(forfeitGlickoIn, forfeitResults);
    const winnerGlickoOut = updateGlicko2(winnerGlickoIn, winnerResults);

    const forfeitScoreBefore = (forfeitProfile as any).currentScore ?? 1000;
    const winnerScoreBefore = (winnerProfile as any).currentScore ?? 1000;

    await this.dataSource.transaction(async (manager) => {
      // 4) 포기자 패배 처리 (Glicko-2 반영)
      await manager
        .createQueryBuilder()
        .update(SportsProfile)
        .set({
          currentScore: forfeitGlickoOut.rating,
          glickoRating: forfeitGlickoOut.rating,
          glickoRd: forfeitGlickoOut.rd,
          glickoVolatility: forfeitGlickoOut.volatility,
          glickoLastUpdatedAt: new Date(),
          losses: () => 'losses + 1',
          gamesPlayed: () => 'games_played + 1',
          winStreak: 0,
          lossStreak: () => 'loss_streak + 1',
          isPlacement: () => `CASE WHEN games_played + 1 < 5 THEN true ELSE false END`,
        })
        .where('id = :id', { id: forfeitProfileId })
        .execute();

      // 5) 승자 승리 처리 (Glicko-2 반영)
      await manager
        .createQueryBuilder()
        .update(SportsProfile)
        .set({
          currentScore: winnerGlickoOut.rating,
          glickoRating: winnerGlickoOut.rating,
          glickoRd: winnerGlickoOut.rd,
          glickoVolatility: winnerGlickoOut.volatility,
          glickoLastUpdatedAt: new Date(),
          wins: () => 'wins + 1',
          gamesPlayed: () => 'games_played + 1',
          winStreak: () => 'win_streak + 1',
          lossStreak: 0,
          isPlacement: () => `CASE WHEN games_played + 1 < 5 THEN true ELSE false END`,
        })
        .where('id = :id', { id: winnerProfileId })
        .execute();

      // 6) Game 레코드 생성 (VERIFIED 상태로 직접 저장)
      const game = manager.create(Game, {
        matchId,
        sportType: match.sportType,
        resultStatus: 'VERIFIED' as any,
        winnerProfileId,
        playedAt: new Date(),
        verifiedAt: new Date(),
        scoreData: { forfeit: true, forfeitUserId: userId },
      });
      const savedGame = await manager.save(Game, game);

      // 7) 점수 히스토리 기록
      await manager.save(ScoreHistory, [
        manager.create(ScoreHistory, {
          sportsProfileId: forfeitProfileId,
          gameId: savedGame.id,
          changeType: ScoreChangeType.GAME_LOSS,
          scoreBefore: forfeitScoreBefore,
          scoreChange: forfeitGlickoOut.rating - forfeitScoreBefore,
          scoreAfter: forfeitGlickoOut.rating,
          rdBefore: forfeitGlickoIn.rd,
          rdAfter: forfeitGlickoOut.rd,
          volatilityBefore: forfeitGlickoIn.volatility,
          volatilityAfter: forfeitGlickoOut.volatility,
        }),
        manager.create(ScoreHistory, {
          sportsProfileId: winnerProfileId,
          gameId: savedGame.id,
          changeType: ScoreChangeType.GAME_WIN,
          scoreBefore: winnerScoreBefore,
          scoreChange: winnerGlickoOut.rating - winnerScoreBefore,
          scoreAfter: winnerGlickoOut.rating,
          rdBefore: winnerGlickoIn.rd,
          rdAfter: winnerGlickoOut.rd,
          volatilityBefore: winnerGlickoIn.volatility,
          volatilityAfter: winnerGlickoOut.volatility,
        }),
      ]);

      // 8) 매칭 상태 COMPLETED로 변경
      await manager.update(Match, matchId, {
        status: 'COMPLETED' as any,
        completedAt: new Date(),
      });
    });

    // 9) 알림 발송
    const winnerUserId = (winnerProfile as any).userId as string;
    if (this.notificationService) {
      await this.notificationService.sendBulk([
        {
          userId,
          type: 'MATCH_FORFEIT',
          title: '매칭 포기',
          body: '매칭을 포기했습니다. 패배 처리되었습니다.',
          data: { matchId },
        },
        {
          userId: winnerUserId,
          type: 'MATCH_FORFEIT_WIN',
          title: '상대방이 포기했습니다',
          body: '상대방이 매칭을 포기하여 승리 처리되었습니다.',
          data: { matchId },
        },
      ]);
    }

    return {
      status: 'COMPLETED',
      forfeitUserId: userId,
      winnerUserId,
      scoreChanges: {
        forfeit: {
          before: forfeitScoreBefore,
          after: forfeitGlickoOut.rating,
          change: forfeitGlickoOut.rating - forfeitScoreBefore,
        },
        winner: {
          before: winnerScoreBefore,
          after: winnerGlickoOut.rating,
          change: winnerGlickoOut.rating - winnerScoreBefore,
        },
      },
    };
  }

  // ─────────────────────────────────────
  // 노쇼 신고
  // ─────────────────────────────────────

  async reportNoshow(reporterUserId: string, matchId: string) {
    // 1. Match 확인 — CHAT/CONFIRMED 상태만 신고 가능
    const match = await this.getMatch(reporterUserId, matchId);
    if (!['CHAT', 'CONFIRMED'].includes(match.status)) {
      throw AppError.badRequest(
        ErrorCode.MATCH_INVALID_STATUS,
        '진행 중인 매칭에서만 노쇼 신고가 가능합니다.',
      );
    }

    // 2. 상대방 식별
    const isRequester = (match.requesterProfile as any)?.userId === reporterUserId;
    const noshowUserId = isRequester
      ? (match.opponentProfile as any)?.userId
      : (match.requesterProfile as any)?.userId;
    const noshowProfileId = isRequester
      ? (match as any).opponentProfileId
      : (match as any).requesterProfileId;
    const reporterProfileId = isRequester
      ? (match as any).requesterProfileId
      : (match as any).opponentProfileId;

    if (!noshowUserId || !noshowProfileId) {
      throw AppError.badRequest(ErrorCode.MATCH_NOT_PARTICIPANT, '상대방 정보를 확인할 수 없습니다.');
    }

    // 3. 상대방 noShowCount 증가 (atomic)
    await this.sportsProfileRepo
      .createQueryBuilder()
      .update()
      .set({ noShowCount: () => 'no_show_count + 1' })
      .where('id = :id', { id: noshowProfileId })
      .execute();

    // 4. 노쇼 횟수 확인 후 밴 적용
    const profile = await this.sportsProfileRepo.findOne({ where: { id: noshowProfileId } });
    const noShowCount = profile?.noShowCount ?? 0;

    if (noShowCount >= 2) {
      // 2회 이상: 계정 영구 정지 (SUSPENDED)
      await this.dataSource.getRepository(User).update(
        { id: noshowUserId },
        { status: 'SUSPENDED' as any },
      );
    } else {
      // 1회: 7일 매칭 밴
      const banUntil = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
      await this.sportsProfileRepo.update(noshowProfileId, { matchBanUntil: banUntil } as any);
    }

    // 5. 매칭 완료 처리
    await this.matchRepo.update(matchId, {
      status: 'COMPLETED' as any,
      completedAt: new Date(),
    });

    // 6. displayScore/currentScore 패널티 적용 (atomic)
    // 노쇼 유저 -30 (최소 100점)
    await this.sportsProfileRepo
      .createQueryBuilder()
      .update()
      .set({
        displayScore: () => 'GREATEST(100, display_score - 30)',
        currentScore: () => 'GREATEST(100, current_score - 30)',
      })
      .where('id = :id', { id: noshowProfileId })
      .execute();

    // 신고자 +15
    await this.sportsProfileRepo
      .createQueryBuilder()
      .update()
      .set({
        displayScore: () => 'display_score + 15',
        currentScore: () => 'current_score + 15',
      })
      .where('id = :id', { id: reporterProfileId })
      .execute();

    // 7. 알림 발송
    if (this.notificationService) {
      await this.notificationService.send({
        userId: noshowUserId,
        type: 'MATCH_NO_SHOW_PENALTY',
        title: '노쇼 패널티',
        body: noShowCount >= 2
          ? '2회 노쇼로 계정이 정지되었습니다.'
          : '노쇼 신고로 7일간 매칭이 제한됩니다.',
        data: { matchId },
      });
    }

    return { message: '노쇼 신고가 접수되었습니다.' };
  }
}
