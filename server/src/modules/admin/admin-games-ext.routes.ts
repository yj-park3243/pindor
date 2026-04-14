import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Game, Match, GameResultStatus, SportsProfile, ScoreHistory } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { ScoreChangeType } from '../../entities/enums.js';
import type { INotificationService } from '../../shared/types/index.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminGamesExtRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/games/disputes ───
  // NOTE: 반드시 /admin/games/:id 보다 먼저 등록해야 "disputes"가 :id로 해석되지 않음
  fastify.get(
    '/admin/games/disputes',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '이의 신청(DISPUTED) 경기 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{ Querystring: { page?: number; pageSize?: number } }>,
      reply: FastifyReply,
    ) => {
      const { page, pageSize, skip } = parsePageParams(request.query);

      const gameRepo = AppDataSource.getRepository(Game);
      const qb = gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('game.resultStatus = :status', { status: GameResultStatus.DISPUTED });

      const [items, total] = await qb
        .orderBy('game.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/games ───
  fastify.get(
    '/admin/games',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '경기 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          sportType?: string;
          resultStatus?: string;
          search?: string;
          page?: number;
          pageSize?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { sportType, resultStatus, search } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const gameRepo = AppDataSource.getRepository(Game);
      const qb = gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser');

      if (sportType) {
        qb.andWhere('game.sportType = :sportType', { sportType });
      }
      if (resultStatus) {
        qb.andWhere('game.resultStatus = :resultStatus', { resultStatus });
      }
      if (search) {
        qb.andWhere(
          '(requesterUser.nickname ILIKE :search OR opponentUser.nickname ILIKE :search)',
          { search: `%${search}%` },
        );
      }

      const [items, total] = await qb
        .orderBy('game.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/games/:id ───
  fastify.get(
    '/admin/games/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '경기 상세 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const gameRepo = AppDataSource.getRepository(Game);
      const game = await gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('game.id = :id', { id: request.params.id })
        .getOne();

      if (!game) {
        throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);
      }

      return reply.send({ success: true, data: game });
    },
  );

  // ─── PATCH /admin/games/:gameId/void ───
  fastify.patch(
    '/admin/games/:gameId/void',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '경기 무효 처리',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { gameId: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['reason'],
          properties: { reason: { type: 'string', minLength: 1 } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { gameId: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const { gameId } = request.params;
      const { reason } = request.body;

      const gameRepo = AppDataSource.getRepository(Game);
      const game = await gameRepo.findOne({
        where: { id: gameId },
        relations: ['match'],
      });

      if (!game) {
        throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);
      }

      await AppDataSource.transaction(async (manager) => {
        await manager.getRepository(Game).update(gameId, {
          resultStatus: GameResultStatus.VOIDED,
        });
        await manager.getRepository(Match).update(game.matchId, {
          status: 'CANCELLED' as any,
          cancelReason: reason,
        });
      });

      // 업데이트된 game 반환
      const updatedGame = await gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('game.id = :id', { id: gameId })
        .getOne();

      return reply.send({ success: true, data: updatedGame });
    },
  );

  // ─── PATCH /admin/games/:gameId/resolve ───
  // 어드민이 DISPUTED 경기의 결과를 확정하고 점수를 반영
  fastify.patch(
    '/admin/games/:gameId/resolve',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '이의 제기 경기 결과 확정 (점수 반영)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { gameId: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['result', 'reason'],
          properties: {
            result: { type: 'string', enum: ['REQUESTER_WIN', 'OPPONENT_WIN', 'DRAW', 'VOID'] },
            reason: { type: 'string', minLength: 1 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { gameId: string };
        Body: { result: 'REQUESTER_WIN' | 'OPPONENT_WIN' | 'DRAW' | 'VOID'; reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { gameId } = request.params;
      const { result, reason } = request.body;

      const gameRepo = AppDataSource.getRepository(Game);
      const game = await gameRepo.findOne({
        where: { id: gameId },
        relations: {
          match: {
            requesterProfile: { user: true } as any,
            opponentProfile: { user: true } as any,
          },
        } as any,
      });

      if (!game) {
        throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);
      }

      if (game.resultStatus !== 'DISPUTED') {
        throw AppError.badRequest(
          ErrorCode.GAME_ALREADY_CONFIRMED,
          'DISPUTED 상태의 경기만 결과를 확정할 수 있습니다.',
        );
      }

      const match = game.match as any;
      const requesterProfile = match.requesterProfile;
      const opponentProfile = match.opponentProfile;

      if (result === 'VOID') {
        // 무효 처리 — 점수 변동 없음
        await AppDataSource.transaction(async (manager) => {
          await manager.getRepository(Game).update(gameId, {
            resultStatus: GameResultStatus.VOIDED,
          });
          await manager.getRepository(Match).update(game.matchId, {
            status: 'CANCELLED' as any,
            cancelReason: `[어드민] ${reason}`,
          });
        });
      } else {
        // 결과 확정 — 승자 결정 + 점수 반영
        let winnerProfileId: string | null = null;
        if (result === 'REQUESTER_WIN') {
          winnerProfileId = requesterProfile.id;
        } else if (result === 'OPPONENT_WIN') {
          winnerProfileId = opponentProfile.id;
        }
        // DRAW → winnerProfileId = null

        const reqScore = requesterProfile.currentScore ?? 1000;
        const oppScore = opponentProfile.currentScore ?? 1000;

        // 간단한 ELO 계산 (K=40)
        const K = 40;
        const expectedReq = 1 / (1 + Math.pow(10, (oppScore - reqScore) / 400));
        const expectedOpp = 1 - expectedReq;

        let actualReq: number;
        if (result === 'REQUESTER_WIN') actualReq = 1;
        else if (result === 'OPPONENT_WIN') actualReq = 0;
        else actualReq = 0.5; // DRAW

        const reqChange = Math.round(K * (actualReq - expectedReq));
        const oppChange = Math.round(K * ((1 - actualReq) - expectedOpp));

        const reqNewScore = Math.max(100, reqScore + reqChange);
        const oppNewScore = Math.max(100, oppScore + oppChange);

        const reqChangeType = result === 'DRAW' ? ScoreChangeType.GAME_DRAW
          : result === 'REQUESTER_WIN' ? ScoreChangeType.GAME_WIN
          : ScoreChangeType.GAME_LOSS;
        const oppChangeType = result === 'DRAW' ? ScoreChangeType.GAME_DRAW
          : result === 'OPPONENT_WIN' ? ScoreChangeType.GAME_WIN
          : ScoreChangeType.GAME_LOSS;

        await AppDataSource.transaction(async (manager) => {
          // 게임 결과 업데이트
          await manager.getRepository(Game).update(gameId, {
            resultStatus: GameResultStatus.VERIFIED,
            winnerProfileId: winnerProfileId as any,
            verifiedAt: new Date(),
          });

          // 매칭 상태 업데이트
          await manager.getRepository(Match).update(game.matchId, {
            status: 'COMPLETED' as any,
            completedAt: new Date(),
          });

          // 점수 반영
          await manager.getRepository(SportsProfile).update(requesterProfile.id, {
            currentScore: reqNewScore,
            displayScore: reqNewScore,
            gamesPlayed: () => 'games_played + 1',
            ...(result === 'REQUESTER_WIN' ? { wins: () => 'wins + 1' } : {}),
            ...(result === 'OPPONENT_WIN' ? { losses: () => 'losses + 1' } : {}),
          } as any);

          await manager.getRepository(SportsProfile).update(opponentProfile.id, {
            currentScore: oppNewScore,
            displayScore: oppNewScore,
            gamesPlayed: () => 'games_played + 1',
            ...(result === 'OPPONENT_WIN' ? { wins: () => 'wins + 1' } : {}),
            ...(result === 'REQUESTER_WIN' ? { losses: () => 'losses + 1' } : {}),
          } as any);

          // 점수 이력 기록
          await manager.getRepository(ScoreHistory).save([
            manager.getRepository(ScoreHistory).create({
              sportsProfileId: requesterProfile.id,
              gameId,
              changeType: reqChangeType,
              scoreBefore: reqScore,
              scoreChange: reqChange,
              scoreAfter: reqNewScore,
            }),
            manager.getRepository(ScoreHistory).create({
              sportsProfileId: opponentProfile.id,
              gameId,
              changeType: oppChangeType,
              scoreBefore: oppScore,
              scoreChange: oppChange,
              scoreAfter: oppNewScore,
            }),
          ]);
        });

        // 양측 유저에게 알림
        const notificationService = (global as any).__notificationService as INotificationService | undefined;
        if (notificationService) {
          const resultMsg = result === 'REQUESTER_WIN'
            ? `운영자 검토 결과: ${requesterProfile.user?.nickname ?? ''}님 승리로 확정`
            : result === 'OPPONENT_WIN'
            ? `운영자 검토 결과: ${opponentProfile.user?.nickname ?? ''}님 승리로 확정`
            : '운영자 검토 결과: 무승부로 확정';

          await notificationService.sendBulk([
            {
              userId: requesterProfile.userId,
              type: 'GAME_RESULT_CONFIRMED',
              title: '이의 제기 결과',
              body: `${resultMsg}. 사유: ${reason}`,
              data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
            },
            {
              userId: opponentProfile.userId,
              type: 'GAME_RESULT_CONFIRMED',
              title: '이의 제기 결과',
              body: `${resultMsg}. 사유: ${reason}`,
              data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
            },
          ]);
        }
      }

      // 업데이트된 게임 반환
      const updatedGame = await gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('game.id = :id', { id: gameId })
        .getOne();

      return reply.send({ success: true, data: updatedGame, meta: { resolvedResult: result, reason } });
    },
  );
}
