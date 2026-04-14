import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { PinsService } from './pins.service.js';
import {
  nearbyPinsQuerySchema,
  listPostsQuerySchema,
  createPostSchema,
  updatePostSchema,
  createCommentSchema,
  type NearbyPinsQuery,
  type ListPostsQuery,
  type CreatePostDto,
  type UpdatePostDto,
  type CreateCommentDto,
} from './pins.schema.js';
import { likeRateLimitConfig } from '../../shared/middleware/rate-limit.js';

export async function pinsRoutes(fastify: FastifyInstance): Promise<void> {
  const pinsService = new PinsService();

  // ─── GET /pins/all ───
  // ?version=20260405123000 → 버전 같으면 data: null, changed: false
  fastify.get(
    '/pins/all',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '전체 핀 목록 (버전 기반 동기화)',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            version: { type: 'string', description: '클라이언트 핀 데이터 버전' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Querystring: { version?: string } }>, reply: FastifyReply) => {
      const clientVersion = request.query.version;
      const result = await pinsService.getAllPinsIfChanged(clientVersion);

      if (!result.changed) {
        return reply.send({
          success: true,
          data: null,
          meta: { version: result.version, changed: false },
        });
      }

      return reply.send({
        success: true,
        data: result.pins,
        meta: { version: result.version, changed: true },
      });
    },
  );

  // ─── GET /pins/batch ── (배치 조회: ids 쿼리 파라미터)
  fastify.get(
    '/pins/batch',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '핀 배치 조회 (ids)',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            ids: { type: 'string', description: '콤마 구분 핀 ID 목록' },
          },
          required: ['ids'],
        },
      },
    },
    async (request: FastifyRequest<{ Querystring: { ids: string } }>, reply: FastifyReply) => {
      const ids = request.query.ids.split(',').map((id) => id.trim()).filter(Boolean);
      if (ids.length === 0 || ids.length > 50) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'ids는 1~50개까지 가능합니다.' },
        });
      }
      const data = await pinsService.getPinsByIds(ids);
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /pins/favorite ───
  fastify.post(
    '/pins/favorite',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '자주 가는 핀 등록',
        security: [{ bearerAuth: [] }],
        body: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
          },
          required: ['pinId'],
        },
      },
    },
    async (request: FastifyRequest<{ Body: { pinId: string } }>, reply: FastifyReply) => {
      await pinsService.setFavoritePin(request.user.userId, request.body.pinId);
      return reply.send({ success: true, data: { message: '자주 가는 핀이 등록되었습니다.' } });
    },
  );

  // ─── GET /pins/nearby ───
  fastify.get(
    '/pins/nearby',
    {
      onRequest: [fastify.authenticate],
      schema: { tags: ['Pins'], summary: '주변 핀 목록', security: [{ bearerAuth: [] }] },
    },
    async (request: FastifyRequest<{ Querystring: NearbyPinsQuery }>, reply: FastifyReply) => {
      const query = nearbyPinsQuerySchema.parse(request.query);
      const data = await pinsService.getNearbyPins(query);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /pins/:id ───
  fastify.get(
    '/pins/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '핀 상세 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const data = await pinsService.getPin(request.params.id);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /pins/:pinId/posts ───
  fastify.get(
    '/pins/:pinId/posts',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '게시글 목록',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { pinId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string }; Querystring: ListPostsQuery }>,
      reply: FastifyReply,
    ) => {
      const query = listPostsQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await pinsService.getPosts(request.params.pinId, query);
      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── POST /pins/:pinId/posts ───
  fastify.post(
    '/pins/:pinId/posts',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '게시글 작성',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { pinId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string }; Body: CreatePostDto }>,
      reply: FastifyReply,
    ) => {
      const dto = createPostSchema.parse(request.body);
      const data = await pinsService.createPost(request.params.pinId, request.user.userId, dto);
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── GET /pins/:pinId/posts/:postId ───
  fastify.get(
    '/pins/:pinId/posts/:postId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '게시글 상세',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string; postId: string }; Querystring: { sportType?: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await pinsService.getPost(
        request.params.pinId,
        request.params.postId,
        request.user.userId,
        request.query.sportType,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /pins/:pinId/posts/:postId ───
  fastify.patch(
    '/pins/:pinId/posts/:postId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '게시글 수정',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string; postId: string }; Body: UpdatePostDto }>,
      reply: FastifyReply,
    ) => {
      const dto = updatePostSchema.parse(request.body ?? {});
      const data = await pinsService.updatePost(
        request.params.pinId,
        request.params.postId,
        request.user.userId,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── DELETE /pins/:pinId/posts/:postId ───
  fastify.delete(
    '/pins/:pinId/posts/:postId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '게시글 삭제',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string; postId: string } }>,
      reply: FastifyReply,
    ) => {
      await pinsService.deletePost(
        request.params.pinId,
        request.params.postId,
        request.user.userId,
      );
      return reply.send({ success: true, data: { message: '게시글이 삭제되었습니다.' } });
    },
  );

  // ─── POST /pins/:pinId/posts/:postId/comments ───
  fastify.post(
    '/pins/:pinId/posts/:postId/comments',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '댓글 작성',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { pinId: string; postId: string };
        Body: CreateCommentDto;
      }>,
      reply: FastifyReply,
    ) => {
      const dto = createCommentSchema.parse(request.body);
      const data = await pinsService.createComment(
        request.params.pinId,
        request.params.postId,
        request.user.userId,
        dto,
      );
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── GET /pins/:pinId/posts/:postId/comments ───
  fastify.get(
    '/pins/:pinId/posts/:postId/comments',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '댓글 목록',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { pinId: string; postId: string };
        Querystring: { cursor?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { items, nextCursor, hasMore } = await pinsService.getComments(
        request.params.postId,
        { cursor: request.query.cursor, limit: request.query.limit },
      );
      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── DELETE /pins/:pinId/posts/:postId/comments/:commentId ───
  fastify.delete(
    '/pins/:pinId/posts/:postId/comments/:commentId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Pins'],
        summary: '댓글 삭제 (소프트 삭제)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
            commentId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string; postId: string; commentId: string } }>,
      reply: FastifyReply,
    ) => {
      await pinsService.softDeleteComment(
        request.params.pinId,
        request.params.postId,
        request.params.commentId,
        request.user.userId,
      );
      return reply.send({ success: true, data: { message: '댓글이 삭제되었습니다.' } });
    },
  );

  // ─── POST /pins/:pinId/posts/:postId/like ───
  fastify.post(
    '/pins/:pinId/posts/:postId/like',
    {
      onRequest: [fastify.authenticate],
      ...likeRateLimitConfig,
      schema: {
        tags: ['Pins'],
        summary: '게시글 좋아요 토글',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            pinId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { pinId: string; postId: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await pinsService.toggleLike(
        request.params.pinId,
        request.params.postId,
        request.user.userId,
      );
      return reply.send({ success: true, data });
    },
  );
}
