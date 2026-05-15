import { FastifyRequest, FastifyReply, FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';
import { verifyAccessToken } from '../utils/jwt.js';
import { AppError, ErrorCode } from '../errors/app-error.js';
import { AppDataSource } from '../../config/database.js';
import { redis } from '../../config/redis.js';
import { User, AdminAccount } from '../../entities/index.js';

// X-Platform 헤더로 받은 디바이스 플랫폼을 users.device_platform에 반영.
// - redis 캐시(TTL 1일) 일치 시 skip → 매 요청 UPDATE 회피
// - DB 실패해도 본 요청 흐름에는 영향 없도록 fire-and-forget
async function syncDevicePlatform(userId: string, request: FastifyRequest): Promise<void> {
  try {
    const raw = request.headers['x-platform'];
    const headerVal = Array.isArray(raw) ? raw[0] : raw;
    if (!headerVal) return;
    const platform = headerVal.toString().toUpperCase();
    if (platform !== 'IOS' && platform !== 'ANDROID') return;

    const cacheKey = `device_platform:${userId}`;
    const cached = await redis.get(cacheKey);
    if (cached === platform) return;

    await AppDataSource.getRepository(User).update({ id: userId }, { devicePlatform: platform });
    await redis.set(cacheKey, platform, 'EX', 86400);
  } catch (e) {
    console.warn('[Auth] syncDevicePlatform failed:', (e as Error).message);
  }
}

// ─────────────────────────────────────
// JWT 검증 플러그인
// ─────────────────────────────────────

async function authPlugin(fastify: FastifyInstance): Promise<void> {
  fastify.decorate(
    'authenticate',
    async (request: FastifyRequest, reply: FastifyReply) => {
      try {
        const authHeader = request.headers.authorization;

        if (!authHeader || !authHeader.startsWith('Bearer ')) {
          throw new AppError(ErrorCode.AUTH_MISSING_TOKEN, 401);
        }

        const token = authHeader.slice(7);
        const payload = await verifyAccessToken(token);

        // 먼저 AdminAccount 테이블에서 확인 (어드민 토큰인 경우)
        const adminAccountRepo = AppDataSource.getRepository(AdminAccount);
        const adminAccount = await adminAccountRepo.findOne({
          where: { id: payload.userId },
          select: { id: true, username: true, isActive: true },
        });

        if (adminAccount) {
          if (!adminAccount.isActive) {
            throw new AppError(ErrorCode.USER_SUSPENDED, 403);
          }
          request.user = {
            userId: adminAccount.id,
            email: adminAccount.username,
          };
          return;
        }

        // AdminAccount에 없으면 일반 User 테이블에서 확인
        const userRepo = AppDataSource.getRepository(User);
        const user = await userRepo.findOne({
          where: { id: payload.userId },
          select: { id: true, email: true, status: true },
        });

        if (!user) {
          throw new AppError(ErrorCode.USER_NOT_FOUND, 401);
        }

        if (user.status === 'SUSPENDED') {
          throw new AppError(ErrorCode.USER_SUSPENDED, 403);
        }

        if (user.status === 'WITHDRAWN') {
          throw new AppError(ErrorCode.USER_WITHDRAWN, 403);
        }

        request.user = {
          userId: user.id,
          email: user.email,
        };

        // 디바이스 플랫폼 비동기 동기화 (응답 흐름 차단 X)
        void syncDevicePlatform(user.id, request);
      } catch (err) {
        if (err instanceof AppError) {
          return reply.status(err.statusCode).send(err.toJSON());
        }
        return reply
          .status(401)
          .send(new AppError(ErrorCode.AUTH_INVALID_TOKEN, 401).toJSON());
      }
    },
  );
}

export default fp(authPlugin, {
  name: 'auth-plugin',
});

// ─────────────────────────────────────
// Fastify 타입 확장
// ─────────────────────────────────────

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

// ─────────────────────────────────────
// 옵셔널 인증 (미인증도 허용)
// ─────────────────────────────────────

export async function optionalAuth(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  try {
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) return;

    const token = authHeader.slice(7);
    const payload = await verifyAccessToken(token);

    request.user = {
      userId: payload.userId,
      email: payload.email,
    };
    void syncDevicePlatform(payload.userId, request);
  } catch {
    // 토큰이 유효하지 않아도 요청 계속 진행
  }
}
