import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { AppDataSource } from '../../config/database.js';
import { Report, Inquiry, UserSanction, User, AdminRole } from '../../entities/index.js';
import { ReportTargetType, UserStatus } from '../../entities/enums.js';
import { sendAdminAlert, escapeHtml } from '../../shared/services/telegram.service.js';
import { requireAdmin } from '../admin/admin.middleware.js';

// ─── 입력 스키마 ───

const createReportSchema = z.object({
  targetType: z.nativeEnum(ReportTargetType),
  targetId: z.string().uuid(),
  reason: z.string().min(1).max(50),
  description: z.string().max(1000).optional(),
});

const createInquirySchema = z.object({
  category: z.enum(['ACCOUNT', 'MATCH', 'SCORE', 'BUG', 'SUGGESTION', 'OTHER']),
  title: z.string().min(1).max(200),
  content: z.string().min(1),
  imageUrl: z.string().url().optional(),
});

const INQUIRY_STATUSES = ['OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'] as const;

const adminListInquiriesQuerySchema = z.object({
  status: z.enum(INQUIRY_STATUSES).optional(),
  category: z.enum(['ACCOUNT', 'MATCH', 'SCORE', 'BUG', 'SUGGESTION', 'OTHER']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

const adminUpdateInquirySchema = z.object({
  status: z.enum(INQUIRY_STATUSES).optional(),
  adminReply: z.string().max(5000).optional(),
}).refine((d) => d.status !== undefined || d.adminReply !== undefined, {
  message: 'status 또는 adminReply 중 최소 하나는 필요합니다.',
});

type CreateReportDto = z.infer<typeof createReportSchema>;
type CreateInquiryDto = z.infer<typeof createInquirySchema>;

export async function reportsRoutes(fastify: FastifyInstance): Promise<void> {
  const reportRepo = AppDataSource.getRepository(Report);
  const inquiryRepo = AppDataSource.getRepository(Inquiry);
  const sanctionRepo = AppDataSource.getRepository(UserSanction);
  const userRepo = AppDataSource.getRepository(User);

  // ─── POST /reports — 신고 접수 ───
  fastify.post(
    '/reports',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Reports'],
        summary: '신고 접수',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: CreateReportDto }>, reply: FastifyReply) => {
      const dto = createReportSchema.parse(request.body);
      const reporterId = request.user.userId;

      // 신고 레코드 저장
      const report = reportRepo.create({
        reporterId,
        targetType: dto.targetType,
        targetId: dto.targetId,
        reason: dto.reason,
        description: dto.description ?? null,
      });
      await reportRepo.save(report);

      // 자동 제재 체크: 같은 대상에 7일 내 3건 이상(서로 다른 신고자)이면 24시간 정지
      const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

      const recentReportCount = await reportRepo
        .createQueryBuilder('r')
        .where('r.targetType = :targetType', { targetType: dto.targetType })
        .andWhere('r.targetId = :targetId', { targetId: dto.targetId })
        .andWhere('r.createdAt >= :since', { since: sevenDaysAgo })
        .select('r.reporterId')
        .distinct(true)
        .getCount();

      if (recentReportCount >= 3 && dto.targetType === ReportTargetType.USER) {
        // 이미 활성 자동 제재가 있는지 확인 (issuedBy IS NULL = 자동 제재)
        const existingSanction = await sanctionRepo
          .createQueryBuilder('s')
          .where('s.userId = :userId', { userId: dto.targetId })
          .andWhere('s.isActive = true')
          .andWhere('s.issuedBy IS NULL')
          .getOne();

        if (!existingSanction) {
          const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
          const sanction = sanctionRepo.create({
            userId: dto.targetId,
            type: 'SUSPEND',
            reason: `7일 내 ${recentReportCount}건 이상 신고 누적으로 자동 정지`,
            reportId: report.id,
            issuedBy: null, // null = auto
            expiresAt,
            isActive: true,
          });
          await sanctionRepo.save(sanction);

          // 유저 상태 SUSPENDED로 변경
          await userRepo.update({ id: dto.targetId }, { status: UserStatus.SUSPENDED });
        }
      }

      // 텔레그램 관리자 알림
      try {
        const reporter = await userRepo.findOne({ where: { id: reporterId } });
        void sendAdminAlert(
          `🚨 <b>신고 접수</b>\n` +
            `• 신고자: ${escapeHtml(reporter?.nickname ?? reporterId)}\n` +
            `• 대상: ${escapeHtml(dto.targetType)} <code>${escapeHtml(dto.targetId)}</code>\n` +
            `• 사유: ${escapeHtml(dto.reason)}\n` +
            (dto.description ? `• 내용: ${escapeHtml(dto.description)}` : ''),
        );
      } catch (_) {}

      return reply.status(201).send({
        success: true,
        data: { id: report.id, message: '신고가 접수되었습니다.' },
      });
    },
  );

  // ─── POST /inquiries — 문의 접수 ───
  fastify.post(
    '/inquiries',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Inquiries'],
        summary: '문의 접수',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: CreateInquiryDto }>, reply: FastifyReply) => {
      const dto = createInquirySchema.parse(request.body);
      const userId = request.user.userId;

      // 이미지 URL이 있으면 content 하단에 첨부
      const contentWithImage = dto.imageUrl
        ? `${dto.content}\n\n[첨부 이미지] ${dto.imageUrl}`
        : dto.content;

      const inquiry = inquiryRepo.create({
        userId,
        category: dto.category,
        title: dto.title,
        content: contentWithImage,
        status: 'OPEN',
        adminReply: null,
        resolvedAt: null,
      });
      await inquiryRepo.save(inquiry);

      // 텔레그램 관리자 알림
      try {
        const u = await userRepo.findOne({ where: { id: userId } });
        void sendAdminAlert(
          `📩 <b>문의 접수</b>\n` +
            `• 닉네임: ${escapeHtml(u?.nickname ?? userId)}\n` +
            `• 카테고리: ${escapeHtml(dto.category)}\n` +
            `• 제목: ${escapeHtml(dto.title)}\n` +
            `• 내용: ${escapeHtml(dto.content.slice(0, 500))}`,
        );
      } catch (_) {}

      return reply.status(201).send({
        success: true,
        data: { id: inquiry.id, message: '문의가 접수되었습니다.' },
      });
    },
  );

  // ─── GET /inquiries — 내 문의 목록 ───
  fastify.get(
    '/inquiries',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Inquiries'],
        summary: '내 문의 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userId = request.user.userId;

      const inquiries = await inquiryRepo.find({
        where: { userId },
        order: { createdAt: 'DESC' },
        select: {
          id: true,
          category: true,
          title: true,
          content: true,
          status: true,
          adminReply: true,
          resolvedAt: true,
          createdAt: true,
          updatedAt: true,
        },
      });

      return reply.send({ success: true, data: inquiries });
    },
  );

  // ─── GET /inquiries/:id — 문의 상세 ───
  fastify.get(
    '/inquiries/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Inquiries'],
        summary: '문의 상세',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const userId = request.user.userId;
      const { id } = request.params;

      const inquiry = await inquiryRepo.findOne({
        where: { id, userId },
      });

      if (!inquiry) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '문의를 찾을 수 없습니다.' },
        });
      }

      return reply.send({ success: true, data: inquiry });
    },
  );

  // ─── GET /admin/inquiries — 어드민: 문의 목록 ───
  fastify.get(
    '/admin/inquiries',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Inquiries'],
        summary: '[어드민] 문의 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const { status, category, page, pageSize } = adminListInquiriesQuerySchema.parse(request.query);

      const qb = inquiryRepo
        .createQueryBuilder('inq')
        .leftJoin('inq.user', 'u')
        .addSelect(['u.id', 'u.nickname', 'u.email'])
        .orderBy('inq.createdAt', 'DESC')
        .skip((page - 1) * pageSize)
        .take(pageSize);

      if (status) qb.andWhere('inq.status = :status', { status });
      if (category) qb.andWhere('inq.category = :category', { category });

      const [items, total] = await qb.getManyAndCount();

      return reply.send({
        success: true,
        data: items,
        meta: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    },
  );

  // ─── GET /admin/inquiries/:id — 어드민: 문의 상세 ───
  fastify.get(
    '/admin/inquiries/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Inquiries'],
        summary: '[어드민] 문의 상세',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const inquiry = await inquiryRepo
        .createQueryBuilder('inq')
        .leftJoin('inq.user', 'u')
        .addSelect(['u.id', 'u.nickname', 'u.email'])
        .where('inq.id = :id', { id: request.params.id })
        .getOne();

      if (!inquiry) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '문의를 찾을 수 없습니다.' },
        });
      }
      return reply.send({ success: true, data: inquiry });
    },
  );

  // ─── PATCH /admin/inquiries/:id — 어드민: 상태/답변 ───
  fastify.patch(
    '/admin/inquiries/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Inquiries'],
        summary: '[어드민] 문의 상태/답변 업데이트',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const dto = adminUpdateInquirySchema.parse(request.body);

      const inquiry = await inquiryRepo.findOne({ where: { id: request.params.id } });
      if (!inquiry) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '문의를 찾을 수 없습니다.' },
        });
      }

      if (dto.status !== undefined) inquiry.status = dto.status;
      if (dto.adminReply !== undefined) inquiry.adminReply = dto.adminReply;
      // RESOLVED/CLOSED 전환 시 resolvedAt 자동 기록 (이전 값 있으면 유지)
      if ((dto.status === 'RESOLVED' || dto.status === 'CLOSED') && !inquiry.resolvedAt) {
        inquiry.resolvedAt = new Date();
      }

      await inquiryRepo.save(inquiry);

      return reply.send({ success: true, data: inquiry });
    },
  );
}
