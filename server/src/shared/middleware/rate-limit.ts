import { FastifyInstance } from 'fastify';
import fastifyRateLimit from '@fastify/rate-limit';
import { redis } from '../../config/redis.js';
import { env } from '../../config/env.js';

export async function registerRateLimit(fastify: FastifyInstance): Promise<void> {
  await fastify.register(fastifyRateLimit, {
    global: true,
    max: env.RATE_LIMIT_MAX,
    timeWindow: env.RATE_LIMIT_WINDOW_MS,
    redis,
    keyGenerator(request) {
      // 인증된 사용자는 userId 기반, 미인증은 IP 기반
      const userId = (request as any).user?.userId;
      return userId ? `ratelimit:user:${userId}` : `ratelimit:ip:${request.ip}`;
    },
    errorResponseBuilder(_request, context) {
      return {
        success: false,
        error: {
          code: 'COMMON_004',
          message: `요청이 너무 많습니다. ${Math.ceil(context.ttl / 1000)}초 후 다시 시도해 주세요.`,
          details: {
            limit: context.max,
            remaining: 0,
            resetIn: context.ttl,
          },
        },
      };
    },
    // 특정 경로는 더 엄격한 제한
    addHeaders: {
      'x-ratelimit-limit': true,
      'x-ratelimit-remaining': true,
      'x-ratelimit-reset': true,
      'retry-after': true,
    },
  });
}

/**
 * 인증 엔드포인트 전용 엄격한 레이트 리밋 설정
 */
export const authRateLimitConfig = {
  config: {
    rateLimit: {
      max: 10,
      timeWindow: 60000, // 1분에 10회
    },
  },
};

/**
 * 업로드 엔드포인트 전용 레이트 리밋
 */
export const uploadRateLimitConfig = {
  config: {
    rateLimit: {
      max: 20,
      timeWindow: 60000, // 1분에 20회
    },
  },
};

/**
 * 좋아요 토글 전용 레이트 리밋 (스팸 방지)
 */
export const likeRateLimitConfig = {
  config: {
    rateLimit: {
      max: 30,
      timeWindow: 60000, // 1분에 30회
    },
  },
};
