import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { UploadsService } from './uploads.service.js';
import { uploadRateLimitConfig } from '../../shared/middleware/rate-limit.js';
import { generateThumbnail } from '../../workers/thumbnail.worker.js';

const presignedUrlSchema = z.object({
  fileType: z.enum(['PROFILE_IMAGE', 'GAME_RESULT', 'POST_IMAGE', 'CHAT_IMAGE']),
  contentType: z.string().min(1),
  fileSize: z.number().int().positive(),
});

export async function uploadsRoutes(fastify: FastifyInstance): Promise<void> {
  const uploadsService = new UploadsService();

  // ─── POST /uploads/presigned-url ───
  fastify.post(
    '/uploads/presigned-url',
    {
      onRequest: [fastify.authenticate],
      ...uploadRateLimitConfig,
      schema: {
        tags: ['Uploads'],
        summary: 'S3 Presigned URL 발급',
        security: [{ bearerAuth: [] }],
        body: {
          type: 'object',
          required: ['fileType', 'contentType', 'fileSize'],
          properties: {
            fileType: {
              type: 'string',
              enum: ['PROFILE_IMAGE', 'GAME_RESULT', 'POST_IMAGE', 'CHAT_IMAGE'],
            },
            contentType: { type: 'string' },
            fileSize: { type: 'integer', minimum: 1 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Body: z.infer<typeof presignedUrlSchema> }>,
      reply: FastifyReply,
    ) => {
      const dto = presignedUrlSchema.parse(request.body);
      const data = await uploadsService.getPresignedUrl(request.user.userId, dto);
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /uploads/confirm ── (업로드 완료 확인 + 썸네일 생성)
  fastify.post(
    '/uploads/confirm',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Uploads'],
        summary: '업로드 완료 확인 및 썸네일 생성',
        security: [{ bearerAuth: [] }],
        body: {
          type: 'object',
          required: ['key'],
          properties: {
            key: { type: 'string', description: 'S3 object key' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Body: { key: string } }>,
      reply: FastifyReply,
    ) => {
      const { key } = request.body;
      // 비동기로 썸네일 생성 (클라이언트는 기다리지 않음)
      generateThumbnail(key).catch((err) => {
        request.log.error({ err, key }, 'Thumbnail generation failed');
      });
      return reply.send({ success: true, data: { key, status: 'processing' } });
    },
  );
}
