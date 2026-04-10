import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { env } from './env.js';

// DATABASE_URL 파싱 (TypeORM은 ?schema= 파라미터 미지원, 특수문자 이슈 방지)
function parseDbUrl(url: string) {
  const cleaned = url.replace(/\?.*$/, ''); // 쿼리 파라미터 제거
  const match = cleaned.match(/^postgresql:\/\/([^:]+):(.+)@([^:]+):(\d+)\/(.+)$/);
  if (!match) return { url: cleaned };
  return {
    host: match[3],
    port: parseInt(match[4]),
    username: match[1],
    password: match[2],
    database: match[5],
  };
}

const dbConfig = parseDbUrl(env.DATABASE_URL);

export const AppDataSource = new DataSource({
  type: 'postgres',
  ...dbConfig,
  schema: 'public',
  synchronize: true,
  logging: env.NODE_ENV === 'development' ? ['query', 'error'] : ['error'],
  entities: ['src/entities/**/*.ts'],
  subscribers: [],
  migrations: [],
  ssl: env.DATABASE_URL.includes('rds.amazonaws.com') ? { rejectUnauthorized: false } : false,
});

// 기존 코드와의 호환을 위한 export
export const db = AppDataSource;
