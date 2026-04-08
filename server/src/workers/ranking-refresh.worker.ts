import { Worker, Queue, Job } from 'bullmq';
import { AppDataSource } from '../config/database.js';
import {
  SportsProfile,
  RankingEntry,
  Pin,
} from '../entities/index.js';
import { redis, bullmqRedis } from '../config/redis.js';
import { RankingCache } from '../modules/rankings/ranking.cache.js';
import type { RankingRefreshJobData } from '../shared/types/index.js';

// ─────────────────────────────────────
// 랭킹 갱신 Worker
// PRD 섹션 5.4: 매시간 갱신
// ─────────────────────────────────────

export const rankingRefreshQueue = new Queue<RankingRefreshJobData>('ranking-refresh', {
  connection: bullmqRedis,
});

const rankingCache = new RankingCache(redis);

export const rankingRefreshWorker = new Worker<RankingRefreshJobData>(
  'ranking-refresh',
  async (job: Job<RankingRefreshJobData>) => {
    const { pinId, sportType } = job.data;

    if (pinId && sportType) {
      // 특정 핀/종목 랭킹 갱신
      await refreshPinRanking(pinId, sportType);
    } else {
      // 전체 랭킹 갱신
      await refreshAllRankings();
    }
  },
  { connection: bullmqRedis, concurrency: 2 },
);

// ─────────────────────────────────────
// 특정 핀 랭킹 갱신
// ─────────────────────────────────────

async function refreshPinRanking(pinId: string, sportType: string): Promise<void> {
  console.info(`[RankingRefresh] Refreshing pin ${pinId} / ${sportType}`);

  const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);
  const rankingEntryRepo = AppDataSource.getRepository(RankingEntry);
  const pinRepo = AppDataSource.getRepository(Pin);

  // DB에서 최신 랭킹 계산
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

  const profiles = await sportsProfileRepo
    .createQueryBuilder('sp')
    .innerJoin('sp.user', 'u')
    .innerJoin('u.userPins', 'up', 'up.pinId = :pinId', { pinId })
    .where('sp.sportType = :sportType', { sportType })
    .andWhere('sp.isActive = true')
    .andWhere('sp.gamesPlayed >= 3')
    .andWhere('u.status = :status', { status: 'ACTIVE' })
    .andWhere('u.lastLoginAt >= :since', { since: thirtyDaysAgo })
    .orderBy('sp.currentScore', 'DESC')
    .take(100)
    .getMany();

  // Redis 초기화 후 재빌드
  await rankingCache.clearPinRanking(pinId, sportType);

  for (const profile of profiles) {
    await rankingCache.updateScore(pinId, sportType, profile.id, profile.currentScore);
  }

  // DB ranking_entries 테이블 동기화
  const existingEntries = await rankingEntryRepo.find({
    where: { pinId, sportType: sportType as any },
  });

  // 랭킹에 없는 항목 삭제
  const profileIds = new Set(profiles.map((p) => p.id));
  const toDelete = existingEntries.filter((e) => !profileIds.has(e.sportsProfileId));

  if (toDelete.length > 0) {
    await rankingEntryRepo.delete(toDelete.map((e) => e.id));
  }

  const existingIds = new Set(existingEntries.map((e) => e.sportsProfileId));

  // 순위 upsert (save: insert on conflict update)
  for (let i = 0; i < profiles.length; i++) {
    const profile = profiles[i];
    const existing = existingEntries.find((e) => e.sportsProfileId === profile.id);

    if (existing) {
      // 업데이트
      await rankingEntryRepo.update(existing.id, {
        rank: i + 1,
        score: profile.currentScore,
        tier: profile.tier,
        gamesPlayed: profile.gamesPlayed,
      });
    } else {
      // 신규 삽입
      const entry = rankingEntryRepo.create({
        pinId,
        sportsProfileId: profile.id,
        sportType: sportType as any,
        rank: i + 1,
        score: profile.currentScore,
        tier: profile.tier,
        gamesPlayed: profile.gamesPlayed,
      });
      await rankingEntryRepo.save(entry);
    }
  }

  // 핀 userCount 업데이트
  await pinRepo.update(pinId, { userCount: profiles.length });

  console.info(`[RankingRefresh] Pin ${pinId} / ${sportType}: ${profiles.length} entries`);
}

// ─────────────────────────────────────
// 전체 핀 랭킹 갱신
// ─────────────────────────────────────

async function refreshAllRankings(): Promise<void> {
  console.info('[RankingRefresh] Starting full ranking refresh');

  const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);
  const pinRepo = AppDataSource.getRepository(Pin);

  const pins = await pinRepo.find({
    where: { isActive: true },
    select: ['id'],
  });

  const sportTypes = ['GOLF', 'BILLIARDS', 'TENNIS', 'TABLE_TENNIS'];

  // 전국 랭킹 갱신
  for (const sportType of sportTypes) {
    const topProfiles = await sportsProfileRepo
      .createQueryBuilder('sp')
      .innerJoin('sp.user', 'u')
      .where('sp.sportType = :sportType', { sportType })
      .andWhere('sp.isActive = true')
      .andWhere('sp.gamesPlayed >= 10')
      .andWhere('u.status = :status', { status: 'ACTIVE' })
      .orderBy('sp.currentScore', 'DESC')
      .take(500)
      .getMany();

    // Redis 전국 랭킹 업데이트
    for (const profile of topProfiles) {
      await rankingCache.updateNationalScore(sportType, profile.id, profile.currentScore);
    }
  }

  // 각 핀별 랭킹 갱신 (큐에 등록)
  const jobs = pins.flatMap((pin) =>
    sportTypes.map((sportType) => ({
      name: 'refresh-pin',
      data: { pinId: pin.id, sportType },
    })),
  );

  // 배치로 큐에 추가 (100개씩)
  for (let i = 0; i < jobs.length; i += 100) {
    await rankingRefreshQueue.addBulk(jobs.slice(i, i + 100));
  }

  console.info(`[RankingRefresh] Queued ${jobs.length} pin ranking refreshes`);
}

rankingRefreshWorker.on('completed', (job) => {
  console.info(`[RankingRefreshWorker] Job ${job.id} completed`);
});

rankingRefreshWorker.on('failed', (job, err) => {
  console.error(`[RankingRefreshWorker] Job ${job?.id} failed:`, err.message);
});
