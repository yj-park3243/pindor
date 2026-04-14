import { AppDataSource } from '../config/database.js';
import { Game, Match } from '../entities/index.js';
import { GamesService } from '../modules/games/games.service.js';
import type { INotificationService } from '../shared/types/index.js';

// ─────────────────────────────────────
// 경기 결과 자동 확정 배치 Worker
//
// 규칙:
//   a) 양측 모두 3일 이내 결과 미입력 → 무승부(DRAW) 처리
//   b) 한쪽만 결과 입력 후 3분이 지나도 상대가 미입력 → 제출된 결과 채택
// (BullMQ delayed job이 메인, 이 폴링은 백업)
// ─────────────────────────────────────

export async function processAutoResolveGames(): Promise<void> {
  const gameRepo = AppDataSource.getRepository(Game);
  const matchRepo = AppDataSource.getRepository(Match);
  const notificationService = (global as any).__notificationService as INotificationService | undefined;
  const gamesService = new GamesService(AppDataSource, notificationService);

  const now = new Date();

  // ─── a) 양측 모두 미입력 + 3일 경과 → 무승부 ───
  // CONFIRMED 매칭에 연결된 게임 중 resultStatus = PENDING이고
  // requester_claimed_result IS NULL AND opponent_claimed_result IS NULL이며
  // 게임 생성 후 3일이 지난 경우
  const threeDaysAgo = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000);

  const drawCandidates = await gameRepo
    .createQueryBuilder('game')
    .innerJoin('game.match', 'match')
    .where('game.resultStatus = :status', { status: 'PENDING' })
    .andWhere('game.requesterClaimedResult IS NULL')
    .andWhere('game.opponentClaimedResult IS NULL')
    .andWhere('match.status = :matchStatus', { matchStatus: 'CONFIRMED' })
    .andWhere('game.createdAt <= :threshold', { threshold: threeDaysAgo })
    .take(50)
    .getMany();

  if (drawCandidates.length > 0) {
    console.info(`[AutoResolveWorker] Processing ${drawCandidates.length} games as DRAW (3-day timeout)`);
    for (const game of drawCandidates) {
      try {
        await gamesService.resolveGameAsDraw(game.id);
      } catch (err) {
        console.error(`[AutoResolveWorker] Failed to resolve game ${game.id} as DRAW:`, (err as Error).message);
      }
    }
  }

  // ─── b) 한쪽만 입력 + 3분 경과 → 제출된 결과 채택 ───
  // resultStatus = PROOF_UPLOADED이고
  // requester_claimed_result OR opponent_claimed_result 중 하나만 있으며
  // 마지막 업데이트(updatedAt) 후 3분이 지난 경우
  // (BullMQ delayed job이 메인이지만, 이 폴링은 백업으로 동작)
  const threeMinutesAgo = new Date(now.getTime() - 3 * 60 * 1000);

  const singleSideCandidates = await gameRepo
    .createQueryBuilder('game')
    .innerJoin('game.match', 'match')
    .where('game.resultStatus = :status', { status: 'PROOF_UPLOADED' })
    .andWhere(
      '(game.requesterClaimedResult IS NOT NULL AND game.opponentClaimedResult IS NULL) OR ' +
      '(game.requesterClaimedResult IS NULL AND game.opponentClaimedResult IS NOT NULL)',
    )
    .andWhere('match.status = :matchStatus', { matchStatus: 'CONFIRMED' })
    .andWhere('game.updatedAt <= :threshold', { threshold: threeMinutesAgo })
    .take(50)
    .getMany();

  if (singleSideCandidates.length > 0) {
    console.info(`[AutoResolveWorker] Processing ${singleSideCandidates.length} games with single-side result (3-min timeout)`);
    for (const game of singleSideCandidates) {
      try {
        await gamesService.resolveGameWithSingleResult(game.id);
      } catch (err) {
        console.error(`[AutoResolveWorker] Failed to resolve game ${game.id} with single result:`, (err as Error).message);
      }
    }
  }

  if (drawCandidates.length === 0 && singleSideCandidates.length === 0) {
    return;
  }

  console.info(
    `[AutoResolveWorker] Done. DRAW: ${drawCandidates.length}, SingleResult: ${singleSideCandidates.length}`,
  );
}
