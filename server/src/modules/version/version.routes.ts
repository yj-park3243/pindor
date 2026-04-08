import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { AppVersion } from '../../entities/index.js';
import { AdminRole } from '../../entities/index.js';
import { requireAdmin } from '../admin/admin.middleware.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

// ─── 기본 데이터 시딩 ───────────────────────────────────────────────────────
async function seedDefaultVersions(): Promise<void> {
  const repo = AppDataSource.getRepository(AppVersion);
  const count = await repo.count();
  if (count === 0) {
    await repo.save([
      repo.create({
        platform: 'IOS',
        minVersion: '1.0.0',
        latestVersion: '1.0.0',
        latestBuild: 4,
        storeUrl: 'https://apps.apple.com/app/kr.pins',
      }),
      repo.create({
        platform: 'ANDROID',
        minVersion: '1.0.0',
        latestVersion: '1.0.0',
        latestBuild: 4,
        storeUrl: 'https://play.google.com/store/apps/details?id=kr.pins.spots',
      }),
    ]);
  }
}

// ─── PATCH body 타입 ────────────────────────────────────────────────────────
type PatchVersionBody = {
  minVersion?: string;
  latestVersion?: string;
  latestBuild?: number;
  forceUpdate?: boolean;
  updateMessage?: string | null;
  storeUrl?: string | null;
};

export async function versionRoutes(fastify: FastifyInstance): Promise<void> {
  // 라우트 등록 시 기본 데이터 시딩
  await seedDefaultVersions();

  // ─── GET /app-version ── 공개 엔드포인트 (인증 불필요) ─────────────────────
  fastify.get(
    '/app-version',
    {
      schema: {
        tags: ['Version'],
        summary: '앱 버전 정보 조회 (공개)',
        querystring: {
          type: 'object',
          properties: {
            platform: { type: 'string', enum: ['IOS', 'ANDROID'] },
          },
          required: ['platform'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Querystring: { platform: string } }>,
      reply: FastifyReply,
    ) => {
      const { platform } = request.query;

      if (!platform || !['IOS', 'ANDROID'].includes(platform.toUpperCase())) {
        return reply.status(400).send({
          success: false,
          error: {
            code: ErrorCode.VALIDATION_ERROR,
            message: 'platform은 IOS 또는 ANDROID 이어야 합니다.',
          },
        });
      }

      const repo = AppDataSource.getRepository(AppVersion);
      const versionInfo = await repo.findOne({
        where: { platform: platform.toUpperCase() },
      });

      if (!versionInfo) {
        return reply.status(404).send({
          success: false,
          error: {
            code: ErrorCode.NOT_FOUND,
            message: '버전 정보를 찾을 수 없습니다.',
          },
        });
      }

      return reply.send({
        success: true,
        data: {
          minVersion: versionInfo.minVersion,
          latestVersion: versionInfo.latestVersion,
          latestBuild: versionInfo.latestBuild,
          forceUpdate: versionInfo.forceUpdate,
          updateMessage: versionInfo.updateMessage,
          storeUrl: versionInfo.storeUrl,
        },
      });
    },
  );

  // ─── GET /admin/app-versions ── 전체 버전 목록 조회 (ADMIN 전용) ──────────
  fastify.get(
    '/admin/app-versions',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '앱 버전 목록 조회 (ADMIN 전용)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const repo = AppDataSource.getRepository(AppVersion);
      const versions = await repo.find({ order: { platform: 'ASC' } });

      return reply.send({
        success: true,
        data: versions,
      });
    },
  );

  // ─── PATCH /admin/app-versions/:id ── 버전 정보 수정 (ADMIN 전용) ─────────
  fastify.patch(
    '/admin/app-versions/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '앱 버전 정보 수정 (ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: PatchVersionBody }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const body = request.body as PatchVersionBody;

      const repo = AppDataSource.getRepository(AppVersion);
      const versionInfo = await repo.findOne({ where: { id } });

      if (!versionInfo) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '버전 정보를 찾을 수 없습니다.');
      }

      // 유효한 필드만 업데이트
      const updates: Partial<AppVersion> = {};

      if (body.minVersion !== undefined) {
        if (!/^\d+\.\d+\.\d+$/.test(body.minVersion)) {
          return reply.status(400).send({
            success: false,
            error: {
              code: ErrorCode.VALIDATION_ERROR,
              message: 'minVersion은 x.y.z 형식이어야 합니다.',
            },
          });
        }
        updates.minVersion = body.minVersion;
      }

      if (body.latestVersion !== undefined) {
        if (!/^\d+\.\d+\.\d+$/.test(body.latestVersion)) {
          return reply.status(400).send({
            success: false,
            error: {
              code: ErrorCode.VALIDATION_ERROR,
              message: 'latestVersion은 x.y.z 형식이어야 합니다.',
            },
          });
        }
        updates.latestVersion = body.latestVersion;
      }

      if (body.latestBuild !== undefined) {
        if (typeof body.latestBuild !== 'number' || body.latestBuild < 1) {
          return reply.status(400).send({
            success: false,
            error: {
              code: ErrorCode.VALIDATION_ERROR,
              message: 'latestBuild는 1 이상의 정수여야 합니다.',
            },
          });
        }
        updates.latestBuild = body.latestBuild;
      }

      if (body.forceUpdate !== undefined) {
        updates.forceUpdate = body.forceUpdate;
      }

      if (body.updateMessage !== undefined) {
        updates.updateMessage = body.updateMessage;
      }

      if (body.storeUrl !== undefined) {
        updates.storeUrl = body.storeUrl;
      }

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
}
