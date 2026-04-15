import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { MatchingService } from './matching.service.js';
import {
  createMatchRequestSchema,
  instantMatchSchema,
  listMatchRequestsQuerySchema,
  listMatchesQuerySchema,
  confirmMatchSchema,
  cancelMatchSchema,
  type CreateMatchRequestDto,
  type InstantMatchDto,
  type ListMatchRequestsQuery,
  type ListMatchesQuery,
  type ConfirmMatchDto,
  type CancelMatchDto,
} from './matching.schema.js';
import { AppDataSource } from '../../config/database.js';
import { NotificationService } from '../notifications/notification.service.js';

export async function matchingRoutes(fastify: FastifyInstance): Promise<void> {
  const notificationService: NotificationService | undefined =
    (global as any).__notificationService;
  const matchingService = new MatchingService(AppDataSource, notificationService);

  // ─── POST /matches/requests ───
  fastify.post(
    '/matches/requests',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 요청 생성',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: CreateMatchRequestDto }>,
      reply: FastifyReply,
    ) => {
      const dto = createMatchRequestSchema.parse(request.body);
      const data = await matchingService.createMatchRequest(request.user.userId, dto);
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── POST /matches/instant ───
  fastify.post(
    '/matches/instant',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '즉시 매칭 (오늘 대결)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: InstantMatchDto }>,
      reply: FastifyReply,
    ) => {
      const dto = instantMatchSchema.parse(request.body);
      const data = await matchingService.createInstantMatch(request.user.userId, dto);
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── GET /matches/requests ───
  fastify.get(
    '/matches/requests',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '내 매칭 요청 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Querystring: ListMatchRequestsQuery }>,
      reply: FastifyReply,
    ) => {
      const query = listMatchRequestsQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await matchingService.listMatchRequests(
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

  // ─── DELETE /matches/requests/:id ───
  fastify.delete(
    '/matches/requests/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 요청 취소',
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
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      await matchingService.cancelMatchRequest(request.user.userId, request.params.id);
      return reply.send({ success: true, data: { message: '매칭 요청이 취소되었습니다.' } });
    },
  );

  // ─── GET /matches ───
  fastify.get(
    '/matches',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '내 매칭 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Querystring: ListMatchesQuery }>,
      reply: FastifyReply,
    ) => {
      const query = listMatchesQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await matchingService.listMatches(
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

  // ─── GET /matches/active ───
  fastify.get(
    '/matches/active',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '활성 매칭 조회 (앱 시작 시 리다이렉트용)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.getActiveMatch(request.user.userId);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /matches/:id ───
  fastify.get(
    '/matches/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 상세 조회',
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
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.getMatch(request.user.userId, request.params.id);
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /matches/:id/confirm ───
  fastify.patch(
    '/matches/:id/confirm',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '경기 확정',
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
      request: FastifyRequest<{ Params: { id: string }; Body: ConfirmMatchDto }>,
      reply: FastifyReply,
    ) => {
      const dto = confirmMatchSchema.parse(request.body ?? {});
      const data = await matchingService.confirmMatch(
        request.user.userId,
        request.params.id,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /matches/:id/cancel ───
  fastify.patch(
    '/matches/:id/cancel',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '경기 취소',
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
      request: FastifyRequest<{ Params: { id: string }; Body: CancelMatchDto }>,
      reply: FastifyReply,
    ) => {
      const dto = cancelMatchSchema.parse(request.body ?? {});
      const data = await matchingService.cancelMatch(
        request.user.userId,
        request.params.id,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /matches/:matchId/accept ───
  fastify.post(
    '/matches/:matchId/accept',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 수락',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            matchId: { type: 'string', format: 'uuid' },
          },
          required: ['matchId'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { matchId: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.acceptMatch(
        request.user.userId,
        request.params.matchId,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /matches/:matchId/reject ───
  fastify.post(
    '/matches/:matchId/reject',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 거절',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            matchId: { type: 'string', format: 'uuid' },
          },
          required: ['matchId'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { matchId: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.rejectMatch(
        request.user.userId,
        request.params.matchId,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /matches/:matchId/status ───
  fastify.get(
    '/matches/:matchId/status',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 수락 상태 조회 (양측 수락 여부)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            matchId: { type: 'string', format: 'uuid' },
          },
          required: ['matchId'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { matchId: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.getMatchAcceptStatus(
        request.user.userId,
        request.params.matchId,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /matches/:id/report-noshow ───
  fastify.post(
    '/matches/:id/report-noshow',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '노쇼 신고 (증거 사진 필수)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
          required: ['id'],
        },
        body: {
          type: 'object',
          properties: {
            imageUrls: { type: 'array', items: { type: 'string' }, minItems: 1, maxItems: 3 },
          },
          required: ['imageUrls'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { imageUrls: string[] } }>,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.reportNoshow(
        request.user.userId,
        request.params.id,
        request.body.imageUrls,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /matches/:id/forfeit ───
  fastify.post(
    '/matches/:id/forfeit',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Matching'],
        summary: '매칭 포기 (패배 처리)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
          required: ['id'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await matchingService.forfeitMatch(request.user.userId, request.params.id);
      return reply.send({ success: true, data });
    },
  );
}
