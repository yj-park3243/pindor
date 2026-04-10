import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { AppDataSource } from '../../config/database.js';
import { Report, Inquiry, UserSanction, User } from '../../entities/index.js';
import { ReportTargetType, UserStatus } from '../../entities/enums.js';

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
}
