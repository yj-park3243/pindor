import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Report, User, Post, Comment, Match, ReportTargetType } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

export async function adminReportsExtRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/reports/:id ── 신고 상세 (대상 엔티티 포함)
  fastify.get(
    '/admin/reports/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '신고 상세 (대상 엔티티 포함)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const reportRepo = AppDataSource.getRepository(Report);

      const report = await reportRepo
        .createQueryBuilder('report')
        .leftJoinAndSelect('report.reporter', 'reporter')
        .where('report.id = :id', { id: request.params.id })
        .getOne();

      if (!report) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '신고를 찾을 수 없습니다.');
      }

      // targetType에 따라 대상 엔티티 조회
      let target: User | Post | Comment | Match | null = null;

      if (report.targetType === ReportTargetType.USER) {
        target = await AppDataSource.getRepository(User).findOne({
          where: { id: report.targetId },
        });
      } else if (report.targetType === ReportTargetType.POST) {
        target = await AppDataSource.getRepository(Post)
          .createQueryBuilder('post')
          .leftJoinAndSelect('post.author', 'author')
          .where('post.id = :id', { id: report.targetId })
          .getOne();
      } else if (report.targetType === ReportTargetType.COMMENT) {
        target = await AppDataSource.getRepository(Comment)
          .createQueryBuilder('comment')
          .leftJoinAndSelect('comment.author', 'author')
          .where('comment.id = :id', { id: report.targetId })
          .getOne();
      } else if (report.targetType === ReportTargetType.MATCH) {
        target = await AppDataSource.getRepository(Match).findOne({
          where: { id: report.targetId },
        });
      }

      return reply.send({
        success: true,
        data: {
          ...report,
          target,
        },
      });
    },
  );
}
