/**
 * 테스트용 가짜 유저 100명 생성 스크립트
 * 실행: npx tsx tests/seed-test-users.ts
 */

import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { SignJWT } from 'jose';
import { writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const prisma = new PrismaClient();

// ─────────────────────────────────────
// 컬러 출력 헬퍼
// ─────────────────────────────────────

const c = {
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  red:   (s: string) => `\x1b[31m${s}\x1b[0m`,
  blue:  (s: string) => `\x1b[34m${s}\x1b[0m`,
  yellow:(s: string) => `\x1b[33m${s}\x1b[0m`,
  bold:  (s: string) => `\x1b[1m${s}\x1b[0m`,
};

// ─────────────────────────────────────
// JWT 토큰 생성 (jwt.ts 동일 방식)
// ─────────────────────────────────────

async function signTestAccessToken(userId: string, email: string): Promise<string> {
  const secret = new TextEncoder().encode(process.env.JWT_SECRET!);
  // 테스트 토큰은 30일 유효
  const expiresIn = 30 * 24 * 3600;

  return new SignJWT({ userId, email, type: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(Math.floor(Date.now() / 1000) + expiresIn)
    .setIssuer('sportsmatch')
    .sign(secret);
}

// ─────────────────────────────────────
// 티어 계산 (점수 기준)
// ─────────────────────────────────────

function calcTier(score: number): 'BRONZE' | 'SILVER' | 'GOLD' | 'PLATINUM' {
  if (score >= 1650) return 'PLATINUM';
  if (score >= 1350) return 'GOLD';
  if (score >= 1100) return 'SILVER';
  return 'BRONZE';
}

// ─────────────────────────────────────
// 랜덤 유틸
// ─────────────────────────────────────

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randFloat(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

// 나이로 birthDate 계산 (만 나이 기준)
function ageToBirthDate(age: number): Date {
  const now = new Date();
  const birthYear = now.getFullYear() - age;
  // 생일을 7월 1일 기준으로 설정 (만 나이가 정확히 age가 되도록)
  return new Date(`${birthYear}-07-01`);
}

// ─────────────────────────────────────
// 기존 테스트 유저 정리
// ─────────────────────────────────────

async function cleanupExistingTestUsers(): Promise<void> {
  console.log(c.blue('[INFO] 기존 테스트 유저 정리 중...'));

  // test_user_ 패턴의 유저 조회
  const existingUsers = await prisma.user.findMany({
    where: {
      nickname: { startsWith: 'test_user_' },
    },
    select: { id: true, nickname: true },
  });

  if (existingUsers.length > 0) {
    const userIds = existingUsers.map(u => u.id);

    // 연관 데이터 삭제 (cascade 미적용 항목 수동 삭제)
    await prisma.matchRequest.deleteMany({
      where: { requesterId: { in: userIds } },
    });

    await prisma.user.deleteMany({
      where: { id: { in: userIds } },
    });

    console.log(c.yellow(`[INFO] 기존 테스트 유저 ${existingUsers.length}명 삭제 완료`));
  } else {
    console.log(c.blue('[INFO] 기존 테스트 유저 없음'));
  }
}

// ─────────────────────────────────────
// 유저 생성 메인 로직
// ─────────────────────────────────────

export interface TestUser {
  id: string;
  email: string;
  nickname: string;
  gender: 'MALE' | 'FEMALE';
  age: number;
  score: number;
  tier: 'BRONZE' | 'SILVER' | 'GOLD' | 'PLATINUM';
  sportsProfileId: string;
  token: string;
}

async function seedTestUsers(): Promise<TestUser[]> {
  console.log(c.bold(c.blue('\n=========================================')));
  console.log(c.bold(c.blue('   테스트 유저 시드 스크립트 시작')));
  console.log(c.bold(c.blue('=========================================\n')));

  if (!process.env.JWT_SECRET) {
    console.error(c.red('[ERROR] JWT_SECRET 환경변수가 설정되지 않았습니다.'));
    process.exit(1);
  }

  // 기존 테스트 유저 정리
  await cleanupExistingTestUsers();

  console.log(c.blue('[INFO] 100명의 테스트 유저 생성 시작...'));

  const testUsers: TestUser[] = [];

  // 강남구 역삼동 중심 좌표 (37.5009, 127.0363)
  const BASE_LAT = 37.5009;
  const BASE_LNG = 127.0363;
  const COORD_RANGE = 0.05;

  for (let i = 1; i <= 100; i++) {
    const num = String(i).padStart(3, '0');
    const nickname = `test_user_${num}`;
    const email = `test_user_${num}@sportsmatch.test`;
    const gender = i <= 50 ? 'MALE' : 'FEMALE'; // 50:50
    const age = randInt(15, 55);
    const score = randInt(800, 1600);
    const tier = calcTier(score);
    const birthDate = ageToBirthDate(age);
    const lat = BASE_LAT + randFloat(-COORD_RANGE, COORD_RANGE);
    const lng = BASE_LNG + randFloat(-COORD_RANGE, COORD_RANGE);

    try {
      // 유저 생성 (트랜잭션)
      const result = await prisma.$transaction(async (tx) => {
        // 1) User 생성
        const user = await tx.user.create({
          data: {
            email,
            nickname,
            status: 'ACTIVE',
          },
        });

        // 2) SocialAccount (KAKAO 더미)
        await tx.socialAccount.create({
          data: {
            userId: user.id,
            provider: 'KAKAO',
            providerId: `test_kakao_${num}`,
          },
        });

        // 3) UserLocation (PostGIS — raw query 필요)
        await tx.$queryRaw`
          INSERT INTO user_locations (id, user_id, current_point, home_point, home_address, match_radius_km, updated_at)
          VALUES (
            gen_random_uuid(),
            ${user.id}::uuid,
            ST_GeogFromText(${`POINT(${lng} ${lat})`}),
            ST_GeogFromText(${`POINT(${lng} ${lat})`}),
            ${'서울 강남구 역삼동'},
            ${10.0},
            now()
          )
        `;

        // 4) SportsProfile (GOLF)
        const sportsProfile = await tx.sportsProfile.create({
          data: {
            userId: user.id,
            sportType: 'GOLF',
            displayName: nickname,
            initialScore: score,
            currentScore: score,
            tier,
            isActive: true,
          },
        });

        return { user, sportsProfile };
      });

      // JWT 토큰 발급
      const token = await signTestAccessToken(result.user.id, email);

      testUsers.push({
        id: result.user.id,
        email,
        nickname,
        gender,
        age,
        score,
        tier,
        sportsProfileId: result.sportsProfile.id,
        token,
      });

      if (i % 10 === 0) {
        console.log(c.green(`[PASS] ${i}명 생성 완료 (최근: ${nickname}, ${gender}, ${age}세, ${score}점 ${tier})`));
      }
    } catch (err) {
      console.error(c.red(`[FAIL] ${nickname} 생성 실패:`), err);
      throw err;
    }
  }

  // JSON 파일로 저장
  const outputPath = join(__dirname, 'test-users.json');
  writeFileSync(outputPath, JSON.stringify(testUsers, null, 2), 'utf-8');

  console.log(c.bold(c.green(`\n[DONE] 테스트 유저 ${testUsers.length}명 생성 완료`)));
  console.log(c.blue(`[INFO] 결과 저장: ${outputPath}`));

  // 통계 출력
  const males = testUsers.filter(u => u.gender === 'MALE').length;
  const females = testUsers.filter(u => u.gender === 'FEMALE').length;
  const tiers = {
    BRONZE: testUsers.filter(u => u.tier === 'BRONZE').length,
    SILVER: testUsers.filter(u => u.tier === 'SILVER').length,
    GOLD: testUsers.filter(u => u.tier === 'GOLD').length,
    PLATINUM: testUsers.filter(u => u.tier === 'PLATINUM').length,
  };
  const avgAge = Math.round(testUsers.reduce((s, u) => s + u.age, 0) / testUsers.length);
  const avgScore = Math.round(testUsers.reduce((s, u) => s + u.score, 0) / testUsers.length);

  console.log(c.bold('\n[통계]'));
  console.log(`  성별: MALE ${males}명 / FEMALE ${females}명`);
  console.log(`  평균 나이: ${avgAge}세`);
  console.log(`  평균 점수: ${avgScore}`);
  console.log(`  티어 분포: BRONZE ${tiers.BRONZE} / SILVER ${tiers.SILVER} / GOLD ${tiers.GOLD} / PLATINUM ${tiers.PLATINUM}`);

  return testUsers;
}

// ─────────────────────────────────────
// 엔트리 포인트
// ─────────────────────────────────────

async function main() {
  try {
    await seedTestUsers();
  } catch (err) {
    console.error(c.red('[ERROR] 시드 실패:'), err);
    process.exit(1);
  } finally {
    await prisma.$disconnect();
  }
}

main();
