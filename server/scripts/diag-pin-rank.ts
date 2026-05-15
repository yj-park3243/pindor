import 'dotenv/config';
import { AppDataSource } from '../src/config/database.js';
import { redis } from '../src/config/redis.js';
import { RankingService } from '../src/modules/rankings/ranking.service.js';
import { SportType, SportsProfile, RankingEntry } from '../src/entities/index.js';

const PIN_ID = 'b95b3652-8b03-4615-9a29-6071a0e8b1f1'; // 사당역
const USER_ID = '80b54969-1055-4223-a993-329db299cb70'; // 빛나는치타
const SPORT = SportType.GOLF;

async function main() {
  await AppDataSource.initialize();
  const svc = new RankingService(redis);

  console.log('--- getPinRanking 결과 ---');
  const result = await svc.getPinRanking(PIN_ID, SPORT, 50, USER_ID);
  console.log(JSON.stringify(result, null, 2));

  console.log('\n--- DB ranking_entries (사당역, GOLF) ---');
  const entries = await AppDataSource.getRepository(RankingEntry).find({
    where: { pinId: PIN_ID, sportType: SPORT },
    order: { rank: 'ASC' },
  });
  console.log(entries.map((e) => ({ rank: e.rank, score: e.score, profileId: e.sportsProfileId, tier: e.tier })));

  console.log('\n--- 빛나는치타 sports_profiles ---');
  const profiles = await AppDataSource.getRepository(SportsProfile).find({
    where: { userId: USER_ID },
  });
  console.log(profiles.map((p) => ({ id: p.id, sport: p.sportType, active: p.isActive, score: p.currentScore, games: p.gamesPlayed })));

  console.log('\n--- isActive=true 필터로 GOLF 프로필 찾기 ---');
  const goldenProfile = await AppDataSource.getRepository(SportsProfile).findOne({
    where: { userId: USER_ID, sportType: SPORT, isActive: true },
  });
  console.log(goldenProfile ? { id: goldenProfile.id, sport: goldenProfile.sportType } : 'NOT FOUND');

  console.log('\n--- Redis ZSET ---');
  const zsetKey = `ranking:${PIN_ID}:${SPORT}`;
  const members = await redis.zrevrange(zsetKey, 0, -1, 'WITHSCORES');
  console.log({ key: zsetKey, members });

  await redis.quit();
  await AppDataSource.destroy();
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
