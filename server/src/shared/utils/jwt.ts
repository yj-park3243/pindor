import { SignJWT, jwtVerify, JWTPayload } from 'jose';
import { env } from '../../config/env.js';
import { AppError, ErrorCode } from '../errors/app-error.js';

// ─────────────────────────────────────
// 타입 정의
// ─────────────────────────────────────

export interface TokenPayload {
  userId: string;
  email?: string | null;
}

export interface AccessTokenPayload extends TokenPayload, JWTPayload {
  type: 'access';
}

export interface RefreshTokenPayload extends TokenPayload, JWTPayload {
  type: 'refresh';
}

// ─────────────────────────────────────
// 비밀 키 인코딩
// ─────────────────────────────────────

function getSecretKey(): Uint8Array {
  return new TextEncoder().encode(env.JWT_SECRET);
}

// ─────────────────────────────────────
// 만료 시간 파싱 헬퍼
// ─────────────────────────────────────

function parseExpiry(expiry: string): number {
  const unit = expiry.slice(-1);
  const value = parseInt(expiry.slice(0, -1), 10);

  switch (unit) {
    case 's': return value;
    case 'm': return value * 60;
    case 'h': return value * 3600;
    case 'd': return value * 86400;
    default:  return parseInt(expiry, 10);
  }
}

// ─────────────────────────────────────
// 토큰 발급
// ─────────────────────────────────────

export async function signAccessToken(payload: TokenPayload): Promise<string> {
  const secret = getSecretKey();
  const expiresIn = parseExpiry(env.JWT_ACCESS_EXPIRES_IN);

  return new SignJWT({ ...payload, type: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(Math.floor(Date.now() / 1000) + expiresIn)
    .setIssuer('sportsmatch')
    .sign(secret);
}

export async function signRefreshToken(payload: TokenPayload): Promise<string> {
  const secret = getSecretKey();
  const expiresIn = parseExpiry(env.JWT_REFRESH_EXPIRES_IN);

  return new SignJWT({ ...payload, type: 'refresh' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(Math.floor(Date.now() / 1000) + expiresIn)
    .setIssuer('sportsmatch')
    .sign(secret);
}

// ─────────────────────────────────────
// 토큰 검증
// ─────────────────────────────────────

export async function verifyAccessToken(token: string): Promise<AccessTokenPayload> {
  try {
    const secret = getSecretKey();
    const { payload } = await jwtVerify(token, secret, {
      issuer: 'sportsmatch',
    });

    if (payload['type'] !== 'access') {
      throw new AppError(ErrorCode.AUTH_INVALID_TOKEN, 401);
    }

    return payload as AccessTokenPayload;
  } catch (err) {
    if (err instanceof AppError) throw err;

    const error = err as Error;
    if (error.name === 'JWTExpired') {
      throw new AppError(ErrorCode.AUTH_EXPIRED_TOKEN, 401);
    }
    throw new AppError(ErrorCode.AUTH_INVALID_TOKEN, 401);
  }
}

export async function verifyRefreshToken(token: string): Promise<RefreshTokenPayload> {
  try {
    const secret = getSecretKey();
    const { payload } = await jwtVerify(token, secret, {
      issuer: 'sportsmatch',
    });

    if (payload['type'] !== 'refresh') {
      throw new AppError(ErrorCode.AUTH_REFRESH_INVALID, 401);
    }

    return payload as RefreshTokenPayload;
  } catch (err) {
    if (err instanceof AppError) throw err;

    const error = err as Error;
    if (error.name === 'JWTExpired') {
      throw new AppError(ErrorCode.AUTH_EXPIRED_TOKEN, 401);
    }
    throw new AppError(ErrorCode.AUTH_REFRESH_INVALID, 401);
  }
}

// ─────────────────────────────────────
// 토큰 쌍 발급
// ─────────────────────────────────────

export async function issueTokenPair(payload: TokenPayload): Promise<{
  accessToken: string;
  refreshToken: string;
}> {
  const [accessToken, refreshToken] = await Promise.all([
    signAccessToken(payload),
    signRefreshToken(payload),
  ]);
  return { accessToken, refreshToken };
}
