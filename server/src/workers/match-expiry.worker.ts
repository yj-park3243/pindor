import { Worker, Queue, Job } from 'bullmq';
import { AppDataSource } from '../config/database.js';
import { redis, bullmqRedis } from '../config/redis.js';
import type { MatchExpiryJobData } from '../shared/types/index.js';
import { MatchRequest } from '../entities/index.js';
import { MatchRequestStatus } from '../entities/index.js';

// ─────────────────────────────────────
// 매칭 요청 만료 처리 Worker
// ─────────────────────────────────────

export const matchExpiryQueue = new Queue<MatchExpiryJobData>('match-expiry', {
  connection: bullmqRedis,
});

export const matchExpiryWorker = new Worker<MatchExpiryJobData>(
  'match-expiry',
  async (job: Job<MatchExpiryJobData>) => {
    const { matchRequestId } = job.data;
    const matchRequestRepo = AppDataSource.getRepository(MatchRequest);

    const request = await matchRequestRepo.findOne({ where: { id: matchRequestId } });

    if (!request) {
      console.info(`[MatchExpiryWorker] Request not found: ${matchRequestId}`);
      return;
    }

    if (request.status !== MatchRequestStatus.WAITING) {
      console.info(
        `[MatchExpiryWorker] Request already processed (${request.status}): ${matchRequestId}`,
      );
      return;
    }

    // WAITING 상태이고 만료 시간이 지났으면 EXPIRED로 변경
    if (new Date() >= request.expiresAt) {
      await matchRequestRepo.update(matchRequestId, { status: MatchRequestStatus.EXPIRED });

      console.info(`[MatchExpiryWorker] Expired: ${matchRequestId}`);

      // 알림 발송 (Redis pub/sub)
      await redis.publish(
        'system_notification',
        JSON.stringify({
          userId: request.requesterId,
          type: 'MATCH_EXPIRED',
          title: '매칭 요청 만료',
          body: '매칭 상대를 찾지 못했습니다. 다시 시도해 보세요.',
          data: { deepLink: '/matches/requests' },
        }),
      );
    }
  },
  { connection: bullmqRedis, concurrency: 5 },
);

// ─────────────────────────────────────
// 만료된 매칭 요청 배치 처리 (주기적 실행)
// ─────────────────────────────────────

export async function processExpiredMatchRequests(): Promise<void> {
  const matchRequestRepo = AppDataSource.getRepository(MatchRequest);

  const expiredRequests = await matchRequestRepo.find({
    where: {
      status: MatchRequestStatus.WAITING,
    },
    take: 100,
  });

  // 만료 시간이 지난 것만 필터링
  const now = new Date();
  const actuallyExpired = expiredRequests.filter((req) => req.expiresAt <= now);

  if (actuallyExpired.length === 0) return;

  console.info(`[MatchExpiryBatch] Processing ${actuallyExpired.length} expired requests`);

  const jobs = actuallyExpired.map((req) => ({
    name: 'expire-match',
    data: { matchRequestId: req.id },
  }));

  await matchExpiryQueue.addBulk(jobs);
}

matchExpiryWorker.on('completed', (job) => {
  console.info(`[MatchExpiryWorker] Job ${job.id} completed`);
});

matchExpiryWorker.on('failed', (job, err) => {
  console.error(`[MatchExpiryWorker] Job ${job?.id} failed:`, err.message);
});
