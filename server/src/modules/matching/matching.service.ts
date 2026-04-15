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
import { redis, bullmqRedis } from '../../config/redis.js';
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
  RankingEntry,
  Report,
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
  // 매칭 라이프사이클 이벤트 발행 헬퍼
  // Redis pub/sub을 통해 Socket.io 서버로 이벤트 전달
  // ─────────────────────────────────────

  private async emitMatchEvent(event: string, data: Record<string, any>): Promise<void> {
    try {
      await redis.publish('match_lifecycle', JSON.stringify({ event, ...data }));
    } catch (err) {
      // 이벤트 발행 실패는 비치명적 — 로그만 남기고 계속 진행
      console.warn(`[MatchService] emitMatchEvent failed (${event}):`, err);
    }
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
      const now = new Date();
      const kstNow = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Seoul' }));
      const kstHour = kstNow.getHours();
      const today = `${kstNow.getFullYear()}-${String(kstNow.getMonth() + 1).padStart(2, '0')}-${String(kstNow.getDate()).padStart(2, '0')}`;
      const tomorrowDate = new Date(kstNow.getFullYear(), kstNow.getMonth(), kstNow.getDate() + 1);
      const tomorrow = `${tomorrowDate.getFullYear()}-${String(tomorrowDate.getMonth() + 1).padStart(2, '0')}-${String(tomorrowDate.getDate()).padStart(2, '0')}`;

      // 밤 11시 이후 당일 매칭 차단
      if (desiredDate === today && kstHour >= 23) {
        throw AppError.badRequest(
          ErrorCode.VALIDATION_ERROR,
          '밤 11시 이후에는 당일 매칭 요청을 할 수 없습니다.',
        );
      }

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
        .andWhere('mr.status = :status', { status: 'WAITING' })
        .getOne();

      if (existingRequestForDate) {
        throw AppError.conflict(
          ErrorCode.MATCH_ALREADY_EXISTS,
          '해당 날짜에 이미 대기 중인 매칭 요청이 있습니다.',
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

    // ─── CONFIRMED 매칭 중 결과 미입력 차단 ───
    // CONFIRMED 상태인 매칭에 연결된 게임이 있고 resultStatus가 PENDING이면 신규 매칭 불가
    const confirmedMatchesWithPendingResult = await this.dataSource.query<Array<{ count: string }>>(
      `SELECT COUNT(*)::int AS count
       FROM matches m
       JOIN sports_profiles rp ON rp.id = m.requester_profile_id
       JOIN sports_profiles op ON op.id = m.opponent_profile_id
       JOIN games g ON g.match_id = m.id
       WHERE (rp.user_id = $1::uuid OR op.user_id = $1::uuid)
         AND m.status = 'CONFIRMED'
         AND g.result_status = 'PENDING'`,
      [userId],
    );

    if (parseInt(confirmedMatchesWithPendingResult[0]?.count ?? '0', 10) > 0) {
      throw AppError.conflict(
        ErrorCode.MATCH_ALREADY_EXISTS,
        '결과 입력 대기 중인 매칭이 있습니다. 결과 입력 후 다시 신청해주세요.',
      );
    }

    // ─── 총 활성 매칭/요청 2개 제한 (COMPLETED/CANCELLED/EXPIRED 제외) ───
    const totalActiveRequests = await this.matchRequestRepo
      .createQueryBuilder('mr')
      .where('mr.requester_id = :userId', { userId })
      .andWhere('mr.status = :status', { status: 'WAITING' })
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
        '진행 중인 매칭이 2개 있습니다. 완료 후 다시 신청해주세요.',
      );
    }

    // 캐주얼 모드 처리: isCasual이 true이면 requestType을 CASUAL로, MMR 범위를 ±600으로 설정
    const isCasual = (dto as any).isCasual === true;
    if (isCasual) {
      (dto as any).requestType = RequestType.CASUAL;
      // 캐주얼은 더 넓은 MMR 범위 적용 (기본값 덮어쓰기)
      if (dto.minOpponentScore === 800 && dto.maxOpponentScore === 1200) {
        dto.minOpponentScore = Math.max(100, sportsProfile.currentScore - 600);
        dto.maxOpponentScore = sportsProfile.currentScore + 600;
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

    // ageRange → minAge/maxAge 계산 (유저 birthDate 기준)
    let resolvedMinAge: number | null = dto.minAge ?? null;
    let resolvedMaxAge: number | null = dto.maxAge ?? null;
    if (dto.ageRange !== undefined && dto.ageRange !== null) {
      const userRows = await this.dataSource.query<Array<{ birthDate: string | null }>>(
        `SELECT birth_date AS "birthDate" FROM users WHERE id = $1::uuid`,
        [userId],
      );
      const birthDate = userRows[0]?.birthDate;
      if (birthDate) {
        const myAge = calculateAge(new Date(birthDate));
        resolvedMinAge = Math.max(14, myAge - dto.ageRange);
        resolvedMaxAge = Math.min(100, myAge + dto.ageRange);
      }
    }

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
        resolvedMinAge,
        resolvedMaxAge,
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

    // WAITING이면 매칭 큐 Worker에 이벤트 발행 (즉시 매칭 시도)
    if ((updatedRequest?.status ?? 'WAITING') === 'WAITING') {
      try {
        const { triggerMatchingProcess } = await import('../../workers/matching-queue.worker.js');
        await triggerMatchingProcess(dto.pinId, dto.sportType);
      } catch (e) {
        // 이벤트 발행 실패해도 매칭 요청 자체는 정상 반환
        console.warn('[MatchService] triggerMatchingProcess failed:', (e as Error).message);
      }
    }

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

    // 점수 차이에 관계없이 최선의 후보와 즉시 매칭
    await this.createMatch(requestId, bestCandidate, opts);

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

      // 양쪽 요청의 시간대 resolve (ANY가 아닌 쪽 우선)
      const [reqMr, oppMr] = await Promise.all([
        manager.findOne(MatchRequest, { where: { id: requestId }, select: { desiredDate: true, desiredTimeSlot: true } as any }),
        manager.findOne(MatchRequest, { where: { id: bestCandidate.matchRequestId }, select: { desiredDate: true, desiredTimeSlot: true } as any }),
      ]);
      const slotA = (reqMr as any)?.desiredTimeSlot;
      const slotB = (oppMr as any)?.desiredTimeSlot;
      const resolvedSlot = (slotA && slotA !== 'ANY') ? slotA : (slotB && slotB !== 'ANY') ? slotB : (slotA || slotB || null);

      // 매칭 생성 (ChatRoom 없이 PENDING_ACCEPT 상태)
      const match = manager.create(Match, {
        matchRequestId: requestId,
        requesterProfileId: requesterProfile.id,
        opponentProfileId: bestCandidate.id,
        pinId: pinId ?? null,
        sportType: opts.sportType as any,
        status: 'PENDING_ACCEPT' as any,
        desiredDate: (reqMr as any)?.desiredDate ?? null,
        desiredTimeSlot: resolvedSlot,
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

      // 매칭 수락 리마인더 job 등록 (5분전, 3분전, 1분전)
      // 수락 만료가 10분이므로 생성 후 5분, 7분, 9분에 발송
      const reminders = [
        { delay: 5 * 60 * 1000, label: '5분' },
        { delay: 7 * 60 * 1000, label: '3분' },
        { delay: 9 * 60 * 1000, label: '1분' },
      ];
      for (const { delay, label } of reminders) {
        for (const userId of [opts.requesterUserId, bestCandidate.userId]) {
          await this.matchAcceptTimeoutQueue.add(
            'accept-reminder',
            {
              matchId: savedMatch.id,
              requesterUserId: opts.requesterUserId,
              opponentUserId: bestCandidate.userId,
              requesterRequestId: requestId,
              opponentRequestId: bestCandidate.matchRequestId,
              reminderUserId: userId,
              reminderLabel: label,
            } as any,
            {
              delay,
              jobId: `accept-reminder-${savedMatch.id}-${userId}-${label}`,
            },
          );
        }
      }

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
              deepLink: `/matches/${savedMatch.id}/accept`,
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
              deepLink: `/matches/${savedMatch.id}/accept`,
            },
          },
        ]);
      }

      // 실시간 매칭 성사 이벤트 발행 (소켓 룸 기반)
      // matchrequest:{requestId} 룸에서 대기 중인 클라이언트에게 직접 전달
      await Promise.all([
        this.emitMatchEvent('MATCH_FOUND', {
          requestId,
          data: { matchId: savedMatch.id, status: 'PENDING_ACCEPT' },
        }),
        this.emitMatchEvent('MATCH_FOUND', {
          requestId: bestCandidate.matchRequestId,
          data: { matchId: savedMatch.id, status: 'PENDING_ACCEPT' },
        }),
      ]);
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
      let createdChatRoomId: string | undefined;
      let notifData: any = null;

      await this.dataSource.transaction(async (manager) => {
        // ChatRoom 생성
        const chatRoom = manager.create(ChatRoom, { roomType: 'MATCH' as any });
        const savedChatRoom = await manager.save(ChatRoom, chatRoom);
        createdChatRoomId = savedChatRoom.id;

        // 4자리 인증번호 생성 (각 유저에게 하나씩)
        const genCode = () => String(Math.floor(1000 + Math.random() * 9000));
        let requesterCode = genCode();
        let opponentCode = genCode();
        // 서로 같으면 재생성
        while (opponentCode === requesterCode) opponentCode = genCode();

        // Match 상태 CHAT으로 변경 + chatRoomId 연결 + 인증번호 저장
        await manager.update(Match, matchId, {
          status: 'CHAT' as any,
          chatRoomId: savedChatRoom.id,
          requesterVerificationCode: requesterCode,
          opponentVerificationCode: opponentCode,
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

        // 시스템 메시지 삽입 (채팅방 생성 1초 전 시간으로 설정 — 항상 맨 위에 표시)
        await manager.save(Message, manager.create(Message, {
          chatRoomId: savedChatRoom.id,
          senderId: match?.requesterProfile?.userId,
          messageType: 'SYSTEM' as any,
          content: '매칭이 성사되었습니다! 상대방과 경기 일정을 조율해 보세요.',
          createdAt: new Date(Date.now() - 1000),
        }));

        // 트랜잭션 내부에서 알림용 데이터 수집
        notifData = match ? {
          requesterUserId: (match.requesterProfile as any).userId,
          opponentUserId: (match.opponentProfile as any).userId,
          requesterNickname: (match.requesterProfile as any).user?.nickname ?? '',
          opponentNickname: (match.opponentProfile as any).user?.nickname ?? '',
          chatRoomId: savedChatRoom.id,
        } : null;
      });

      // 양측 수락 완료 → CHAT 상태 실시간 전달 (트랜잭션 커밋 후)
      console.info(`[MatchAccept] 양측 수락 완료 — MATCH_STATUS_CHANGED 발행: matchId=${matchId}, chatRoomId=${createdChatRoomId}`);
      await this.emitMatchEvent('MATCH_STATUS_CHANGED', {
        matchId,
        data: { matchId, status: 'CHAT', chatRoomId: createdChatRoomId },
      });

      // 양측 알림 (트랜잭션 커밋 후 발송 — 클라이언트가 조회 시 최신 데이터 보장)
      console.info(`[MatchAccept] MATCH_BOTH_ACCEPTED 알림 발송: notifData=${JSON.stringify(notifData)}, hasService=${!!this.notificationService}`);
      if (this.notificationService && notifData) {
        await this.notificationService.sendBulk([
          {
            userId: notifData.requesterUserId,
            type: 'MATCH_BOTH_ACCEPTED',
            title: '매칭이 확정되었습니다!',
            body: `${notifData.opponentNickname}님과의 매칭이 확정되었습니다.`,
            data: { matchId, chatRoomId: notifData.chatRoomId, deepLink: `/matches/${matchId}` },
          },
          {
            userId: notifData.opponentUserId,
            type: 'MATCH_BOTH_ACCEPTED',
            title: '매칭이 확정되었습니다!',
            body: `${notifData.requesterNickname}님과의 매칭이 확정되었습니다.`,
            data: { matchId, chatRoomId: notifData.chatRoomId, deepLink: `/matches/${matchId}` },
          },
        ]);
      }

      // 핀 활동 기록 (양측 유저)
      try {
        const matchForPin = await this.matchRepo.findOne({ where: { id: matchId } });
        if (matchForPin?.pinId) {
          const { PinsService } = await import('../pins/pins.service.js');
          const pinsService = new PinsService();
          const requesterUserId = (await this.matchAcceptanceRepo.findOne({ where: { matchId, userId } }))
            ? userId : undefined;
          const opponentUserId = opponentAcceptance.userId;
          const userIds = [userId, opponentUserId].filter(Boolean) as string[];
          await pinsService.recordActivities(matchForPin.pinId, userIds);
        }
      } catch { /* 활동 기록 실패해도 매칭에 영향 없음 */ }

      return { status: 'MATCHED', message: '매칭이 확정되었습니다!', chatRoomId: createdChatRoomId };
    }

    // 상대가 아직 응답 안 했으면 대기 알림
    if (this.notificationService) {
      await this.notificationService.send({
        userId,
        type: 'MATCH_WAITING_OPPONENT',
        title: '매칭 수락 완료',
        body: '상대방의 응답을 기다리고 있습니다.',
        data: { matchId, deepLink: `/matches/${matchId}` },
      });
    }

    // 한 명 수락 → 상태 변경 실시간 전달 (수락자가 기다리는 화면 갱신용)
    await this.emitMatchEvent('MATCH_STATUS_CHANGED', {
      matchId,
      data: { matchId, status: 'PENDING_ACCEPT', subStatus: 'WAITING_OPPONENT' },
    });

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

      // 4) 거절자의 matchRequest → CANCELLED (큐에서 완전 제거)
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
          status: MatchRequestStatus.CANCELLED,
        });
      }

      // 상대방의 matchRequest → WAITING (재매칭 가능)
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

      // 6) 거절 쿨다운 적용 (분 단위)
      let cooldownMinutes = 0;
      const rejectionCount = (updatedUser as any)?.rejectionCount ?? 0;
      if (rejectionCount >= 20) {
        cooldownMinutes = 60; // 1시간
      } else if (rejectionCount >= 10) {
        cooldownMinutes = 30;
      } else if (rejectionCount >= 5) {
        cooldownMinutes = 15;
      }

      if (cooldownMinutes > 0) {
        const cooldownUntil = new Date(Date.now() + cooldownMinutes * 60 * 1000);
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
            changeType: ScoreChangeType.NO_SHOW_COMPENSATION,
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

    // 거절 → CANCELLED 상태 실시간 전달
    await this.emitMatchEvent('MATCH_STATUS_CHANGED', {
      matchId,
      data: { matchId, status: 'CANCELLED', reason: 'REJECTED' },
    });

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
    const { status, sportType, cursor } = query;
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);

    const qb = this.matchRequestRepo
      .createQueryBuilder('mr')
      .leftJoinAndSelect('mr.sportsProfile', 'sp')
      .leftJoin('pins', 'p', 'p.id = mr.pin_id')
      .addSelect('p.name', 'pinName')
      .where('mr.requesterId = :userId', { userId });

    if (status) qb.andWhere('mr.status = :status', { status });
    if (sportType) qb.andWhere('mr.sportType = :sportType', { sportType });
    if (cursor) qb.andWhere('mr.createdAt < :cursor', { cursor: new Date(cursor) });

    qb.orderBy('mr.createdAt', 'DESC').take(limit + 1);

    const rawAndEntities = await qb.getRawAndEntities();
    const requests = rawAndEntities.entities;
    const rawRows = rawAndEntities.raw;

    const hasMore = requests.length > limit;
    const items = hasMore ? requests.slice(0, limit) : requests;
    const rawItems = hasMore ? rawRows.slice(0, limit) : rawRows;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    const result = items.map((req, idx) => ({
      ...req,
      pinName: rawItems[idx]?.pinName ?? null,
    }));

    return { items: result, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 내 매칭 목록
  // ─────────────────────────────────────

  async listMatches(userId: string, query: ListMatchesQuery) {
    const { status, cursor } = query;
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);

    const qb = this.matchRepo
      .createQueryBuilder('match')
      .leftJoinAndSelect('match.requesterProfile', 'rp')
      .leftJoin('rp.user', 'rpUser')
      .addSelect(['rpUser.id', 'rpUser.nickname', 'rpUser.profileImageUrl'])
      .leftJoinAndSelect('match.opponentProfile', 'op')
      .leftJoin('op.user', 'opUser')
      .addSelect(['opUser.id', 'opUser.nickname', 'opUser.profileImageUrl'])
      .leftJoin(MatchRequest, 'mr', 'mr.id = match.matchRequestId')
      .addSelect('mr.isCasual', 'isCasual')
      .addSelect('mr.desired_date', 'mr_desired_date')
      .addSelect('mr.desired_time_slot', 'mr_desired_time_slot')
      .addSelect('mr.pin_id', 'mr_pin_id')
      .leftJoin('pins', 'pin', 'pin.id = mr.pin_id')
      .addSelect('pin.name', 'pin_name')
      .leftJoin(Game, 'game', 'game.match_id = match.id')
      .addSelect('game.id', 'game_id')
      .addSelect('game.winner_profile_id', 'game_winner_profile_id')
      .addSelect('game.result_status', 'game_result_status')
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

    // PENDING_ACCEPT 매칭의 수락 정보를 일괄 조회
    const pendingMatchIds = items
      .filter((m) => (m.status as string) === 'PENDING_ACCEPT')
      .map((m) => m.id);
    let acceptancesMap = new Map<string, MatchAcceptance[]>();
    if (pendingMatchIds.length > 0) {
      const allAcceptances = await this.matchAcceptanceRepo.find({
        where: pendingMatchIds.map((id) => ({ matchId: id })),
      });
      for (const acc of allAcceptances) {
        const list = acceptancesMap.get(acc.matchId) ?? [];
        list.push(acc);
        acceptancesMap.set(acc.matchId, list);
      }
    }

    // 완료된 매칭의 점수 변동을 일괄 조회
    const completedGameIds = items
      .map((m, idx) => ({ gameId: rawItems[idx]?.game_id as string | null, match: m }))
      .filter((x) => x.match.status === 'COMPLETED' && x.gameId)
      .map((x) => x.gameId!);
    const scoreChangeMap = new Map<string, number>(); // gameId+profileId → scoreChange
    if (completedGameIds.length > 0) {
      const scoreRows = await this.dataSource.query<Array<{ game_id: string; sports_profile_id: string; score_change: number }>>(
        `SELECT game_id, sports_profile_id, score_change FROM score_histories WHERE game_id = ANY($1)`,
        [completedGameIds],
      );
      for (const row of scoreRows) {
        scoreChangeMap.set(`${row.game_id}_${row.sports_profile_id}`, row.score_change);
      }
    }

    // 각 매칭에서 상대방 정보 추출
    const result = items.map((match, idx) => {
      const isRequester = (match.requesterProfile as any).userId === userId;
      const opponent = isRequester ? match.opponentProfile : match.requesterProfile;
      const isCasual = rawItems[idx]?.isCasual === true;

      // 완료된 매칭의 승패 정보
      const winnerProfileId = rawItems[idx]?.game_winner_profile_id ?? null;
      const gameResultStatus = rawItems[idx]?.game_result_status ?? null;
      const myProfileId = isRequester
        ? (match.requesterProfile as any).id
        : (match.opponentProfile as any).id;
      let gameResult: string | null = null; // WIN | LOSS | DRAW | DISPUTED | NO_RESULT
      if (match.status === 'COMPLETED' && winnerProfileId) {
        gameResult = winnerProfileId === myProfileId ? 'WIN' : 'LOSS';
      } else if (match.status === 'COMPLETED' && gameResultStatus === 'VERIFIED' && !winnerProfileId) {
        gameResult = 'DRAW';
      } else if (match.status === 'COMPLETED' && gameResultStatus === 'DISPUTED') {
        gameResult = 'DISPUTED';
      } else if (match.status === 'COMPLETED' && (!gameResultStatus || gameResultStatus === 'PENDING')) {
        gameResult = 'NO_RESULT';
      }

      // PENDING_ACCEPT 상태일 때만 myAcceptance 포함
      let myAcceptance: { accepted: boolean | null; expiresAt: Date | null } | null = null;
      if ((match.status as string) === 'PENDING_ACCEPT') {
        const accs = acceptancesMap.get(match.id) ?? [];
        const myAcc = accs.find((a) => a.userId === userId);
        if (myAcc) {
          myAcceptance = {
            accepted: myAcc.accepted ?? null,
            expiresAt: myAcc.expiresAt ?? null,
          };
        }
      }

      // 내 점수 변동 조회
      const gameId = rawItems[idx]?.game_id as string | null;
      const myScoreChange = gameId ? (scoreChangeMap.get(`${gameId}_${myProfileId}`) ?? null) : null;


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
        gameResult,
        myScoreChange,
        pinName: rawItems[idx]?.pin_name ?? null,
        desiredDate: match.desiredDate ?? rawItems[idx]?.mr_desired_date ?? null,
        desiredTimeSlot: (match as any).desiredTimeSlot ?? rawItems[idx]?.mr_desired_time_slot ?? null,
        ...(myAcceptance !== null ? { myAcceptance } : {}),
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

    // matchRequest에서 isCasual, desiredDate, desiredTimeSlot 조회 + 핀 이름 단일 쿼리로 통합
    let isCasual = false;
    let desiredDate: string | null = null;
    let desiredTimeSlot: string | null = null;
    let pinName: string | null = null;

    if (match.matchRequestId) {
      const mrRows = await this.dataSource.query<
        Array<{
          isCasual: boolean;
          desiredDate: string | null;
          desiredTimeSlot: string | null;
          pinName: string | null;
        }>
      >(
        `SELECT
          mr.is_casual AS "isCasual",
          mr.desired_date AS "desiredDate",
          mr.desired_time_slot AS "desiredTimeSlot",
          p.name AS "pinName"
        FROM match_requests mr
        LEFT JOIN pins p ON p.id = mr.pin_id
        WHERE mr.id = $1::uuid
        LIMIT 1`,
        [match.matchRequestId],
      );

      if (mrRows.length > 0) {
        isCasual = mrRows[0].isCasual === true;
        desiredDate = mrRows[0].desiredDate ?? null;
        desiredTimeSlot = mrRows[0].desiredTimeSlot ?? null;
        pinName = mrRows[0].pinName ?? null;
      }

      // 상대 매칭 요청의 시간대 확인: ANY(하루종일) vs 구체적 시간 → 구체적 시간 우선
      // matchRequestId는 항상 매칭의 requester 것이므로, 상대는 항상 opponentProfile
      if (desiredTimeSlot === 'ANY' || desiredTimeSlot === null) {
        const opponentProfileId = match.opponentProfile.id;
        const opponentMr = await this.dataSource.query<
          Array<{ desiredTimeSlot: string | null }>
        >(
          `SELECT mr.desired_time_slot AS "desiredTimeSlot"
           FROM match_requests mr
           WHERE mr.sports_profile_id = $1::uuid
             AND mr.status = 'MATCHED'
             AND mr.sport_type = $2
           ORDER BY mr.updated_at DESC
           LIMIT 1`,
          [opponentProfileId, match.sportType],
        );
        const oppSlot = opponentMr[0]?.desiredTimeSlot ?? null;
        if (oppSlot && oppSlot !== 'ANY') {
          desiredTimeSlot = oppSlot;
        }
      }
    } else if (match.pinId) {
      // matchRequestId가 없는 경우: 양쪽 매칭 요청에서 시간대 조회
      const bothMr = await this.dataSource.query<
        Array<{
          desiredDate: string | null;
          desiredTimeSlot: string | null;
          pinName: string | null;
          isCasual: boolean;
        }>
      >(
        `SELECT
          mr.is_casual AS "isCasual",
          mr.desired_date AS "desiredDate",
          mr.desired_time_slot AS "desiredTimeSlot",
          p.name AS "pinName"
        FROM match_requests mr
        LEFT JOIN pins p ON p.id = mr.pin_id
        WHERE mr.sports_profile_id IN ($1::uuid, $2::uuid)
          AND mr.status = 'MATCHED'
          AND mr.sport_type = $3
        ORDER BY mr.updated_at DESC
        LIMIT 2`,
        [match.requesterProfile.id, match.opponentProfile.id, match.sportType],
      );

      if (bothMr.length > 0) {
        pinName = bothMr[0].pinName ?? null;
        desiredDate = bothMr[0].desiredDate ?? null;
        isCasual = bothMr[0].isCasual === true;
        // 구체적 시간 우선: ANY가 아닌 것을 선택
        const specificSlot = bothMr.find(r => r.desiredTimeSlot && r.desiredTimeSlot !== 'ANY');
        desiredTimeSlot = specificSlot?.desiredTimeSlot ?? bothMr[0].desiredTimeSlot ?? null;
      } else {
        // 매칭 요청 없으면 핀 이름만
        const pinRows = await this.dataSource.query<Array<{ name: string }>>(
          `SELECT name FROM pins WHERE id = $1::uuid LIMIT 1`,
          [match.pinId],
        );
        pinName = pinRows[0]?.name ?? null;
      }
    }

    // 상대와의 만남 횟수 조회 (완료된 매칭 수)
    const myUserId = userId;
    const opponentUserId = (opponentProfile as any).user?.id;
    let encounterCount = 0;
    if (opponentUserId) {
      const result = await this.matchRepo
        .createQueryBuilder('m')
        .leftJoin('m.requesterProfile', 'rp')
        .leftJoin('rp.user', 'ru')
        .leftJoin('m.opponentProfile', 'op')
        .leftJoin('op.user', 'ou')
        .where('m.status = :status', { status: 'COMPLETED' })
        .andWhere(
          '((ru.id = :myId AND ou.id = :oppId) OR (ru.id = :oppId AND ou.id = :myId))',
          { myId: myUserId, oppId: opponentUserId },
        )
        .getCount();
      encounterCount = result;
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

    // Game 조회 (결과 제출 여부 + 승패 판정 포함)
    const game = await this.dataSource.getRepository(Game).findOne({
      where: { matchId },
      select: { id: true, requesterClaimedResult: true, opponentClaimedResult: true, winnerProfileId: true, resultStatus: true } as any,
    });
    const myResultSubmitted = game
      ? (isRequester ? game.requesterClaimedResult != null : game.opponentClaimedResult != null)
      : false;
    const opponentClaimedResult = game
      ? (isRequester ? game.opponentClaimedResult : game.requesterClaimedResult)
      : null;

    // 승패 결과 계산
    const myProfileId = (myProfile as any).id;
    let gameResult: string | null = null;
    if (match.status === 'COMPLETED' && game?.winnerProfileId) {
      gameResult = game.winnerProfileId === myProfileId ? 'WIN' : 'LOSS';
    } else if (match.status === 'COMPLETED' && game?.resultStatus === 'VERIFIED' && !game?.winnerProfileId) {
      gameResult = 'DRAW';
    } else if (match.status === 'COMPLETED' && game?.resultStatus === 'DISPUTED') {
      gameResult = 'DISPUTED';
    } else if (match.status === 'COMPLETED' && (!game?.resultStatus || game?.resultStatus === 'PENDING')) {
      gameResult = 'NO_RESULT';
    }

    // 내 인증번호 (requester이면 requesterVerificationCode, 아니면 opponentVerificationCode)
    const myVerificationCode = isRequester
      ? match.requesterVerificationCode
      : match.opponentVerificationCode;

    return {
      ...match,
      gameId: game?.id ?? null,
      myResultSubmitted,
      opponentClaimedResult,
      gameResult,
      isCasual,
      pinName,
      encounterCount,
      desiredDate: match.desiredDate ?? desiredDate,
      desiredTimeSlot: (match as any).desiredTimeSlot ?? desiredTimeSlot,
      myAcceptance,
      opponentAcceptance,
      timeRemainingSeconds,
      myVerificationCode,
      requesterProfile: isRequester
        ? myProfile
        : { ...opponentProfile, currentScore: undefined },
      opponentProfile: isRequester
        ? { ...opponentProfile, currentScore: undefined }
        : myProfile,
      opponent: await (async () => {
        // 핀별 점수/티어 조회 (해당 핀에서의 ranking_entry)
        let pinScore: number | null = null;
        let pinTier: string | null = null;
        let pinGamesPlayed: number | null = null;
        if (match.pinId) {
          const oppRankEntry = await this.dataSource.getRepository(RankingEntry).findOne({
            where: {
              pinId: match.pinId,
              sportsProfileId: (opponentProfile as any).id,
              sportType: (opponentProfile as any).sportType,
            },
          });
          if (oppRankEntry) {
            pinScore = oppRankEntry.score;
            pinTier = oppRankEntry.tier;
            pinGamesPlayed = oppRankEntry.gamesPlayed;
          }
        }
        const hasPinRecord = pinScore !== null;
        return {
          id: (opponentProfile as any).user?.id,
          nickname: (opponentProfile as any).user?.nickname,
          profileImageUrl: (opponentProfile as any).user?.profileImageUrl,
          tier: pinTier ?? (opponentProfile as any).tier,
          wins: (opponentProfile as any).wins,
          losses: (opponentProfile as any).losses,
          draws: (opponentProfile as any).draws,
          matchMessage: (opponentProfile as any).matchMessage ?? null,
          gamesPlayed: pinGamesPlayed ?? (opponentProfile as any).gamesPlayed ?? 0,
          sportType: (opponentProfile as any).sportType,
          displayScore: hasPinRecord ? pinScore : null,
          isPlacement: !hasPinRecord,
          placementGamesRemaining: hasPinRecord ? null : 5,
        };
      })(),
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

    // 매칭 취소 시 항상 패널티 적용 (취소자 -30, 상대방 +15)
    const shouldPenalize = true;

    await this.matchRepo.update(matchId, {
      status: 'CANCELLED' as any,
      cancelledBy: userId,
      cancelReason: dto.reason,
    });

    // matchRequest 상태도 EXPIRED로 변경 (중복 매칭 요청 방지)
    if (match.matchRequestId) {
      await this.matchRequestRepo.update(match.matchRequestId, {
        status: 'EXPIRED' as any,
      });
    }

    if (shouldPenalize) {
      await this.applyNoShowPenalty(userId, matchId, match);
    }

    // 양쪽 유저에게 MATCH_CANCELLED 알림 → 앱에서 즉시 반영
    if (this.notificationService) {
      const opponentUserId =
        (match.requesterProfile as any).userId === userId
          ? (match.opponentProfile as any).userId
          : (match.requesterProfile as any).userId;
      await this.notificationService.send({
        userId: opponentUserId,
        type: 'MATCH_CANCELLED',
        title: '매칭 취소',
        body: '상대방이 매칭을 취소했습니다.',
        data: { matchId, deepLink: '/matches' },
      });
    }

    // 취소 → CANCELLED 상태 실시간 전달
    await this.emitMatchEvent('MATCH_STATUS_CHANGED', {
      matchId,
      data: { matchId, status: 'CANCELLED' },
    });

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

  async reportNoshow(reporterUserId: string, matchId: string, imageUrls?: string[]) {
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

    // 7. 증거 사진 포함 Report 레코드 생성
    if (imageUrls && imageUrls.length > 0) {
      const reportRepo = this.dataSource.getRepository(Report);
      await reportRepo.save(
        reportRepo.create({
          reporterId: reporterUserId,
          targetType: 'USER' as any,
          targetId: noshowUserId,
          reason: 'NOSHOW',
          description: `매치 ${matchId} 노쇼 신고`,
          imageUrls,
        }),
      );
    }

    // 8. 알림 발송
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
