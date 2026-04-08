import { Worker, Queue, Job } from 'bullmq';
import { AppDataSource } from '../config/database.js';
import { redis, bullmqRedis } from '../config/redis.js';
import type { ResultDeadlineJobData } from '../shared/types/index.js';
import { Game, Match } from '../entities/index.js';

// ─────────────────────────────────────
// 결과 입력 기한 처리 Worker
// PRD FR-004-5: 경기 후 72시간 내 미입력 시 경고
// ─────────────────────────────────────

export const resultDeadlineQueue = new Queue<ResultDeadlineJobData>('result-deadline', {
  connection: bullmqRedis,
});

export const resultDeadlineWorker = new Worker<ResultDeadlineJobData>(
  'result-deadline',
  async (job: Job<ResultDeadlineJobData>) => {
    const { gameId, matchId } = job.data;
    const gameRepo = AppDataSource.getRepository(Game);
    const matchRepo = AppDataSource.getRepository(Match);

    const game = await gameRepo.findOne({
      where: { id: gameId },
      relations: {
        match: {
          requesterProfile: true,
          opponentProfile: true,
        } as any,
      } as any,
    });

    if (!game) {
      console.info(`[ResultDeadlineWorker] Game not found: ${gameId}`);
      return;
    }

    // 이미 결과가 입력된 경우 스킵
    if (game.resultStatus !== 'PENDING') {
      console.info(
        `[ResultDeadlineWorker] Already processed (${game.resultStatus}): ${gameId}`,
      );
      return;
    }

    // 기한 체크 (3시간 전 알림 vs 기한 초과)
    if (!game.resultInputDeadline) return;

    const now = new Date();
    const deadline = game.resultInputDeadline;
    const hoursUntilDeadline = (deadline.getTime() - now.getTime()) / (1000 * 60 * 60);

    const match = game.match;
    const participantIds = [
      (match.requesterProfile as any).userId,
      (match.opponentProfile as any).userId,
    ];

    if (hoursUntilDeadline <= 3 && hoursUntilDeadline > 0) {
      // 기한 임박 알림 (3시간 전)
      console.info(`[ResultDeadlineWorker] Sending deadline warning: ${gameId}`);

      for (const userId of participantIds) {
        await redis.publish(
          'system_notification',
          JSON.stringify({
            userId,
            type: 'RESULT_DEADLINE',
            title: '경기 결과 입력 마감 임박',
            body: `경기 결과 입력 기한이 ${Math.round(hoursUntilDeadline)}시간 남았습니다.`,
            data: { gameId, deepLink: `/games/${gameId}` },
            saveToDb: false,
          }),
        );
      }
    } else if (hoursUntilDeadline <= 0) {
      // 기한 초과 — 미입력 패널티 처리
      console.warn(`[ResultDeadlineWorker] Deadline exceeded: ${gameId}`);

      // 게임 무효 처리
      await gameRepo.update(gameId, { resultStatus: 'VOIDED' as any });
      await matchRepo.update(matchId, { status: 'CANCELLED' as any });

      // 패널티 알림
      for (const userId of participantIds) {
        await redis.publish(
          'system_notification',
          JSON.stringify({
            userId,
            type: 'RESULT_DEADLINE',
            title: '경기 결과 미입력 경고',
            body: '결과 입력 기한이 지나 경기가 취소 처리되었습니다.',
            data: { gameId, deepLink: `/games/${gameId}` },
          }),
        );
      }
    }
  },
  { connection: bullmqRedis, concurrency: 5 },
);

// ─────────────────────────────────────
// 배치: 기한 임박 게임 알림 스케줄
// ─────────────────────────────────────

export async function scheduleDeadlineWarnings(): Promise<void> {
  const gameRepo = AppDataSource.getRepository(Game);

  const threeHoursFromNow = new Date(Date.now() + 3 * 60 * 60 * 1000);
  const fourHoursFromNow = new Date(Date.now() + 4 * 60 * 60 * 1000);

  // TypeORM Between operator 대신 QueryBuilder 사용 (날짜 범위 쿼리)
  const gamesNearDeadline = await gameRepo
    .createQueryBuilder('game')
    .where('game.resultStatus = :status', { status: 'PENDING' })
    .andWhere('game.resultInputDeadline >= :from AND game.resultInputDeadline <= :to', {
      from: threeHoursFromNow,
      to: fourHoursFromNow,
    })
    .take(50)
    .getMany();

  if (gamesNearDeadline.length === 0) return;

  console.info(`[DeadlineScheduler] Scheduling warnings for ${gamesNearDeadline.length} games`);

  for (const game of gamesNearDeadline) {
    if (!game.resultInputDeadline) continue;

    const delay = Math.max(0, game.resultInputDeadline.getTime() - Date.now() - 3 * 60 * 60 * 1000);

    await resultDeadlineQueue.add(
      'check-deadline',
      { gameId: game.id, matchId: game.matchId },
      { delay, attempts: 2 },
    );
  }
}

resultDeadlineWorker.on('completed', (job) => {
  console.info(`[ResultDeadlineWorker] Job ${job.id} completed`);
});

resultDeadlineWorker.on('failed', (job, err) => {
  console.error(`[ResultDeadlineWorker] Job ${job?.id} failed:`, err.message);
});
