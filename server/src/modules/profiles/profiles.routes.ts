import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { ProfilesService } from './profiles.service.js';
import {
  createSportsProfileSchema,
  updateSportsProfileSchema,
  type CreateSportsProfileDto,
  type UpdateSportsProfileDto,
} from './profiles.schema.js';
import { AppDataSource } from '../../config/database.js';

export async function profilesRoutes(fastify: FastifyInstance): Promise<void> {
  const profilesService = new ProfilesService(AppDataSource);

  // ─── POST /sports-profiles ───
  fastify.post(
    '/sports-profiles',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Sports Profiles'],
        summary: '스포츠 프로필 생성',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: CreateSportsProfileDto }>,
      reply: FastifyReply,
    ) => {
      const dto = createSportsProfileSchema.parse(request.body);
      const data = await profilesService.createProfile(request.user.userId, dto);
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── GET /sports-profiles ───
  fastify.get(
    '/sports-profiles',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Sports Profiles'],
        summary: '내 스포츠 프로필 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const data = await profilesService.getProfiles(request.user.userId);
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /sports-profiles/:id ───
  fastify.patch(
    '/sports-profiles/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Sports Profiles'],
        summary: '스포츠 프로필 수정',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: UpdateSportsProfileDto;
      }>,
      reply: FastifyReply,
    ) => {
      const dto = updateSportsProfileSchema.parse(request.body);
      const data = await profilesService.updateProfile(
        request.user.userId,
        request.params.id,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /sports-profiles/:id/score-history ───
  fastify.get(
    '/sports-profiles/:id/score-history',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Sports Profiles'],
        summary: '점수 히스토리 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
        },
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Querystring: { limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const data = await profilesService.getScoreHistory(
        request.user.userId,
        request.params.id,
        request.query.limit ?? 20,
      );
      return reply.send({ success: true, data });
    },
  );
}
