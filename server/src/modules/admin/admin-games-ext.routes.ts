import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Game, Match, GameResultStatus } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

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
      request: FastifyRequest<{ Querystring: { cursor?: string; limit?: number } }>,
      reply: FastifyReply,
    ) => {
      const { cursor, limit: rawLimit } = request.query;
      const limit = rawLimit ? Number(rawLimit) : 20;

      const gameRepo = AppDataSource.getRepository(Game);
      const qb = gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('game.resultStatus = :status', { status: GameResultStatus.DISPUTED });

      if (cursor) {
        qb.andWhere('game.createdAt < :cursor', { cursor: new Date(cursor) });
      }

      const games = await qb
        .orderBy('game.createdAt', 'DESC')
        .take(limit + 1)
        .getMany();

      const hasMore = games.length > limit;
      const items = hasMore ? games.slice(0, limit) : games;
      const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
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
          cursor?: string;
          limit?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { sportType, resultStatus, search, cursor, limit: rawLimit } = request.query;
      const limit = rawLimit ? Number(rawLimit) : 20;

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
      if (cursor) {
        qb.andWhere('game.createdAt < :cursor', { cursor: new Date(cursor) });
      }

      const games = await qb
        .orderBy('game.createdAt', 'DESC')
        .take(limit + 1)
        .getMany();

      const hasMore = games.length > limit;
      const items = hasMore ? games.slice(0, limit) : games;
      const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
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
}
