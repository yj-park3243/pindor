import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { AppDataSource } from '../../config/database.js';
import { AdminRole, Dispute, Match } from '../../entities/index.js';
import { requireAdmin } from '../admin/admin.middleware.js';

// ─── 입력 스키마 ───

const createDisputeSchema = z.object({
  matchId: z.string().uuid('올바른 매칭 ID가 아닙니다.'),
  title: z.string().min(1, '제목을 입력해주세요.').max(200, '제목은 200자 이하로 입력해주세요.'),
  content: z.string().min(1, '내용을 입력해주세요.'),
  imageUrls: z.array(z.string().url()).max(3).optional(),
  phoneNumber: z.string().max(20).optional(),
});

const listDisputesQuerySchema = z.object({
  page: z.coerce.number().min(1).default(1),
  pageSize: z.coerce.number().min(1).max(50).default(20),
});

const adminListDisputesQuerySchema = z.object({
  status: z.enum(['PENDING', 'IN_PROGRESS', 'RESOLVED']).optional(),
  page: z.coerce.number().min(1).default(1),
  pageSize: z.coerce.number().min(1).max(50).default(20),
});

const adminUpdateDisputeSchema = z.object({
  status: z.enum(['IN_PROGRESS', 'RESOLVED']),
  adminReply: z.string().optional(),
});

type CreateDisputeDto = z.infer<typeof createDisputeSchema>;
type AdminUpdateDisputeDto = z.infer<typeof adminUpdateDisputeSchema>;

export async function disputesRoutes(fastify: FastifyInstance): Promise<void> {
  const disputeRepo = AppDataSource.getRepository(Dispute);
  const matchRepo = AppDataSource.getRepository(Match);

  // ─── POST /disputes — 의의 제기 접수 ───
  fastify.post(
    '/disputes',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Disputes'],
        summary: '의의 제기 접수',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const dto = createDisputeSchema.parse(request.body);
      const reporterId = request.user.userId;

      // 매칭 존재 여부 확인
      const match = await matchRepo.findOne({ where: { id: dto.matchId } });
      if (!match) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '매칭을 찾을 수 없습니다.' },
        });
      }

      const dispute = disputeRepo.create({
        matchId: dto.matchId,
        reporterId,
        title: dto.title,
        content: dto.content,
        imageUrls: dto.imageUrls ?? [],
        phoneNumber: dto.phoneNumber ?? null,
        status: 'PENDING',
        adminReply: null,
        resolvedBy: null,
      });

      await disputeRepo.save(dispute);

      return reply.status(201).send({
        success: true,
        data: { id: dispute.id, message: '의의 제기가 접수되었습니다.' },
      });
    },
  );

  // ─── GET /disputes — 내 의의 제기 목록 ───
  fastify.get(
    '/disputes',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Disputes'],
        summary: '내 의의 제기 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userId = request.user.userId;
      const query = listDisputesQuerySchema.parse(request.query);
      const { page, pageSize } = query;

      const [items, total] = await disputeRepo.findAndCount({
        where: { reporterId: userId },
        order: { createdAt: 'DESC' },
        skip: (page - 1) * pageSize,
        take: pageSize,
        select: {
          id: true,
          matchId: true,
          title: true,
          status: true,
          adminReply: true,
          createdAt: true,
          updatedAt: true,
        } as any,
      });

      return reply.send({
        success: true,
        data: items,
        meta: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    },
  );

  // ─── GET /disputes/:id — 의의 제기 상세 ───
  fastify.get(
    '/disputes/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Disputes'],
        summary: '의의 제기 상세',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userId = request.user.userId;
      const { id } = request.params as { id: string };

      const dispute = await disputeRepo.findOne({
        where: { id, reporterId: userId },
      });

      if (!dispute) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '의의 제기를 찾을 수 없습니다.' },
        });
      }

      return reply.send({ success: true, data: dispute });
    },
  );

  // ─── GET /admin/disputes — 어드민: 전체 의의 제기 목록 ───
  fastify.get(
    '/admin/disputes',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Disputes'],
        summary: '[어드민] 의의 제기 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const query = adminListDisputesQuerySchema.parse(request.query);
      const { status, page, pageSize } = query as any;

      const qb = disputeRepo
        .createQueryBuilder('d')
        .leftJoin('d.reporter', 'reporter')
        .addSelect(['reporter.id', 'reporter.nickname', 'reporter.email'])
        .orderBy('d.createdAt', 'DESC')
        .skip((page - 1) * pageSize)
        .take(pageSize);

      if (status) {
        qb.where('d.status = :status', { status });
      }

      const [items, total] = await qb.getManyAndCount();

      return reply.send({
        success: true,
        data: items,
        meta: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    },
  );

  // ─── PATCH /admin/disputes/:id — 어드민: 의의 제기 처리 ───
  fastify.patch(
    '/admin/disputes/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Disputes'],
        summary: '[어드민] 의의 제기 상태 업데이트',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const { id } = request.params as { id: string };
      const dto = adminUpdateDisputeSchema.parse(request.body);
      const adminId = request.user.userId;

      const dispute = await disputeRepo.findOne({ where: { id } });
      if (!dispute) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '의의 제기를 찾을 수 없습니다.' },
        });
      }

      await disputeRepo.update(id, {
        status: dto.status,
        adminReply: dto.adminReply ?? dispute.adminReply,
        resolvedBy: dto.status === 'RESOLVED' ? adminId : dispute.resolvedBy,
      });

      const updated = await disputeRepo.findOne({ where: { id } });

      return reply.send({ success: true, data: updated });
    },
  );
}
