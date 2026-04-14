import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { AdminRole, AppErrorLog } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminErrorLogsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/error-logs ── 앱 에러 로그 목록 ───────
  fastify.get(
    '/admin/error-logs',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '앱 에러 로그 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          page?: number;
          pageSize?: number;
          screenName?: string;
          userId?: string;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { screenName, userId } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const repo = AppDataSource.getRepository(AppErrorLog);

      const qb = repo.createQueryBuilder('log');

      if (screenName) {
        qb.andWhere('log.screenName = :screenName', { screenName });
      }

      if (userId) {
        qb.andWhere('log.userId = :userId', { userId });
      }

      const [items, total] = await qb
        .orderBy('log.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({
        success: true,
        data: paginatedResponse(items, total, page, pageSize),
      });
    },
  );
}
