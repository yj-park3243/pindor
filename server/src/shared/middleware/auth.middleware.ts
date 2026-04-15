import { FastifyRequest, FastifyReply, FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';
import { verifyAccessToken } from '../utils/jwt.js';
import { AppError, ErrorCode } from '../errors/app-error.js';
import { AppDataSource } from '../../config/database.js';
import { User, AdminAccount } from '../../entities/index.js';

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
  } catch {
    // 토큰이 유효하지 않아도 요청 계속 진행
  }
}
