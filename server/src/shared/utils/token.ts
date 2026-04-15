import { redis } from '../../config/redis.js';

const REFRESH_TOKEN_TTL = 30 * 24 * 3600; // 30일

export async function storeRefreshToken(userId: string, refreshToken: string): Promise<void> {
  await redis.setex(`refresh_token:${userId}`, REFRESH_TOKEN_TTL, refreshToken);
}
