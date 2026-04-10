import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { GamesService } from './games.service.js';
import {
  submitGameResultSchema,
  confirmGameResultSchema,
  disputeGameResultSchema,
  listGamesQuerySchema,
  type SubmitGameResultDto,
  type ConfirmGameResultDto,
  type DisputeGameResultDto,
  type ListGamesQuery,
} from './games.schema.js';
import { AppDataSource } from '../../config/database.js';

export async function gamesRoutes(fastify: FastifyInstance): Promise<void> {
  const gamesService = new GamesService(AppDataSource);

  // ─── POST /games/:gameId/result ───
  fastify.post(
    '/games/:gameId/result',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Games'],
        summary: '경기 결과 입력',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { gameId: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { gameId: string }; Body: SubmitGameResultDto }>,
      reply: FastifyReply,
    ) => {
      const dto = submitGameResultSchema.parse(request.body);
      const data = await gamesService.submitResult(
        request.user.userId,
        request.params.gameId,
        dto,
      );
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── POST /games/:gameId/confirm ───
  fastify.post(
    '/games/:gameId/confirm',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Games'],
        summary: '결과 인증 동의/거절',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { gameId: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { gameId: string };
        Body: ConfirmGameResultDto;
      }>,
      reply: FastifyReply,
    ) => {
      const dto = confirmGameResultSchema.parse(request.body);
      const data = await gamesService.confirmResult(
        request.user.userId,
        request.params.gameId,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /games/:gameId/dispute ───
  fastify.post(
    '/games/:gameId/dispute',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Games'],
        summary: '결과 이의 신청',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { gameId: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { gameId: string };
        Body: DisputeGameResultDto;
      }>,
      reply: FastifyReply,
    ) => {
      const dto = disputeGameResultSchema.parse(request.body);
      const data = await gamesService.disputeResult(
        request.user.userId,
        request.params.gameId,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /games/:gameId/proofs ───
  fastify.post(
    '/games/:gameId/proofs',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Games'],
        summary: '증빙 사진 업로드',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { gameId: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { gameId: string };
        Body: { imageUrls: string[] };
      }>,
      reply: FastifyReply,
    ) => {
      const { imageUrls } = request.body as { imageUrls: string[] };
      if (!imageUrls || !Array.isArray(imageUrls) || imageUrls.length === 0) {
        return reply.status(400).send({ success: false, error: { code: 'COMMON_001', message: 'imageUrls가 필요합니다.' } });
      }
      await gamesService.addProofImages(request.user.userId, request.params.gameId, imageUrls);
      return reply.send({ success: true });
    },
  );

  // ─── GET /games/:id ───
  fastify.get(
    '/games/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Games'],
        summary: '경기 상세 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await gamesService.getGame(request.user.userId, request.params.id);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /games ───
  fastify.get(
    '/games',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Games'],
        summary: '내 경기 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Querystring: ListGamesQuery }>,
      reply: FastifyReply,
    ) => {
      const query = listGamesQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await gamesService.listMyGames(
        request.user.userId,
        query,
      );
      return reply.send({
        success: true,
        data: items,
        meta: { cursor: nextCursor, hasMore },
      });
    },
  );
}
