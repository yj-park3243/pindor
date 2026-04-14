import { Worker, Job } from 'bullmq';
import { AppDataSource } from '../config/database.js';
import { bullmqRedis } from '../config/redis.js';
import { GamesService } from '../modules/games/games.service.js';
import type { INotificationService } from '../shared/types/index.js';
import type { GameAutoResolveJobData } from '../queues/game-auto-resolve.queue.js';

// ─────────────────────────────────────
// 경기 결과 자동 확정 Worker (BullMQ delayed job)
//
// 한쪽만 결과를 입력한 뒤 3분이 지나도 상대방이 미입력 →
// 제출된 결과를 자동 채택하고 매칭을 종료합니다.
// ─────────────────────────────────────

export const gameAutoResolveWorker = new Worker<GameAutoResolveJobData>(
  'game-auto-resolve',
  async (job: Job<GameAutoResolveJobData>) => {
    const { gameId } = job.data;

    const notificationService = (global as any).__notificationService as INotificationService | undefined;
    const gamesService = new GamesService(AppDataSource, notificationService);

    try {
      await gamesService.resolveGameWithSingleResult(gameId);
    } catch (err) {
      console.error(
        `[GameAutoResolveWorker] Failed to auto-resolve game ${gameId}:`,
        (err as Error).message,
      );
      throw err;
    }
  },
  { connection: bullmqRedis, concurrency: 5 },
);

gameAutoResolveWorker.on('completed', (job) => {
  console.info(`[GameAutoResolveWorker] Job ${job.id} completed (game: ${job.data.gameId})`);
});

gameAutoResolveWorker.on('failed', (job, err) => {
  console.error(
    `[GameAutoResolveWorker] Job ${job?.id} failed (game: ${job?.data.gameId}):`,
    err.message,
  );
});
