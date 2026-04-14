import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Match, MatchStatus } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminMatchesRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/matches ───
  fastify.get(
    '/admin/matches',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '매치 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          status?: string;
          sportType?: string;
          search?: string;
          page?: number;
          pageSize?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { status, sportType, search } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const matchRepo = AppDataSource.getRepository(Match);
      const qb = matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser');

      if (status) {
        qb.andWhere('match.status = :status', { status: status as MatchStatus });
      }
      if (sportType) {
        qb.andWhere('match.sportType = :sportType', { sportType });
      }
      if (search) {
        qb.andWhere(
          '(requesterUser.nickname ILIKE :search OR opponentUser.nickname ILIKE :search)',
          { search: `%${search}%` },
        );
      }

      const [items, total] = await qb
        .orderBy('match.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/matches/:id ───
  fastify.get(
    '/admin/matches/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '매치 상세 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('match.id = :id', { id: request.params.id })
        .getOne();

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      return reply.send({ success: true, data: match });
    },
  );

  // ─── PATCH /admin/matches/:id/force-cancel ───
  fastify.patch(
    '/admin/matches/:id/force-cancel',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '매치 강제 취소',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['reason'],
          properties: { reason: { type: 'string', minLength: 1 } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { reason } = request.body;

      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo.findOne({ where: { id } });

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      await matchRepo.update(id, {
        status: MatchStatus.CANCELLED,
        cancelReason: reason,
        cancelledBy: request.user.userId,
      });

      const updatedMatch = await matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('match.id = :id', { id })
        .getOne();

      return reply.send({ success: true, data: updatedMatch });
    },
  );

  // ─── PATCH /admin/matches/:id/force-complete ───
  fastify.patch(
    '/admin/matches/:id/force-complete',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '매치 강제 완료',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo.findOne({ where: { id } });

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      await matchRepo.update(id, {
        status: MatchStatus.COMPLETED,
        completedAt: new Date(),
      });

      const updatedMatch = await matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('match.id = :id', { id })
        .getOne();

      return reply.send({ success: true, data: updatedMatch });
    },
  );
}
