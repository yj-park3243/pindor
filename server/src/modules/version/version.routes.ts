import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { AppVersion, AppVersionCheckLog, User } from '../../entities/index.js';
import { AdminRole } from '../../entities/index.js';
import { requireAdmin } from '../admin/admin.middleware.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { verifyAccessToken } from '../../shared/utils/jwt.js';
import { sendAdminAlert, escapeHtml } from '../../shared/services/telegram.service.js';
import { redis } from '../../config/redis.js';

// ─── 버전 체크 로그 저장 (실패해도 응답에 영향 없음) ──────────────────────────
async function saveVersionCheckLog(
  request: FastifyRequest,
  params: {
    platform: string;
    appVersion: string | null;
    latitude: number | null;
    longitude: number | null;
  },
): Promise<void> {
  try {
    const auth = request.headers.authorization;
    const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;

    let userId: string | null = null;
    let nickname: string | null = null;
    let email: string | null = null;
    let phoneNumber: string | null = null;
    if (token) {
      try {
        const payload = await verifyAccessToken(token);
        const userRepo = AppDataSource.getRepository(User);
        const user = await userRepo.findOne({
          where: { id: payload.userId },
          select: { id: true, nickname: true, email: true, phoneNumber: true } as any,
        });
        if (user) {
          userId = user.id;
          nickname = user.nickname ?? null;
          email = user.email ?? null;
          phoneNumber = user.phoneNumber ?? null;
        }
      } catch {
        /* 토큰 만료/위조는 무시 */
      }
    }

    const repo = AppDataSource.getRepository(AppVersionCheckLog);
    await repo.insert({
      userId,
      nickname,
      email,
      phoneNumber,
      platform: params.platform,
      appVersion: params.appVersion,
      latitude: params.latitude,
      longitude: params.longitude,
      ipAddress: request.ip ?? null,
      userAgent: (request.headers['user-agent'] as string) ?? null,
    });
  } catch (e) {
    console.warn('[VersionCheck] log save failed:', (e as Error).message);
  }
}

// ─── 앱 버전 체크 시 텔레그램 알림 (1시간 throttle) ──────────────────────────
async function notifyVersionCheck(
  request: FastifyRequest,
  platform: string,
): Promise<void> {
  try {
    const auth = request.headers.authorization;
    const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;

    let userInfo: { id: string; nickname: string } | null = null;
    if (token) {
      try {
        const payload = await verifyAccessToken(token);
        const userRepo = AppDataSource.getRepository(User);
        const user = await userRepo.findOne({
          where: { id: payload.userId },
          select: { id: true, nickname: true } as any,
        });
        if (user) userInfo = { id: user.id, nickname: user.nickname ?? '-' };
      } catch {
        /* 토큰 만료/위조는 무시 — 익명 처리 */
      }
    }

    // throttle: 같은 user(또는 IP) 1시간 1회
    const throttleKey = userInfo
      ? `version_check_notify:${userInfo.id}`
      : `version_check_notify:anon:${request.ip}`;
    const set = await redis.set(throttleKey, '1', 'EX', 3600, 'NX');
    if (set !== 'OK') return; // 이미 1시간 내 알림 발송됨

    const who = userInfo
      ? `${escapeHtml(userInfo.nickname)} <code>${escapeHtml(userInfo.id)}</code>`
      : `익명 (IP <code>${escapeHtml(request.ip)}</code>)`;
    void sendAdminAlert(
      `📲 <b>앱 접속</b>\n• ${who}\n• 플랫폼: ${escapeHtml(platform)}`,
    );
  } catch (e) {
    console.warn('[VersionCheck] telegram notify failed:', (e as Error).message);
  }
}

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
  showAd?: boolean;
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
            appVersion: { type: 'string' },
            lat: { type: 'string' },
            lng: { type: 'string' },
          },
          required: ['platform'],
        },
      },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          platform: string;
          appVersion?: string;
          lat?: string;
          lng?: string;
        };
      }>,
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

      // ─── 텔레그램 알림: 누가 앱 접속(버전 체크)했는지 ──
      // 토큰이 있으면 user 정보 추출, 없으면 익명. 같은 user는 1시간 1번만 발송 (Redis throttle).
      void notifyVersionCheck(request, platform.toUpperCase());

      // ─── 버전 체크 로그 저장 (위치 포함) ──
      const latRaw = request.query.lat;
      const lngRaw = request.query.lng;
      const latNum = latRaw != null ? Number(latRaw) : NaN;
      const lngNum = lngRaw != null ? Number(lngRaw) : NaN;
      void saveVersionCheckLog(request, {
        platform: platform.toUpperCase(),
        appVersion: request.query.appVersion ?? null,
        latitude: Number.isFinite(latNum) ? latNum : null,
        longitude: Number.isFinite(lngNum) ? lngNum : null,
      });

      return reply.send({
        success: true,
        data: {
          minVersion: versionInfo.minVersion,
          latestVersion: versionInfo.latestVersion,
          latestBuild: versionInfo.latestBuild,
          forceUpdate: versionInfo.forceUpdate,
          updateMessage: versionInfo.updateMessage,
          storeUrl: versionInfo.storeUrl,
          showAd: versionInfo.showAd,
          requirePhoneVerification: versionInfo.requirePhoneVerification,
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

      if (body.showAd !== undefined) {
        updates.showAd = body.showAd;
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

  // ─── GET /admin/version-check-logs ── 버전 체크 로그 조회 (ADMIN 전용) ─────
  fastify.get(
    '/admin/version-check-logs',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '앱 버전 체크 로그 조회 (ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            page: { type: 'integer', minimum: 1, default: 1 },
            pageSize: { type: 'integer', minimum: 1, maximum: 200, default: 50 },
            platform: { type: 'string', enum: ['IOS', 'ANDROID'] },
            userId: { type: 'string', format: 'uuid' },
            hasLocation: { type: 'boolean' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          page?: number;
          pageSize?: number;
          platform?: string;
          userId?: string;
          hasLocation?: boolean;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const page = request.query.page ?? 1;
      const pageSize = request.query.pageSize ?? 50;

      const repo = AppDataSource.getRepository(AppVersionCheckLog);
      const qb = repo.createQueryBuilder('log').orderBy('log.createdAt', 'DESC');

      if (request.query.platform) {
        qb.andWhere('log.platform = :platform', { platform: request.query.platform });
      }
      if (request.query.userId) {
        qb.andWhere('log.userId = :userId', { userId: request.query.userId });
      }
      if (request.query.hasLocation === true) {
        qb.andWhere('log.latitude IS NOT NULL AND log.longitude IS NOT NULL');
      } else if (request.query.hasLocation === false) {
        qb.andWhere('(log.latitude IS NULL OR log.longitude IS NULL)');
      }

      const total = await qb.getCount();
      const rows = await qb
        .skip((page - 1) * pageSize)
        .take(pageSize)
        .getMany();

      return reply.send({
        success: true,
        data: rows,
        total,
        page,
        pageSize,
      });
    },
  );
}
