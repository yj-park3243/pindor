import Redis from 'ioredis';
import { env } from './env.js';

let redisInstance: Redis | null = null;
let bullmqRedisInstance: Redis | null = null;

/**
 * 일반용 Redis 연결 (캐시, 세션, 랭킹 등)
 */
export function getRedis(): Redis {
  if (!redisInstance) {
    redisInstance = new Redis(env.REDIS_URL, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
      retryStrategy(times) {
        if (times > 10) {
          console.error('[Redis] Max retry attempts reached, giving up');
          return null;
        }
        const delay = Math.min(times * 100, 2000);
        console.warn(`[Redis] Retrying connection in ${delay}ms (attempt ${times})`);
        return delay;
      },
    });

    redisInstance.on('connect', () => {
      console.info('[Redis] Connected');
    });

    redisInstance.on('error', (err) => {
      console.error('[Redis] Connection error:', err.message);
    });
  }

  return redisInstance;
}

/**
 * BullMQ 전용 Redis 연결 (maxRetriesPerRequest: null 필수)
 */
export function getBullMQRedis(): Redis {
  if (!bullmqRedisInstance) {
    bullmqRedisInstance = new Redis(env.REDIS_URL, {
      maxRetriesPerRequest: null,
      enableReadyCheck: false,
      retryStrategy(times) {
        if (times > 10) return null;
        return Math.min(times * 100, 2000);
      },
    });
  }
  return bullmqRedisInstance;
}

export async function closeRedis(): Promise<void> {
  if (redisInstance) {
    await redisInstance.quit();
    redisInstance = null;
  }
  if (bullmqRedisInstance) {
    await bullmqRedisInstance.quit();
    bullmqRedisInstance = null;
  }
  console.info('[Redis] Connections closed');
}

export const redis = getRedis();
export const bullmqRedis = getBullMQRedis();
