import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { createHash } from 'crypto';
import { AdminRole, SocialProvider } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { User, SocialAccount, AdminProfile, AdminAccount } from '../../entities/index.js';
import { verifyRefreshToken, issueTokenPair } from '../../shared/utils/jwt.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

// ─── 시스템 기본 설정 (DB 없이 하드코딩) ───
const DEFAULT_SYSTEM_SETTINGS = {
  maintenanceMode: false,
  matchTimeout: 24,           // hours
  maxReportsBeforeAutoSuspend: 5,
  defaultMatchRadius: 10,     // km
  seasonDuration: 90,         // days
  appVersion: '1.0.0',
} as const;

type SystemSettings = {
  maintenanceMode?: boolean;
  matchTimeout?: number;
  maxReportsBeforeAutoSuspend?: number;
  defaultMatchRadius?: number;
  seasonDuration?: number;
  appVersion?: string;
};

export async function adminSettingsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── POST /admin/auth/logout ── 로그아웃 (stateless JWT)
  fastify.post(
    '/admin/auth/logout',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '어드민 로그아웃', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({ success: true, data: { message: '로그아웃 되었습니다.' } });
    },
  );

  // ─── POST /admin/auth/refresh ── 토큰 갱신
  fastify.post(
    '/admin/auth/refresh',
    {
      schema: { tags: ['Admin'], summary: '어드민 토큰 갱신' },
    },
    async (
      request: FastifyRequest<{ Body: { refreshToken: string } }>,
      reply: FastifyReply,
    ) => {
      const { refreshToken } = request.body as { refreshToken: string };

      if (!refreshToken) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'refreshToken이 필요합니다.' },
        });
      }

      const payload = await verifyRefreshToken(refreshToken);
      const tokens = await issueTokenPair({ userId: payload.userId, email: payload.email });

      return reply.send({
        success: true,
        data: {
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        },
      });
    },
  );

  // ─── GET /admin/settings/system ── 시스템 설정 조회
  fastify.get(
    '/admin/settings/system',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '시스템 설정 조회', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({
        success: true,
        data: { ...DEFAULT_SYSTEM_SETTINGS },
      });
    },
  );

  // ─── PATCH /admin/settings/system ── 시스템 설정 변경
  fastify.patch(
    '/admin/settings/system',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: { tags: ['Admin'], summary: '시스템 설정 변경 (SUPER_ADMIN 전용)', security: [{ bearerAuth: [] }] },
    },
    async (request: FastifyRequest<{ Body: SystemSettings }>, reply: FastifyReply) => {
      const body = request.body as SystemSettings;

      // 시스템 설정 테이블이 없으므로 메모리 병합 후 반환 (경고 로그)
      fastify.log.warn(
        '[admin-settings] PATCH /admin/settings/system: 시스템 설정 변경이 요청되었지만 ' +
          '영속 저장소가 없습니다. 변경사항이 서버 재시작 시 초기화됩니다.',
      );

      const merged = { ...DEFAULT_SYSTEM_SETTINGS, ...body };

      return reply.send({
        success: true,
        data: merged,
      });
    },
  );

  // ─── GET /admin/settings/accounts ── 어드민 계정 목록
  fastify.get(
    '/admin/settings/accounts',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: { tags: ['Admin'], summary: '어드민 계정 목록 (SUPER_ADMIN 전용)', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const adminAccountRepo = AppDataSource.getRepository(AdminAccount);
      const accounts = await adminAccountRepo.find({ order: { createdAt: 'ASC' } });

      return reply.send({
        success: true,
        data: accounts.map((a) => ({
          id: a.id,
          username: a.username,
          name: a.name,
          role: a.role,
          isActive: a.isActive,
          lastLoginAt: a.lastLoginAt,
          createdAt: a.createdAt,
        })),
      });
    },
  );

  // ─── POST /admin/settings/accounts ── 어드민 계정 생성
  fastify.post(
    '/admin/settings/accounts',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '어드민 계정 생성 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{
        Body: { username: string; password: string; name: string; role: AdminRole };
      }>,
      reply: FastifyReply,
    ) => {
      const { username, password, name, role } = request.body as {
        username: string;
        password: string;
        name: string;
        role: AdminRole;
      };

      if (!username || !password || !name || !role) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'username, password, name, role은 필수입니다.' },
        });
      }

      const adminAccountRepo = AppDataSource.getRepository(AdminAccount);
      const existing = await adminAccountRepo.findOne({ where: { username } });
      if (existing) {
        return reply.status(409).send({
          success: false,
          error: { code: 'CONFLICT', message: '이미 사용 중인 아이디입니다.' },
        });
      }

      const passwordHash = createHash('sha256').update(password).digest('hex');
      const account = adminAccountRepo.create({ username, passwordHash, name, role });
      await adminAccountRepo.save(account);

      return reply.status(201).send({
        success: true,
        data: {
          id: account.id,
          username: account.username,
          name: account.name,
          role: account.role,
          createdAt: account.createdAt,
        },
      });
    },
  );

  // ─── PATCH /admin/settings/accounts/:id ── 어드민 계정 수정
  fastify.patch(
    '/admin/settings/accounts/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '어드민 계정 수정 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { name?: string; role?: AdminRole; isActive?: boolean; password?: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const body = request.body as { name?: string; role?: AdminRole; isActive?: boolean; password?: string };

      const adminAccountRepo = AppDataSource.getRepository(AdminAccount);
      const account = await adminAccountRepo.findOne({ where: { id } });

      if (!account) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '어드민 계정을 찾을 수 없습니다.');
      }

      const updates: Partial<AdminAccount> = {};
      if (body.name !== undefined) updates.name = body.name;
      if (body.role !== undefined) updates.role = body.role;
      if (body.isActive !== undefined) updates.isActive = body.isActive;
      if (body.password) updates.passwordHash = createHash('sha256').update(body.password).digest('hex');

      await adminAccountRepo.update(id, updates);

      return reply.send({
        success: true,
        data: { id, ...updates, passwordHash: undefined },
      });
    },
  );

  // ─── DELETE /admin/settings/accounts/:id ── 어드민 계정 삭제
  fastify.delete(
    '/admin/settings/accounts/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '어드민 계정 삭제 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;

      const adminAccountRepo = AppDataSource.getRepository(AdminAccount);
      const account = await adminAccountRepo.findOne({ where: { id } });

      if (!account) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '어드민 계정을 찾을 수 없습니다.');
      }

      await adminAccountRepo.delete(id);

      return reply.send({ success: true, data: { message: '계정이 삭제되었습니다.' } });
    },
  );
}
