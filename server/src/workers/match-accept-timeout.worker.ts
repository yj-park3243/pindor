import { Worker, Queue, Job } from 'bullmq';
import { AppDataSource } from '../config/database.js';
import { redis, bullmqRedis } from '../config/redis.js';
import type { MatchAcceptTimeoutJobData } from '../shared/types/index.js';
import {
  Match,
  MatchRequest,
  MatchAcceptance,
  SportsProfile,
  ScoreHistory,
} from '../entities/index.js';
import { MatchRequestStatus, ScoreChangeType } from '../entities/index.js';
import { calculateAge } from '../shared/utils/age.js';

// ─────────────────────────────────────
// 매칭 수락 타임아웃 Worker
// ─────────────────────────────────────
//
// 역할:
//   1. accept-timeout: 30분 내 미응답 처리 (수락 시간 만료)
//   2. delayed-match: 점수 차이가 50~150 또는 150+ 인 경우 3분/5분 대기 후 매칭 성사

export const matchAcceptTimeoutQueue = new Queue<MatchAcceptTimeoutJobData>(
  'match-accept-timeout',
  { connection: bullmqRedis },
);

export const matchAcceptTimeoutWorker = new Worker<MatchAcceptTimeoutJobData>(
  'match-accept-timeout',
  async (job: Job<MatchAcceptTimeoutJobData>) => {
    const { matchId, requesterUserId, opponentUserId, requesterRequestId, opponentRequestId } =
      job.data;

    // ──────────────────────────────────
    // [accept-reminder] 수락 리마인더 알림 처리
    // ──────────────────────────────────
    if (job.name === 'accept-reminder') {
      const { reminderUserId, reminderLabel } = job.data as any;
      await handleAcceptReminder(matchId, reminderUserId, reminderLabel);
      return;
    }

    // ──────────────────────────────────
    // [delayed-match] 지연 매칭 처리
    // ──────────────────────────────────
    if (job.name === 'delayed-match') {
      await handleDelayedMatch(
        requesterRequestId,
        requesterUserId,
        opponentUserId,
        opponentRequestId,
      );
      return;
    }

    // ──────────────────────────────────
    // [accept-timeout] 30분 수락 타임아웃 처리
    // ──────────────────────────────────
    if (job.name === 'accept-timeout') {
      await handleAcceptTimeout(
        matchId,
        requesterUserId,
        opponentUserId,
        requesterRequestId,
        opponentRequestId,
      );
      return;
    }
  },
  { connection: bullmqRedis, concurrency: 5 },
);

// ─────────────────────────────────────
// 수락 리마인더 처리 (accept-reminder)
// ─────────────────────────────────────

async function handleAcceptReminder(
  matchId: string,
  userId: string,
  label: string,
): Promise<void> {
  if (!AppDataSource.isInitialized) {
    await AppDataSource.initialize();
  }

  const matchRepo = AppDataSource.getRepository(Match);

  // 매칭이 아직 PENDING_ACCEPT 상태인지 확인 — 이미 수락/취소된 경우 스킵
  const match = await matchRepo.findOne({ where: { id: matchId } });
  if (!match || (match.status as string) !== 'PENDING_ACCEPT') {
    console.info(
      `[AcceptReminder] Skipping reminder (${label}) — match not in PENDING_ACCEPT: ${matchId}`,
    );
    return;
  }

  await redis.publish(
    'system_notification',
    JSON.stringify({
      userId,
      type: 'MATCH_ACCEPT_REMINDER',
      title: '매칭 수락 알림',
      body: `매칭 수락 시간이 ${label} 남았습니다!`,
      data: { matchId, deepLink: `/matches/${matchId}/accept` },
    }),
  );

  console.info(`[AcceptReminder] Sent reminder (${label}) to user ${userId} for match ${matchId}`);
}

// ─────────────────────────────────────
// 지연 매칭 처리 (delayed-match)
// ─────────────────────────────────────

async function handleDelayedMatch(
  requesterRequestId: string,
  requesterUserId: string,
  opponentUserId: string,
  opponentRequestId: string,
): Promise<void> {
  const matchRequestRepo = AppDataSource.getRepository(MatchRequest);
  const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);
  const matchRepo = AppDataSource.getRepository(Match);
  const matchAcceptanceRepo = AppDataSource.getRepository(MatchAcceptance);

  // 양측 매칭 요청이 아직 WAITING인지 확인
  const [requesterReq, opponentReq] = await Promise.all([
    matchRequestRepo.findOne({ where: { id: requesterRequestId } }),
    matchRequestRepo.findOne({ where: { id: opponentRequestId } }),
  ]);

  if (!requesterReq || requesterReq.status !== MatchRequestStatus.WAITING) {
    console.info(
      `[DelayedMatch] Requester request no longer WAITING: ${requesterRequestId}`,
    );
    return;
  }

  if (!opponentReq || opponentReq.status !== MatchRequestStatus.WAITING) {
    console.info(
      `[DelayedMatch] Opponent request no longer WAITING: ${opponentRequestId}`,
    );
    return;
  }

  // 상대 스포츠 프로필 정보 조회
  const opponentProfile = await sportsProfileRepo.findOne({
    where: {
      userId: opponentUserId,
      sportType: requesterReq.sportType,
      isActive: true,
    },
    relations: { user: true },
  });

  if (!opponentProfile) {
    console.info(`[DelayedMatch] Opponent profile not found: ${opponentUserId}`);
    return;
  }

  const requesterProfile = await sportsProfileRepo.findOne({
    where: {
      userId: requesterUserId,
      sportType: requesterReq.sportType,
      isActive: true,
    },
    relations: { user: true },
  });

  if (!requesterProfile) {
    console.info(`[DelayedMatch] Requester profile not found: ${requesterUserId}`);
    return;
  }

  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  await AppDataSource.transaction(async (manager) => {
    // 매칭 생성 (PENDING_ACCEPT)
    const match = manager.create(Match, {
      matchRequestId: requesterRequestId,
      requesterProfileId: requesterProfile.id,
      opponentProfileId: opponentProfile.id,
      sportType: requesterReq.sportType as any,
      status: 'PENDING_ACCEPT' as any,
    });
    const savedMatch = await manager.save(Match, match);

    // MatchAcceptance 레코드 2개 생성
    await manager.save(MatchAcceptance, [
      manager.create(MatchAcceptance, {
        matchId: savedMatch.id,
        userId: requesterUserId,
        accepted: null,
        expiresAt,
      }),
      manager.create(MatchAcceptance, {
        matchId: savedMatch.id,
        userId: opponentUserId,
        accepted: null,
        expiresAt,
      }),
    ]);

    // 양측 매칭 요청 상태를 MATCHED로
    await manager
      .createQueryBuilder()
      .update(MatchRequest)
      .set({ status: MatchRequestStatus.MATCHED })
      .where('id IN (:...ids)', { ids: [requesterRequestId, opponentRequestId] })
      .execute();

    // 10분 타임아웃 job 등록
    await matchAcceptTimeoutQueue.add(
      'accept-timeout',
      {
        matchId: savedMatch.id,
        requesterUserId,
        opponentUserId,
        requesterRequestId,
        opponentRequestId,
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
      for (const userId of [requesterUserId, opponentUserId]) {
        await matchAcceptTimeoutQueue.add(
          'accept-reminder',
          {
            matchId: savedMatch.id,
            requesterUserId,
            opponentUserId,
            requesterRequestId,
            opponentRequestId,
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

    // 알림 발송
    const requesterAge = (requesterProfile.user as any)?.birthDate
      ? calculateAge(new Date((requesterProfile.user as any).birthDate))
      : null;
    const opponentAge = (opponentProfile.user as any)?.birthDate
      ? calculateAge(new Date((opponentProfile.user as any).birthDate))
      : null;

    await redis.publish(
      'system_notification',
      JSON.stringify({
        userId: requesterUserId,
        type: 'MATCH_PENDING_ACCEPT',
        title: '매칭 상대를 찾았습니다!',
        body: `상대: ${(opponentProfile.user as any).nickname}${(opponentProfile.user as any).gender ? `/${(opponentProfile.user as any).gender}` : ''}${opponentAge !== null ? `/${opponentAge}세` : ''}. 수락하시겠습니까?`,
        data: {
          matchId: savedMatch.id,
          opponentNickname: (opponentProfile.user as any).nickname,
          opponentGender: (opponentProfile.user as any).gender ?? '',
          opponentAge: opponentAge !== null ? String(opponentAge) : '',
          deepLink: `/matches/${savedMatch.id}/accept`,
        },
      }),
    );

    await redis.publish(
      'system_notification',
      JSON.stringify({
        userId: opponentUserId,
        type: 'MATCH_PENDING_ACCEPT',
        title: '매칭 상대를 찾았습니다!',
        body: `상대: ${(requesterProfile.user as any).nickname}${(requesterProfile.user as any).gender ? `/${(requesterProfile.user as any).gender}` : ''}${requesterAge !== null ? `/${requesterAge}세` : ''}. 수락하시겠습니까?`,
        data: {
          matchId: savedMatch.id,
          opponentNickname: (requesterProfile.user as any).nickname,
          opponentGender: (requesterProfile.user as any).gender ?? '',
          opponentAge: requesterAge !== null ? String(requesterAge) : '',
          deepLink: `/matches/${savedMatch.id}/accept`,
        },
      }),
    );
  });

  console.info(
    `[DelayedMatch] Match created: requester=${requesterUserId}, opponent=${opponentUserId}`,
  );
}

// ─────────────────────────────────────
// 수락 타임아웃 처리 (accept-timeout)
// ─────────────────────────────────────

async function handleAcceptTimeout(
  matchId: string,
  requesterUserId: string,
  opponentUserId: string,
  requesterRequestId: string,
  opponentRequestId: string,
): Promise<void> {
  const matchRepo = AppDataSource.getRepository(Match);
  const matchRequestRepo = AppDataSource.getRepository(MatchRequest);
  const matchAcceptanceRepo = AppDataSource.getRepository(MatchAcceptance);

  // 매칭이 아직 PENDING_ACCEPT인지 확인
  const match = await matchRepo.findOne({
    where: { id: matchId },
  });

  if (!match || (match.status as string) !== 'PENDING_ACCEPT') {
    console.info(`[AcceptTimeout] Match is not in PENDING_ACCEPT state: ${matchId}`);
    return;
  }

  // acceptances 별도 조회 (Match 엔티티에 relation 없음)
  const acceptances = await matchAcceptanceRepo.find({
    where: { matchId },
  });

  // expiresAt이 지난 MatchAcceptance 중 accepted=null인 것 찾기
  const now = new Date();
  const expiredPendingAcceptances = acceptances.filter(
    (a: any) => a.accepted === null && a.expiresAt <= now,
  );

  if (expiredPendingAcceptances.length === 0) {
    console.info(`[AcceptTimeout] No expired pending acceptances for match: ${matchId}`);
    return;
  }

  // 미응답자가 있고, 수락한 사람이 있는 경우에만 패널티 적용
  // (양측 모두 미응답이면 패널티 없음)
  const acceptedAcceptances = acceptances.filter((a: any) => a.accepted === true);
  const hasPenalty = expiredPendingAcceptances.length > 0 && acceptedAcceptances.length > 0;

  await AppDataSource.transaction(async (manager) => {
    // 매칭을 CANCELLED 처리
    await manager.update(Match, matchId, { status: 'CANCELLED' as any });

    for (const acc of expiredPendingAcceptances) {
      // MatchAcceptance 레코드에 만료 기록
      await manager.update(MatchAcceptance, acc.id, { respondedAt: now });

      // 미응답 유저의 matchRequest를 WAITING으로 복구
      const pendingMatchRequest = await manager
        .createQueryBuilder(MatchRequest, 'mr')
        .leftJoin('mr.sportsProfile', 'sp')
        .where('sp.userId = :userId AND mr.status = :status', {
          userId: acc.userId,
          status: MatchRequestStatus.MATCHED,
        })
        .orderBy('mr.updatedAt', 'DESC')
        .getOne();

      if (pendingMatchRequest) {
        await manager.update(MatchRequest, pendingMatchRequest.id, {
          status: MatchRequestStatus.WAITING,
        });
      }

      // 미응답자 패널티: 수락한 상대방이 있는 경우에만 -15 displayScore 적용
      // glickoRating은 변경하지 않음 (순수 MMR 보존)
      if (hasPenalty) {
        const sportType = match.sportType as string;
        const noResponderProfile = await manager
          .createQueryBuilder(SportsProfile, 'sp')
          .where('sp.userId = :userId AND sp.sportType = :sportType AND sp.isActive = true', {
            userId: acc.userId,
            sportType,
          })
          .getOne();

        if (noResponderProfile) {
          const scoreBefore = noResponderProfile.displayScore ?? noResponderProfile.currentScore;
          const newScore = Math.max(100, scoreBefore - 15);

          await manager
            .createQueryBuilder()
            .update(SportsProfile)
            .set({
              displayScore: newScore,
              currentScore: newScore,
            })
            .where('id = :id', { id: noResponderProfile.id })
            .execute();

          await manager.save(ScoreHistory, manager.create(ScoreHistory, {
            sportsProfileId: noResponderProfile.id,
            gameId: null,
            changeType: ScoreChangeType.NO_SHOW_PENALTY,
            scoreBefore,
            scoreChange: -15,
            scoreAfter: newScore,
          }));
        }

        // 미응답 유저에게 패널티 알림
        await redis.publish(
          'system_notification',
          JSON.stringify({
            userId: acc.userId,
            type: 'MATCH_ACCEPT_TIMEOUT',
            title: '매칭 수락 시간 만료 (패널티)',
            body: '수락 시간이 만료되어 매칭이 취소되었습니다. -15점 패널티가 적용되었습니다.',
            data: { matchId, deepLink: '/matches/requests' },
          }),
        );
      } else {
        // 양측 모두 미응답: 패널티 없이 안내만
        await redis.publish(
          'system_notification',
          JSON.stringify({
            userId: acc.userId,
            type: 'MATCH_ACCEPT_TIMEOUT',
            title: '매칭 수락 시간 만료',
            body: '수락 시간이 만료되어 매칭이 취소되었습니다.',
            data: { matchId, deepLink: '/matches/requests' },
          }),
        );
      }
    }

    // 수락한 유저는 재매칭 가능 상태로 복구 + displayScore +5 보상
    for (const acc of acceptedAcceptances) {
      const acceptedMatchRequest = await manager
        .createQueryBuilder(MatchRequest, 'mr')
        .leftJoin('mr.sportsProfile', 'sp')
        .where('sp.userId = :userId AND mr.status = :status', {
          userId: acc.userId,
          status: MatchRequestStatus.MATCHED,
        })
        .orderBy('mr.updatedAt', 'DESC')
        .getOne();

      if (acceptedMatchRequest) {
        await manager.update(MatchRequest, acceptedMatchRequest.id, {
          status: MatchRequestStatus.WAITING,
        });
      }

      // 수락자 보상: displayScore +5 (glickoRating 불변)
      const sportType = match.sportType as string;
      const acceptorProfile = await manager
        .createQueryBuilder(SportsProfile, 'sp')
        .where('sp.userId = :userId AND sp.sportType = :sportType AND sp.isActive = true', {
          userId: acc.userId,
          sportType,
        })
        .getOne();

      if (acceptorProfile) {
        const acceptorScoreBefore = acceptorProfile.displayScore ?? acceptorProfile.currentScore;
        const acceptorNewScore = acceptorScoreBefore + 5;

        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({
            displayScore: acceptorNewScore,
            currentScore: acceptorNewScore,
          })
          .where('id = :id', { id: acceptorProfile.id })
          .execute();

        await manager.save(ScoreHistory, manager.create(ScoreHistory, {
          sportsProfileId: acceptorProfile.id,
          gameId: null,
          changeType: ScoreChangeType.NO_SHOW_PENALTY,
          scoreBefore: acceptorScoreBefore,
          scoreChange: 5,
          scoreAfter: acceptorNewScore,
        }));
      }

      // 수락한 유저에게 알림
      await redis.publish(
        'system_notification',
        JSON.stringify({
          userId: acc.userId,
          type: 'MATCH_ACCEPT_TIMEOUT',
          title: '매칭이 취소되었습니다',
          body: '상대방이 시간 내에 응답하지 않아 매칭이 취소되었습니다. 다시 매칭을 시도할 수 있습니다.',
          data: { matchId, deepLink: '/matches/requests' },
        }),
      );
    }
  });

  // 타임아웃 취소 → CANCELLED 상태 실시간 전달
  try {
    await redis.publish('match_lifecycle', JSON.stringify({
      event: 'MATCH_STATUS_CHANGED',
      matchId,
      data: { matchId, status: 'CANCELLED', reason: 'ACCEPT_TIMEOUT' },
    }));
  } catch (pubErr) {
    console.warn('[AcceptTimeout] match_lifecycle publish failed:', pubErr);
  }

  console.info(`[AcceptTimeout] Match cancelled due to timeout: ${matchId}`);
}

matchAcceptTimeoutWorker.on('completed', (job) => {
  console.info(`[MatchAcceptTimeoutWorker] Job ${job.id} (${job.name}) completed`);
});

matchAcceptTimeoutWorker.on('failed', (job, err) => {
  console.error(
    `[MatchAcceptTimeoutWorker] Job ${job?.id} (${job?.name}) failed:`,
    err.message,
  );
});
