import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { Notice, AdminRole } from '../../entities/index.js';
import { requireAdmin } from '../admin/admin.middleware.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

// ─── 타입 정의 ──────────────────────────────────────────────────────────────

type CreateNoticeBody = {
  title: string;
  content: string;
  isPinned?: boolean;
  isPublished?: boolean;
};

type PatchNoticeBody = {
  title?: string;
  content?: string;
  isPinned?: boolean;
  isPublished?: boolean;
};

type NoticeListQuery = {
  page?: number;
  limit?: number;
};

// ─── 라우트 ─────────────────────────────────────────────────────────────────

export async function noticesRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /notices ── 공지 목록 (공개, 페이지네이션) ───────────────────────
  fastify.get(
    '/notices',
    {
      schema: {
        tags: ['Notices'],
        summary: '공지사항 목록 조회 (공개)',
        querystring: {
          type: 'object',
          properties: {
            page: { type: 'integer', minimum: 1, default: 1 },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Querystring: NoticeListQuery }>,
      reply: FastifyReply,
    ) => {
      const page = request.query.page ?? 1;
      const limit = request.query.limit ?? 20;
      const skip = (page - 1) * limit;

      const repo = AppDataSource.getRepository(Notice);

      const [items, total] = await repo.findAndCount({
        where: { isPublished: true },
        order: { isPinned: 'DESC', createdAt: 'DESC' },
        skip,
        take: limit,
      });

      return reply.send({
        success: true,
        data: {
          items,
          pagination: {
            page,
            limit,
            total,
            totalPages: Math.ceil(total / limit),
          },
        },
      });
    },
  );

  // ─── GET /notices/pinned ── 메인 화면용 고정 공지 (공개) ──────────────────
  fastify.get(
    '/notices/pinned',
    {
      schema: {
        tags: ['Notices'],
        summary: '메인 화면용 고정 공지사항 조회 (공개)',
      },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const repo = AppDataSource.getRepository(Notice);

      const items = await repo.find({
        where: { isPinned: true, isPublished: true },
        order: { createdAt: 'DESC' },
        take: 5,
      });

      return reply.send({
        success: true,
        data: items,
      });
    },
  );

  // ─── GET /notices/:id ── 공지 상세 (공개) ────────────────────────────────
  fastify.get(
    '/notices/:id',
    {
      schema: {
        tags: ['Notices'],
        summary: '공지사항 상세 조회 (공개)',
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const repo = AppDataSource.getRepository(Notice);

      const notice = await repo.findOne({
        where: { id, isPublished: true },
      });

      if (!notice) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '공지사항을 찾을 수 없습니다.');
      }

      return reply.send({
        success: true,
        data: notice,
      });
    },
  );

  // ─── POST /admin/notices ── 공지 생성 (ADMIN 전용) ───────────────────────
  fastify.post(
    '/admin/notices',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '공지사항 생성 (ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        body: {
          type: 'object',
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 200 },
            content: { type: 'string', minLength: 1 },
            isPinned: { type: 'boolean' },
            isPublished: { type: 'boolean' },
          },
          required: ['title', 'content'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Body: CreateNoticeBody }>,
      reply: FastifyReply,
    ) => {
      const { title, content, isPinned = false, isPublished = true } = request.body;
      const authorId = request.user?.userId ?? null;

      const repo = AppDataSource.getRepository(Notice);

      const notice = repo.create({
        title,
        content,
        isPinned,
        isPublished,
        authorId,
      });

      await repo.save(notice);

      return reply.status(201).send({
        success: true,
        data: notice,
      });
    },
  );

  // ─── PATCH /admin/notices/:id ── 공지 수정 (ADMIN 전용) ──────────────────
  fastify.patch(
    '/admin/notices/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '공지사항 수정 (ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
        body: {
          type: 'object',
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 200 },
            content: { type: 'string', minLength: 1 },
            isPinned: { type: 'boolean' },
            isPublished: { type: 'boolean' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: PatchNoticeBody }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const body = request.body;

      const repo = AppDataSource.getRepository(Notice);
      const notice = await repo.findOne({ where: { id } });

      if (!notice) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '공지사항을 찾을 수 없습니다.');
      }

      const updates: Partial<Notice> = {};

      if (body.title !== undefined) updates.title = body.title;
      if (body.content !== undefined) updates.content = body.content;
      if (body.isPinned !== undefined) updates.isPinned = body.isPinned;
      if (body.isPublished !== undefined) updates.isPublished = body.isPublished;

      if (Object.keys(updates).length === 0) {
        return reply.status(400).send({
          success: false,
          error: {
            code: ErrorCode.VALIDATION_ERROR,
            message: '수정할 필드가 없습니다.',
          },
        });
      }

      await repo.update(id, updates);
      const updated = await repo.findOne({ where: { id } });

      return reply.send({
        success: true,
        data: updated,
      });
    },
  );

  // ─── DELETE /admin/notices/:id ── 공지 삭제 (ADMIN 전용) ─────────────────
  fastify.delete(
    '/admin/notices/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '공지사항 삭제 (ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const repo = AppDataSource.getRepository(Notice);

      const notice = await repo.findOne({ where: { id } });

      if (!notice) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '공지사항을 찾을 수 없습니다.');
      }

      await repo.delete(id);

      return reply.send({
        success: true,
        data: { id },
      });
    },
  );

  // ─── GET /legal/privacy ── 개인정보 처리방침 URL (공개) ──────────────────
  fastify.get(
    '/legal/privacy',
    {
      schema: {
        tags: ['Legal'],
        summary: '개인정보 처리방침 URL 조회 (공개)',
      },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({
        success: true,
        data: { url: 'https://pins.kr/privacy.html' },
      });
    },
  );

  // ─── GET /legal/terms ── 이용약관 URL (공개) ─────────────────────────────
  fastify.get(
    '/legal/terms',
    {
      schema: {
        tags: ['Legal'],
        summary: '이용약관 URL 조회 (공개)',
      },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({
        success: true,
        data: { url: 'https://pins.kr/terms.html' },
      });
    },
  );
}
