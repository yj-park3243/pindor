import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { KcpService } from './kcp.service.js';
import { kcpVerifySchema, type KcpVerifyDto } from './kcp.schema.js';
import { AppDataSource } from '../../config/database.js';

const DEFAULT_RETURN_URL = 'spots://kcp-cert';

export async function kcpRoutes(fastify: FastifyInstance): Promise<void> {
  const kcpService = new KcpService(AppDataSource);

  // ─── GET /auth/kcp/form ───
  fastify.get(
    '/auth/kcp/form',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Auth'],
        summary: 'KCP 본인인증 HTML Form 생성',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            returnUrl: { type: 'string', description: '인증 완료 후 리턴 URL (기본값: spots://kcp-cert)' },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              success: { type: 'boolean' },
              data: {
                type: 'object',
                properties: {
                  html: { type: 'string' },
                },
              },
            },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Querystring: { returnUrl?: string } }>,
      reply: FastifyReply,
    ) => {
      const userId = request.user.userId;
      const returnUrl = request.query.returnUrl ?? DEFAULT_RETURN_URL;

      const html = await kcpService.generateCertForm(userId, returnUrl);

      return reply.status(200).send({
        success: true,
        data: { html },
      });
    },
  );

  // ─── POST /auth/kcp/verify ───
  fastify.post(
    '/auth/kcp/verify',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Auth'],
        summary: 'KCP 본인인증 결과 검증',
        security: [{ bearerAuth: [] }],
        body: {
          type: 'object',
          required: ['key'],
          properties: {
            key: { type: 'string', description: 'KCP 인증 완료 후 전달받은 key' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Body: KcpVerifyDto }>,
      reply: FastifyReply,
    ) => {
      const dto = kcpVerifySchema.parse(request.body);
      const userId = request.user.userId;

      const result = await kcpService.verifyCert(userId, dto.key);

      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );
}
