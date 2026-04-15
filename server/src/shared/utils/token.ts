import { redis } from '../../config/redis.js';
import { REFRESH_TOKEN_TTL } from '../constants.js';

export async function storeRefreshToken(userId: string, refreshToken: string): Promise<void> {
  await redis.setex(`refresh_token:${userId}`, REFRESH_TOKEN_TTL, refreshToken);
}
