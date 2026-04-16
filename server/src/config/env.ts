import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  // 서버
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(3000),
  WS_PORT: z.coerce.number().default(3001),
  API_BASE_URL: z.string().url().default('http://localhost:3000/v1'),

  // 데이터베이스
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),

  // Redis
  REDIS_URL: z.string().min(1, 'REDIS_URL is required'),

  // JWT
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_ACCESS_EXPIRES_IN: z.string().default('7d'),
  JWT_REFRESH_EXPIRES_IN: z.string().default('30d'),

  // 카카오 OAuth (로컬 개발 시 빈 값 허용)
  KAKAO_REST_API_KEY: z.string().default('dev-kakao-key-placeholder'),
  KAKAO_CLIENT_SECRET: z.string().optional(),

  // AWS S3 (로컬 개발 시 빈 값 허용 — 업로드 기능만 비활성)
  AWS_REGION: z.string().default('ap-northeast-2'),
  AWS_ACCESS_KEY_ID: z.string().default(''),
  AWS_SECRET_ACCESS_KEY: z.string().default(''),
  AWS_S3_BUCKET: z.string().default('sportsmatch-uploads-dev'),
  AWS_CLOUDFRONT_DOMAIN: z.string().optional(),

  // Firebase (로컬 개발 시 빈 값 허용 — 푸시만 비활성)
  FIREBASE_SERVICE_ACCOUNT: z.string().default(''),

  // 어드민
  ADMIN_SECRET_KEY: z.string().default('dev-admin-secret-key-32chars-min'),

  // CORS
  CORS_ORIGIN: z.string().default('*'),

  // Rate Limit
  RATE_LIMIT_MAX: z.coerce.number().default(100),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60000),
});

export type EnvConfig = z.infer<typeof envSchema>;

function validateEnv(): EnvConfig {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    const errors = result.error.errors
      .map((e) => `  ${e.path.join('.')}: ${e.message}`)
      .join('\n');
    throw new Error(`Environment validation failed:\n${errors}`);
  }

  return result.data;
}

export const env = validateEnv();
