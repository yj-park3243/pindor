import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { ChatService } from './chat.service.js';

const sendMessageSchema = z.object({
  messageType: z.enum(['TEXT', 'IMAGE', 'SYSTEM', 'SCHEDULE_PROPOSAL', 'LOCATION']).default('TEXT'),
  content: z.string().max(500).optional(),
  imageUrl: z.string().url().optional(),
  extraData: z.record(z.unknown()).optional(),
});

const getMessagesQuerySchema = z.object({
  cursor: z.string().optional(),
  after: z.string().optional(), // ISO 날짜 — 이 시간 이후 메시지만 조회 (증분 fetch)
  limit: z.coerce.number().min(1).max(100).default(50),
});

export async function chatRoutes(fastify: FastifyInstance): Promise<void> {
  const chatService = new ChatService();

  // ─── GET /chat-rooms ───
  fastify.get(
    '/chat-rooms',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Chat'],
        summary: '내 채팅방 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const data = await chatService.getChatRooms(request.user.userId);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /chat-rooms/:id/messages ───
  fastify.get(
    '/chat-rooms/:id/messages',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Chat'],
        summary: '메시지 목록',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
        querystring: {
          type: 'object',
          properties: {
            cursor: { type: 'string' },
            after: { type: 'string', description: 'ISO 날짜 — 이 시간 이후 메시지만 조회' },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 50 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Querystring: { cursor?: string; after?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const query = getMessagesQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await chatService.getMessages(
        request.user.userId,
        request.params.id,
        query,
      );
      return reply.send({
        success: true,
        data: items,
        meta: { cursor: nextCursor, hasMore },
      });
    },
  );

  // ─── PATCH /chat-rooms/:id/read (읽음 처리 HTTP fallback) ───
  fastify.patch(
    '/chat-rooms/:id/read',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Chat'],
        summary: '메시지 읽음 처리',
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
      const readIds = await chatService.markMessagesRead(
        request.user.userId,
        request.params.id,
      );
      return reply.send({ success: true, data: { readCount: readIds.length } });
    },
  );

  // ─── POST /chat-rooms/:id/messages (HTTP Fallback) ───
  fastify.post(
    '/chat-rooms/:id/messages',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Chat'],
        summary: '메시지 전송 (HTTP fallback)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: z.infer<typeof sendMessageSchema>;
      }>,
      reply: FastifyReply,
    ) => {
      const dto = sendMessageSchema.parse(request.body);
      const data = await chatService.sendMessage(request.user.userId, request.params.id, dto);
      return reply.status(201).send({ success: true, data });
    },
  );
}
