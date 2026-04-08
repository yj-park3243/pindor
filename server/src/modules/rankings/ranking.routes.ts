import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { SportType } from '../../entities/index.js';
import { RankingService } from './ranking.service.js';
import { redis } from '../../config/redis.js';

const sportTypeQuery = z.object({
  sportType: z.nativeEnum(SportType).default(SportType.GOLF),
  limit: z.coerce.number().min(1).max(100).default(50),
  cursor: z.string().optional(),
});

export async function rankingRoutes(fastify: FastifyInstance): Promise<void> {
  const rankingService = new RankingService(redis);

  // ─── GET /rankings/pins/:pinId ───
  fastify.get(
    '/rankings/pins/:pinId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Rankings'],
        summary: '핀 랭킹 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { pinId: { type: 'string', format: 'uuid' } },
        },
        querystring: {
          type: 'object',
          properties: {
            sportType: { type: 'string', enum: Object.values(SportType) },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 50 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { pinId: string };
        Querystring: { sportType?: SportType; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const query = sportTypeQuery.parse(request.query);
      const data = await rankingService.getPinRanking(
        request.params.pinId,
        query.sportType,
        query.limit,
        request.user.userId,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /rankings/national ───
  fastify.get(
    '/rankings/national',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Rankings'],
        summary: '전국 랭킹',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{
        Querystring: { sportType?: SportType; cursor?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const query = sportTypeQuery.parse(request.query);
      const { rankings, nextCursor, hasMore } = await rankingService.getNationalRanking(
        query.sportType,
        query.cursor,
        query.limit,
      );
      return reply.send({
        success: true,
        data: rankings,
        meta: { cursor: nextCursor, hasMore },
      });
    },
  );

  // ─── GET /rankings/me ───
  fastify.get(
    '/rankings/me',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Rankings'],
        summary: '내 랭킹 조회',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Querystring: { sportType?: SportType } }>,
      reply: FastifyReply,
    ) => {
      const sportType = (request.query.sportType as SportType) ?? SportType.GOLF;
      const data = await rankingService.getMyRanking(request.user.userId, sportType);
      return reply.send({ success: true, data });
    },
  );
}
