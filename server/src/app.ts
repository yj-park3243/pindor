import Fastify, { FastifyInstance } from 'fastify';
import fastifyCors from '@fastify/cors';
import fastifyEtag from '@fastify/etag';
import fastifyFormbody from '@fastify/formbody';
import fastifyHelmet from '@fastify/helmet';
import fastifySwagger from '@fastify/swagger';
import fastifySwaggerUi from '@fastify/swagger-ui';
import { ZodError } from 'zod';
import { env } from './config/env.js';
import { AppError, ErrorCode } from './shared/errors/app-error.js';
import authPlugin from './shared/middleware/auth.middleware.js';
import { registerRateLimit } from './shared/middleware/rate-limit.js';

// ─── 라우트 임포트 ───
import { authRoutes } from './modules/auth/auth.routes.js';
import { kcpRoutes } from './modules/auth/kcp.routes.js';
import { usersRoutes } from './modules/users/users.routes.js';
import { blocksRoutes } from './modules/users/blocks.routes.js';
import { profilesRoutes } from './modules/profiles/profiles.routes.js';
import { matchingRoutes } from './modules/matching/matching.routes.js';
import { gamesRoutes } from './modules/games/games.routes.js';
import { chatRoutes } from './modules/chat/chat.routes.js';
import { rankingRoutes } from './modules/rankings/ranking.routes.js';
import { pinsRoutes } from './modules/pins/pins.routes.js';
import { notificationRoutes } from './modules/notifications/notification.routes.js';
import { uploadsRoutes } from './modules/uploads/uploads.routes.js';
import { adminRoutes } from './modules/admin/admin.routes.js';
import { adminDashboardRoutes } from './modules/admin/admin-dashboard.routes.js';
import { adminSettingsRoutes } from './modules/admin/admin-settings.routes.js';
import { adminUsersExtRoutes } from './modules/admin/admin-users-ext.routes.js';
import { adminGamesExtRoutes } from './modules/admin/admin-games-ext.routes.js';
import { adminMatchesRoutes } from './modules/admin/admin-matches.routes.js';
import { adminProfilesRoutes } from './modules/admin/admin-profiles.routes.js';
import { adminRankingsRoutes } from './modules/admin/admin-rankings.routes.js';
import { adminPinsExtRoutes } from './modules/admin/admin-pins-ext.routes.js';
import { adminPostsRoutes } from './modules/admin/admin-posts.routes.js';
import { adminReportsExtRoutes } from './modules/admin/admin-reports-ext.routes.js';
import { adminNotificationsRoutes } from './modules/admin/admin-notifications.routes.js';
import { adminTeamsRoutes } from './modules/admin/admin-teams.routes.js';
import { teamsRoutes } from './modules/teams/teams.routes.js';
import { reportsRoutes } from './modules/reports/reports.routes.js';
import { versionRoutes } from './modules/version/version.routes.js';
import { noticesRoutes } from './modules/notices/notices.routes.js';
import { disputesRoutes } from './modules/disputes/disputes.routes.js';
import { errorLogRoutes } from './modules/error-logs/error-log.routes.js';
import { adminErrorLogsRoutes } from './modules/admin/admin-error-logs.routes.js';
import { adminAnalyticsRoutes } from './modules/admin/admin-analytics.routes.js';

export async function createApp(): Promise<FastifyInstance> {
  const fastify = Fastify({
    logger: {
      level: env.NODE_ENV === 'production' ? 'info' : 'debug',
      transport:
        env.NODE_ENV !== 'production'
          ? {
              target: 'pino-pretty',
              options: { colorize: true, translateTime: 'SYS:standard' },
            }
          : undefined,
      serializers: {
        req(req) {
          return {
            method: req.method,
            url: req.url,
            ip: req.ip,
            userId: (req as any).userId ?? '-',
          };
        },
        res(res) {
          return { statusCode: res.statusCode };
        },
      },
    },
    trustProxy: true,
    ajv: {
      customOptions: {
        removeAdditional: false,
        coerceTypes: true,
        allErrors: true,
      },
    },
    requestIdHeader: 'x-request-id',
    genReqId: () => crypto.randomUUID(),
  });

  // ─────────────────────────────────────
  // 보안 플러그인
  // ─────────────────────────────────────

  await fastify.register(fastifyFormbody); // KCP 콜백 등 x-www-form-urlencoded 파싱
  await fastify.register(fastifyHelmet, {
    contentSecurityPolicy: false,
  });

  await fastify.register(fastifyCors, {
    origin: env.CORS_ORIGIN.split(',').map((o) => o.trim()),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
    exposedHeaders: ['X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-RateLimit-Reset', 'ETag'],
  });

  // ─────────────────────────────────────
  // ETag (GET 응답 자동 ETag + 304 Not Modified)
  // ─────────────────────────────────────

  await fastify.register(fastifyEtag);

  // ─────────────────────────────────────
  // Rate Limit
  // ─────────────────────────────────────

  await registerRateLimit(fastify);

  // ─────────────────────────────────────
  // Swagger 문서 (개발 환경)
  // ─────────────────────────────────────

  if (env.NODE_ENV !== 'production') {
    await fastify.register(fastifySwagger, {
      openapi: {
        info: {
          title: 'PINDOR API',
          description: '위치 기반 스포츠 매칭 플랫폼 PINDOR API',
          version: '1.0.0',
        },
        components: {
          securitySchemes: {
            bearerAuth: {
              type: 'http',
              scheme: 'bearer',
              bearerFormat: 'JWT',
            },
          },
        },
        tags: [
          { name: 'Auth', description: '인증 API' },
          { name: 'Users', description: '사용자 API' },
          { name: 'Sports Profiles', description: '스포츠 프로필 API' },
          { name: 'Matching', description: '매칭 API' },
          { name: 'Games', description: '경기 결과 API' },
          { name: 'Chat', description: '채팅 API' },
          { name: 'Rankings', description: '랭킹 API' },
          { name: 'Pins', description: '핀/게시판 API' },
          { name: 'Notifications', description: '알림 API' },
          { name: 'Uploads', description: '파일 업로드 API' },
          { name: 'Admin', description: '어드민 API' },
          { name: 'Teams', description: '팀 관리 API' },
          { name: 'TeamMatches', description: '팀 매칭 API' },
          { name: 'TeamChat', description: '팀 채팅 API' },
          { name: 'TeamPosts', description: '팀 게시판 API' },
          { name: 'Reports', description: '신고 API' },
          { name: 'Inquiries', description: '문의 API' },
        ],
      },
    });

    await fastify.register(fastifySwaggerUi, {
      routePrefix: '/docs',
      uiConfig: { docExpansion: 'list', deepLinking: false },
    });
  }

  // ─────────────────────────────────────
  // 인증 플러그인
  // ─────────────────────────────────────

  await fastify.register(authPlugin);

  // ─────────────────────────────────────
  // 요청 로깅 훅 (유저ID + 경로 + 응답시간 + 상태코드)
  // ─────────────────────────────────────

  fastify.addHook('onRequest', async (request) => {
    // auth 미들웨어 이후 userId가 설정됨 — 여기서는 시작 시간만 기록
    (request as any)._startTime = Date.now();
  });

  fastify.addHook('onResponse', async (request, reply) => {
    const ms = Date.now() - ((request as any)._startTime || Date.now());
    const userId = (request as any).userId ?? '-';
    const status = reply.statusCode;
    const method = request.method;
    const url = request.url;

    // 한 줄 요약 로그 (디버깅에 최적)
    const level = status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info';
    request.log[level](
      `${method} ${url} ${status} ${ms}ms | user:${userId}`
    );
  });

  // ─────────────────────────────────────
  // 글로벌 에러 핸들러
  // ─────────────────────────────────────

  fastify.setErrorHandler((error, _request, reply) => {
    // ZodError (유효성 검증 실패)
    if (error instanceof ZodError) {
      return reply.status(400).send({
        success: false,
        error: {
          code: ErrorCode.VALIDATION_ERROR,
          message: '입력값이 올바르지 않습니다.',
          details: error.errors.map((e) => ({
            field: e.path.join('.'),
            message: e.message,
          })),
        },
      });
    }

    // AppError
    if (error instanceof AppError) {
      return reply.status(error.statusCode).send(error.toJSON());
    }

    // Fastify 유효성 에러
    if (error.validation) {
      return reply.status(400).send({
        success: false,
        error: {
          code: ErrorCode.VALIDATION_ERROR,
          message: '입력값이 올바르지 않습니다.',
          details: error.validation,
        },
      });
    }

    // Rate Limit 에러
    if (error.statusCode === 429) {
      return reply.status(429).send({
        success: false,
        error: {
          code: ErrorCode.RATE_LIMIT_EXCEEDED,
          message: '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
        },
      });
    }

    // 서버 에러
    const userId = (_request as any).userId ?? '-';
    fastify.log.error(
      { err: error, userId, method: _request.method, url: _request.url },
      `500 Internal Error | user:${userId} ${_request.method} ${_request.url}`
    );
    return reply.status(500).send({
      success: false,
      error: {
        code: ErrorCode.INTERNAL_SERVER_ERROR,
        message:
          env.NODE_ENV === 'production'
            ? '서버 오류가 발생했습니다.'
            : error.message,
      },
    });
  });

  // 404 핸들러
  fastify.setNotFoundHandler((_request, reply) => {
    return reply.status(404).send({
      success: false,
      error: {
        code: ErrorCode.NOT_FOUND,
        message: '요청한 리소스를 찾을 수 없습니다.',
      },
    });
  });

  // ─────────────────────────────────────
  // 라우트 등록 (모두 /v1 prefix)
  // ─────────────────────────────────────

  const V1_PREFIX = '/v1';

  await fastify.register(authRoutes, { prefix: V1_PREFIX });
  await fastify.register(kcpRoutes, { prefix: V1_PREFIX });
  await fastify.register(usersRoutes, { prefix: V1_PREFIX });
  await fastify.register(blocksRoutes, { prefix: V1_PREFIX });
  await fastify.register(profilesRoutes, { prefix: V1_PREFIX });
  await fastify.register(matchingRoutes, { prefix: V1_PREFIX });
  await fastify.register(gamesRoutes, { prefix: V1_PREFIX });
  await fastify.register(chatRoutes, { prefix: V1_PREFIX });
  await fastify.register(rankingRoutes, { prefix: V1_PREFIX });
  await fastify.register(pinsRoutes, { prefix: V1_PREFIX });
  await fastify.register(notificationRoutes, { prefix: V1_PREFIX });
  await fastify.register(uploadsRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminDashboardRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminSettingsRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminUsersExtRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminGamesExtRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminMatchesRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminProfilesRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminRankingsRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminPinsExtRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminPostsRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminReportsExtRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminNotificationsRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminTeamsRoutes, { prefix: V1_PREFIX });
  await fastify.register(teamsRoutes, { prefix: V1_PREFIX });
  await fastify.register(reportsRoutes, { prefix: V1_PREFIX });
  await fastify.register(versionRoutes, { prefix: V1_PREFIX });
  await fastify.register(noticesRoutes, { prefix: V1_PREFIX });
  await fastify.register(disputesRoutes, { prefix: V1_PREFIX });
  await fastify.register(errorLogRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminErrorLogsRoutes, { prefix: V1_PREFIX });
  await fastify.register(adminAnalyticsRoutes, { prefix: V1_PREFIX });

  // ─────────────────────────────────────
  // 헬스체크 엔드포인트
  // ─────────────────────────────────────

  fastify.get('/health', async (_request, reply) => {
    return reply.send({
      status: 'ok',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      environment: env.NODE_ENV,
    });
  });

  fastify.get('/v1/health', async (_request, reply) => {
    return reply.send({ status: 'ok' });
  });

  return fastify;
}
