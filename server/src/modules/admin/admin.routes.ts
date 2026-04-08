import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { createHash } from 'crypto';
import { AdminRole, UserStatus, SocialProvider } from '../../entities/index.js';
import { AdminService } from './admin.service.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { User, SocialAccount, AdminProfile } from '../../entities/index.js';
import { issueTokenPair } from '../../shared/utils/jwt.js';

export async function adminRoutes(fastify: FastifyInstance): Promise<void> {
  const adminService = new AdminService();

  // ─── POST /admin/auth/login ── 어드민 이메일 로그인
  fastify.post(
    '/admin/auth/login',
    { schema: { tags: ['Admin'], summary: '어드민 로그인' } },
    async (request: FastifyRequest<{ Body: { email: string; password: string } }>, reply: FastifyReply) => {
      const { email, password } = request.body as { email: string; password: string };
      const passwordHash = createHash('sha256').update(password).digest('hex');

      const socialAccountRepo = AppDataSource.getRepository(SocialAccount);
      const adminProfileRepo = AppDataSource.getRepository(AdminProfile);

      // 이메일 계정 확인
      const social = await socialAccountRepo.findOne({
        where: { provider: SocialProvider.EMAIL, providerId: email },
        relations: { user: true },
      });

      if (!social || social.accessToken !== passwordHash) {
        return reply.status(401).send({
          success: false,
          error: { code: 'AUTH_INVALID', message: '이메일 또는 비밀번호가 올바르지 않습니다.' },
        });
      }

      // 어드민 권한 확인
      const adminProfile = await adminProfileRepo.findOne({
        where: { userId: social.user.id },
      });

      if (!adminProfile) {
        return reply.status(403).send({
          success: false,
          error: { code: 'AUTH_FORBIDDEN', message: '어드민 권한이 없습니다.' },
        });
      }

      const tokens = await issueTokenPair({ userId: social.user.id, email });

      return reply.send({
        success: true,
        data: {
          admin: {
            id: social.user.id,
            email,
            nickname: social.user.nickname,
            role: adminProfile.role,
          },
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        },
      });
    },
  );

  // ─── GET /admin/auth/me ── 내 어드민 정보
  fastify.get(
    '/admin/auth/me',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '내 어드민 정보', security: [{ bearerAuth: [] }] },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userRepo = AppDataSource.getRepository(User);
      const adminProfileRepo = AppDataSource.getRepository(AdminProfile);

      const user = await userRepo.findOne({ where: { id: request.user.userId } });
      const adminProfile = await adminProfileRepo.findOne({ where: { userId: request.user.userId } });

      return reply.send({
        success: true,
        data: {
          id: user?.id,
          email: user?.email,
          nickname: user?.nickname,
          role: adminProfile?.role,
        },
      });
    },
  );

  // ─── GET /admin/dashboard ───
  fastify.get(
    '/admin/dashboard',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '대시보드 지표', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const data = await adminService.getDashboard();
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /admin/users ───
  fastify.get(
    '/admin/users',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '사용자 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { status?: string; search?: string; cursor?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { items, nextCursor, hasMore } = await adminService.listUsers({
        status: request.query.status as UserStatus | undefined,
        search: request.query.search,
        cursor: request.query.cursor,
        limit: request.query.limit,
      });
      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── PATCH /admin/users/:id/suspend ───
  fastify.patch(
    '/admin/users/:id/suspend',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 정지',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { reason?: string } }>,
      reply: FastifyReply,
    ) => {
      await adminService.suspendUser(request.params.id, request.body?.reason ?? '');
      return reply.send({ success: true, data: { message: '사용자가 정지되었습니다.' } });
    },
  );

  // ─── PATCH /admin/users/:id/activate ───
  fastify.patch(
    '/admin/users/:id/activate',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 활성화',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      await adminService.activateUser(request.params.id);
      return reply.send({ success: true, data: { message: '사용자가 활성화되었습니다.' } });
    },
  );

  // ─── GET /admin/reports ───
  fastify.get(
    '/admin/reports',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '신고 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { status?: string; targetType?: string; cursor?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { items, nextCursor, hasMore } = await adminService.listReports(request.query);
      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── PATCH /admin/reports/:id/resolve ───
  fastify.patch(
    '/admin/reports/:id/resolve',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '신고 처리',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { action: 'RESOLVED' | 'DISMISSED' };
      }>,
      reply: FastifyReply,
    ) => {
      const action = request.body?.action ?? 'RESOLVED';
      await adminService.resolveReport(request.params.id, request.user.userId, action);
      return reply.send({ success: true, data: { message: '신고가 처리되었습니다.' } });
    },
  );

  // ─── GET /admin/games/disputed ───
  fastify.get(
    '/admin/games/disputed',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '이의 신청 경기 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{ Querystring: { cursor?: string; limit?: number } }>,
      reply: FastifyReply,
    ) => {
      const { items, nextCursor, hasMore } = await adminService.listDisputedGames(
        request.query,
      );
      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── POST /admin/games/:id/resolve-dispute ───
  fastify.post(
    '/admin/games/:id/resolve-dispute',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '이의 신청 처리',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: {
          action: 'KEEP_ORIGINAL' | 'MODIFY_RESULT' | 'VOID_GAME';
          requesterScore?: number;
          opponentScore?: number;
          winnerId?: string;
        };
      }>,
      reply: FastifyReply,
    ) => {
      await adminService.resolveDispute(
        request.params.id,
        request.user.userId,
        request.body,
      );
      return reply.send({ success: true, data: { message: '이의 신청이 처리되었습니다.' } });
    },
  );

  // ─── GET /admin/pins ───
  fastify.get(
    '/admin/pins',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '핀 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { level?: string; active?: string; cursor?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { items, nextCursor, hasMore } = await adminService.listPins({
        level: request.query.level,
        active: request.query.active === 'true',
        cursor: request.query.cursor,
        limit: request.query.limit,
      });
      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── PATCH /admin/pins/:id/activate ───
  fastify.patch(
    '/admin/pins/:id/activate',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '핀 활성화/비활성화',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { active: boolean } }>,
      reply: FastifyReply,
    ) => {
      await adminService.activatePin(request.params.id, request.body.active);
      return reply.send({
        success: true,
        data: { message: `핀이 ${request.body.active ? '활성화' : '비활성화'}되었습니다.` },
      });
    },
  );

  // ─── POST /admin/users/:id/grant-admin ───
  fastify.post(
    '/admin/users/:id/grant-admin',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '어드민 권한 부여 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { role: AdminRole };
      }>,
      reply: FastifyReply,
    ) => {
      await adminService.grantAdminRole(
        request.params.id,
        request.body.role,
        request.user.userId,
      );
      return reply.send({ success: true, data: { message: '어드민 권한이 부여되었습니다.' } });
    },
  );
}
