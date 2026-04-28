/**
 * MMR 범위 확장 테스트 스크립트
 *
 * 매칭 요청 큐에 있는 요청들의 createdAt을 강제로 과거로 당겨서
 * 시간 경과에 따른 MMR 범위 확장이 즉시 동작하는지 검증한다.
 *
 * 실행:
 *   npx tsx scripts/test-mmr-range-expansion.ts [--minutes=20] [--all]
 *
 * 옵션:
 *   --minutes=N    : createdAt을 N분 전으로 당김 (기본 20)
 *   --all          : WAITING/MATCHING 상태인 모든 요청 대상 (기본은 자기 요청만 추천)
 *   --requestId=ID : 특정 요청 1건만 처리
 *
 * 권장 워커 환경변수 (.env):
 *   MATCH_WAIT_WINDOW_MIN=5      # 최소 윈도우 5분으로 단축
 *   MATCH_WAIT_RATIO_BOOST=5     # waitRatio 5배 가속
 */
import 'reflect-metadata';
import 'dotenv/config';
import { AppDataSource } from '../src/config/database.js';
import { MatchRequest, MatchRequestStatus } from '../src/entities/index.js';
import { In } from 'typeorm';

async function main() {
  const args = process.argv.slice(2);
  const minutesArg = args.find((a) => a.startsWith('--minutes='));
  const requestIdArg = args.find((a) => a.startsWith('--requestId='));
  const all = args.includes('--all');

  const minutes = minutesArg ? parseInt(minutesArg.split('=')[1], 10) : 20;
  const requestId = requestIdArg ? requestIdArg.split('=')[1] : null;

  await AppDataSource.initialize();
  const repo = AppDataSource.getRepository(MatchRequest);

  const where: any = requestId
    ? { id: requestId }
    : { status: In([MatchRequestStatus.WAITING, MatchRequestStatus.MATCHING]) };

  const reqs = await repo.find({ where });
  if (reqs.length === 0) {
    console.log('대상 요청 없음');
    process.exit(0);
  }

  if (!all && !requestId && reqs.length > 5) {
    console.log(`대기 중 요청 ${reqs.length}건. 전체 적용하려면 --all 추가`);
    process.exit(0);
  }

  const newCreatedAt = new Date(Date.now() - minutes * 60 * 1000);
  await repo
    .createQueryBuilder()
    .update(MatchRequest)
    .set({ createdAt: newCreatedAt })
    .whereInIds(reqs.map((r) => r.id))
    .execute();

  console.log(
    `${reqs.length}건의 createdAt을 ${minutes}분 전(${newCreatedAt.toISOString()})으로 당김`,
  );
  console.log('다음 매칭 사이클(5초)에서 확장된 MMR 범위가 적용됨');
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
