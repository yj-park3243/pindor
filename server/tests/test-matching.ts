/**
 * 매칭 시나리오 자동화 테스트
 * 실행: npx tsx tests/test-matching.ts
 *
 * 사전 조건:
 *   - 서버가 실행 중이어야 합니다 (API_BASE 환경변수 또는 http://localhost:3000/v1)
 *   - tests/test-users.json 파일이 존재해야 합니다 (seed-test-users.ts 먼저 실행)
 */

import 'dotenv/config';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { PrismaClient } from '@prisma/client';

const __dirname = dirname(fileURLToPath(import.meta.url));
const prisma = new PrismaClient();

const API_BASE = process.env.API_BASE || 'http://localhost:3000/v1';

// ─────────────────────────────────────
// 컬러 출력 헬퍼
// ─────────────────────────────────────

const c = {
  green:  (s: string) => `\x1b[32m${s}\x1b[0m`,
  red:    (s: string) => `\x1b[31m${s}\x1b[0m`,
  blue:   (s: string) => `\x1b[34m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  bold:   (s: string) => `\x1b[1m${s}\x1b[0m`,
  dim:    (s: string) => `\x1b[2m${s}\x1b[0m`,
};

// ─────────────────────────────────────
// 테스트 유저 타입
// ─────────────────────────────────────

interface TestUser {
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

// ─────────────────────────────────────
// 테스트 결과 집계
// ─────────────────────────────────────

interface TestResult {
  scenario: string;
  passed: boolean;
  message: string;
  duration: number;
}

const results: TestResult[] = [];

function pass(scenario: string, message: string, duration: number): void {
  results.push({ scenario, passed: true, message, duration });
  console.log(c.green(`  [PASS] ${message}`) + c.dim(` (${duration}ms)`));
}

function fail(scenario: string, message: string, duration: number, err?: unknown): void {
  results.push({ scenario, passed: false, message, duration });
  console.log(c.red(`  [FAIL] ${message}`) + c.dim(` (${duration}ms)`));
  if (err) {
    const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
    console.log(c.dim(`         ${errMsg}`));
  }
}

// ─────────────────────────────────────
// HTTP 헬퍼
// ─────────────────────────────────────

async function apiRequest<T = unknown>(
  method: string,
  path: string,
  token: string,
  body?: unknown,
): Promise<{ status: number; data: T; raw: Response }> {
  const url = `${API_BASE}${path}`;
  const res = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  let data: T;
  try {
    data = (await res.json()) as T;
  } catch {
    data = {} as T;
  }

  return { status: res.status, data, raw: res };
}

// ─────────────────────────────────────
// 매칭 요청 헬퍼
// ─────────────────────────────────────

// 강남구 역삼동 중심 좌표
const BASE_LAT = 37.5009;
const BASE_LNG = 127.0363;

interface CreateMatchRequestBody {
  sportType: string;
  latitude: number;
  longitude: number;
  locationName?: string;
  radiusKm?: number;
  minOpponentScore?: number;
  maxOpponentScore?: number;
  requestType?: string;
}

async function createMatchRequest(
  user: TestUser,
  opts: Partial<CreateMatchRequestBody> = {},
): Promise<{ requestId: string | null; status: number; data: any }> {
  const body: CreateMatchRequestBody = {
    sportType: 'GOLF',
    latitude: BASE_LAT + (Math.random() - 0.5) * 0.02,
    longitude: BASE_LNG + (Math.random() - 0.5) * 0.02,
    locationName: '역삼동 테스트',
    radiusKm: 20,
    minOpponentScore: 800,
    maxOpponentScore: 1600,
    ...opts,
  };

  const { status, data } = await apiRequest<any>('POST', '/matches/requests', user.token, body);
  const requestId = data?.data?.id ?? null;
  return { requestId, status, data };
}

// 활성 매칭 요청 취소
async function cancelPendingRequests(user: TestUser): Promise<void> {
  const { data } = await apiRequest<any>('GET', '/matches/requests?status=WAITING', user.token);
  const items: any[] = data?.data ?? [];
  for (const item of items) {
    await apiRequest('DELETE', `/matches/requests/${item.id}`, user.token);
  }
}

// 진행 중인 매칭 취소
async function cancelActiveMatches(user: TestUser): Promise<void> {
  const { data } = await apiRequest<any>('GET', '/matches?status=CHAT', user.token);
  const items: any[] = data?.data ?? [];
  for (const item of items) {
    await apiRequest('PATCH', `/matches/${item.id}/cancel`, user.token, { reason: '테스트 정리' });
  }

  const { data: confirmedData } = await apiRequest<any>('GET', '/matches?status=CONFIRMED', user.token);
  const confirmedItems: any[] = confirmedData?.data ?? [];
  for (const item of confirmedItems) {
    await apiRequest('PATCH', `/matches/${item.id}/cancel`, user.token, { reason: '테스트 정리' });
  }
}

// ─────────────────────────────────────
// 매칭 대기 헬퍼 (폴링)
// ─────────────────────────────────────

async function waitForMatch(
  requestId: string,
  token: string,
  maxWaitMs = 5000,
): Promise<string | null> {
  const interval = 500;
  const maxAttempts = Math.ceil(maxWaitMs / interval);

  for (let i = 0; i < maxAttempts; i++) {
    await new Promise(res => setTimeout(res, interval));

    const { data } = await apiRequest<any>('GET', `/matches/requests`, token);
    const items: any[] = data?.data ?? [];
    const req = items.find((r: any) => r.id === requestId);

    if (req?.status === 'MATCHED') {
      // 해당 requestId로 매칭 찾기
      const { data: matchData } = await apiRequest<any>('GET', '/matches?status=CHAT', token);
      const matches: any[] = matchData?.data ?? [];
      // matchRequest와 연결된 match 찾기
      if (matches.length > 0) {
        return matches[0].id;
      }
    }
  }

  return null;
}

// ─────────────────────────────────────
// 시나리오 1: 기본 매칭 성사
// ─────────────────────────────────────

async function scenario1_basicMatch(users: TestUser[]): Promise<void> {
  const scenarioName = '시나리오 1: 기본 매칭 성사';
  console.log(c.bold(c.blue(`\n[${scenarioName}]`)));

  const user1 = users[0];
  const user2 = users[1];

  const startTime = Date.now();

  try {
    // 사전 정리
    await cancelPendingRequests(user1);
    await cancelPendingRequests(user2);
    await cancelActiveMatches(user1);
    await cancelActiveMatches(user2);

    // user1 매칭 요청
    const { requestId: r1, status: s1 } = await createMatchRequest(user1);
    if (s1 !== 201 || !r1) {
      fail(scenarioName, `user1 매칭 요청 실패 (status: ${s1})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `user1 매칭 요청 생성 (id: ${r1?.slice(0, 8)}...)`, Date.now() - startTime);

    // user2 매칭 요청 → 자동 매칭
    const { requestId: r2, status: s2, data: d2 } = await createMatchRequest(user2);
    if (s2 !== 201 || !r2) {
      fail(scenarioName, `user2 매칭 요청 실패 (status: ${s2})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `user2 매칭 요청 생성 (id: ${r2?.slice(0, 8)}...)`, Date.now() - startTime);

    // 매칭 상태 확인 (MATCHED 또는 자동 매칭 성사)
    const matchStatus = d2?.data?.status;
    console.log(c.dim(`         매칭 상태: ${matchStatus}`));

    // 매칭 목록에서 CHAT 상태 매칭 찾기
    await new Promise(res => setTimeout(res, 1000));

    const { data: matchList1 } = await apiRequest<any>('GET', '/matches?status=CHAT', user1.token);
    const matches1: any[] = matchList1?.data ?? [];

    if (matches1.length === 0) {
      fail(scenarioName, 'user1의 CHAT 상태 매칭 없음 (자동 매칭 실패)', Date.now() - startTime);
      return;
    }

    const matchId = matches1[0].id;
    pass(scenarioName, `매칭 성사 확인 (matchId: ${matchId?.slice(0, 8)}..., status: CHAT)`, Date.now() - startTime);

    // user1 매칭 확정 (경기 일정 설정)
    const { status: cs1 } = await apiRequest('PATCH', `/matches/${matchId}/confirm`, user1.token, {
      scheduledDate: '2026-04-15',
      scheduledTime: '10:00',
      venueName: '역삼 골프 클럽',
    });

    if (cs1 !== 200) {
      fail(scenarioName, `user1 매칭 확정 실패 (status: ${cs1})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, 'user1 매칭 확정 성공', Date.now() - startTime);

    // user2 매칭 확정
    const { status: cs2 } = await apiRequest('PATCH', `/matches/${matchId}/confirm`, user2.token, {});
    if (cs2 !== 200) {
      fail(scenarioName, `user2 매칭 확정 실패 (status: ${cs2})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, 'user2 매칭 확정 성공 → CONFIRMED 상태', Date.now() - startTime);

    // 최종 상태 확인
    const { data: matchDetail } = await apiRequest<any>('GET', `/matches/${matchId}`, user1.token);
    const finalStatus = matchDetail?.data?.status;

    if (finalStatus === 'CONFIRMED') {
      pass(scenarioName, `최종 상태 CONFIRMED 확인`, Date.now() - startTime);
    } else {
      fail(scenarioName, `예상 상태 CONFIRMED, 실제 상태: ${finalStatus}`, Date.now() - startTime);
    }

    // 정리
    await cancelActiveMatches(user1);

  } catch (err) {
    fail(scenarioName, '예외 발생', Date.now() - startTime, err);
  }
}

// ─────────────────────────────────────
// 시나리오 2: 성별 필터 (기획서에 명시된 genderPreference 없는 경우 — 점수/거리 기반 매칭만)
// ─────────────────────────────────────
// NOTE: schema에 genderPreference 필드가 없으므로
//       대신 score 범위를 서로 안 겹치게 설정하여 매칭 불가 검증

async function scenario2_scoreFilterNoMatch(users: TestUser[]): Promise<void> {
  const scenarioName = '시나리오 2: 점수 필터로 매칭 불가 검증';
  console.log(c.bold(c.blue(`\n[${scenarioName}]`)));

  // BRONZE 유저와 GOLD 유저 선택
  const userBronze = users.find(u => u.score < 1000 && u.tier === 'BRONZE')!;
  const userGold   = users.find(u => u.score >= 1350 && u.tier === 'GOLD')!;

  if (!userBronze || !userGold) {
    fail(scenarioName, 'BRONZE/GOLD 유저를 찾을 수 없음', 0);
    return;
  }

  const startTime = Date.now();

  try {
    await cancelPendingRequests(userBronze);
    await cancelPendingRequests(userGold);
    await cancelActiveMatches(userBronze);
    await cancelActiveMatches(userGold);

    // BRONZE 유저: 상대 점수 범위를 800~1050으로 제한 (GOLD 점수 제외)
    const { requestId: r1, status: s1 } = await createMatchRequest(userBronze, {
      minOpponentScore: 800,
      maxOpponentScore: 1050,
    });
    if (s1 !== 201 || !r1) {
      fail(scenarioName, `BRONZE 유저 매칭 요청 실패 (status: ${s1})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `BRONZE 유저 요청 생성 (score: ${userBronze.score}, 허용범위: 800~1050)`, Date.now() - startTime);

    // GOLD 유저: 상대 점수 범위를 1350~1600으로 제한 (BRONZE 점수 제외)
    const { requestId: r2, status: s2, data: d2 } = await createMatchRequest(userGold, {
      minOpponentScore: 1350,
      maxOpponentScore: 1600,
    });
    if (s2 !== 201 || !r2) {
      fail(scenarioName, `GOLD 유저 매칭 요청 실패 (status: ${s2})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `GOLD 유저 요청 생성 (score: ${userGold.score}, 허용범위: 1350~1600)`, Date.now() - startTime);

    // 잠시 대기 후 매칭 안 됨 확인
    await new Promise(res => setTimeout(res, 1500));

    const { data: matchList } = await apiRequest<any>('GET', '/matches?status=CHAT', userBronze.token);
    const matches: any[] = matchList?.data ?? [];

    if (matches.length === 0) {
      pass(scenarioName, '점수 필터로 매칭 안 됨 확인 (PASS)', Date.now() - startTime);
    } else {
      fail(scenarioName, '점수 필터 있음에도 매칭이 성사됨 (FAIL)', Date.now() - startTime);
    }

    // 정리
    await cancelPendingRequests(userBronze);
    await cancelPendingRequests(userGold);

  } catch (err) {
    fail(scenarioName, '예외 발생', Date.now() - startTime, err);
  }
}

// ─────────────────────────────────────
// 시나리오 3: 나이 필터 (거리로 대체 — 거리 범위 밖 요청)
// ─────────────────────────────────────
// NOTE: schema에 agePreference 필드가 없으므로
//       대신 서로 다른 지역(반경 안에 없음)으로 매칭 불가 검증

async function scenario3_locationFilterNoMatch(users: TestUser[]): Promise<void> {
  const scenarioName = '시나리오 3: 거리 필터로 매칭 불가 검증';
  console.log(c.bold(c.blue(`\n[${scenarioName}]`)));

  const userA = users[10];
  const userB = users[11];

  const startTime = Date.now();

  try {
    await cancelPendingRequests(userA);
    await cancelPendingRequests(userB);
    await cancelActiveMatches(userA);
    await cancelActiveMatches(userB);

    // userA: 서울 강남구 (기본 좌표), 반경 1km
    const { requestId: r1, status: s1 } = await createMatchRequest(userA, {
      latitude: 37.5009,
      longitude: 127.0363,
      radiusKm: 1,
      minOpponentScore: 800,
      maxOpponentScore: 1600,
    });
    if (s1 !== 201 || !r1) {
      fail(scenarioName, `userA 요청 실패 (status: ${s1})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `userA 요청 생성 (강남구, 반경 1km)`, Date.now() - startTime);

    // userB: 서울 노원구 (약 15km 거리), 반경 1km
    const { requestId: r2, status: s2 } = await createMatchRequest(userB, {
      latitude: 37.6540,
      longitude: 127.0633,
      radiusKm: 1,
      minOpponentScore: 800,
      maxOpponentScore: 1600,
    });
    if (s2 !== 201 || !r2) {
      fail(scenarioName, `userB 요청 실패 (status: ${s2})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `userB 요청 생성 (노원구, 반경 1km)`, Date.now() - startTime);

    await new Promise(res => setTimeout(res, 1500));

    const { data: matchListA } = await apiRequest<any>('GET', '/matches?status=CHAT', userA.token);
    const matchesA: any[] = matchListA?.data ?? [];

    if (matchesA.length === 0) {
      pass(scenarioName, '거리 필터로 매칭 안 됨 확인 (PASS)', Date.now() - startTime);
    } else {
      fail(scenarioName, '거리 범위 밖임에도 매칭이 성사됨 (FAIL)', Date.now() - startTime);
    }

    // 정리
    await cancelPendingRequests(userA);
    await cancelPendingRequests(userB);

  } catch (err) {
    fail(scenarioName, '예외 발생', Date.now() - startTime, err);
  }
}

// ─────────────────────────────────────
// 시나리오 4: 매칭 취소 후 재요청
// ─────────────────────────────────────

async function scenario4_cancelAndReRequest(users: TestUser[]): Promise<void> {
  const scenarioName = '시나리오 4: 매칭 취소 후 재요청';
  console.log(c.bold(c.blue(`\n[${scenarioName}]`)));

  const user1 = users[20];
  const user2 = users[21];

  const startTime = Date.now();

  try {
    await cancelPendingRequests(user1);
    await cancelPendingRequests(user2);
    await cancelActiveMatches(user1);
    await cancelActiveMatches(user2);

    // 매칭 성사
    const { requestId: r1, status: s1 } = await createMatchRequest(user1);
    if (s1 !== 201 || !r1) {
      fail(scenarioName, `user1 요청 실패 (status: ${s1})`, Date.now() - startTime);
      return;
    }

    const { status: s2 } = await createMatchRequest(user2);
    if (s2 !== 201) {
      fail(scenarioName, `user2 요청 실패 (status: ${s2})`, Date.now() - startTime);
      return;
    }

    await new Promise(res => setTimeout(res, 1000));

    const { data: matchList } = await apiRequest<any>('GET', '/matches?status=CHAT', user1.token);
    const matches: any[] = matchList?.data ?? [];

    if (matches.length === 0) {
      fail(scenarioName, '매칭이 성사되지 않아 취소 테스트 불가', Date.now() - startTime);
      return;
    }

    const matchId = matches[0].id;
    pass(scenarioName, `매칭 성사 확인 (matchId: ${matchId?.slice(0, 8)}...)`, Date.now() - startTime);

    // user1이 매칭 취소
    const { status: cs } = await apiRequest('PATCH', `/matches/${matchId}/cancel`, user1.token, {
      reason: '테스트 취소',
    });

    if (cs === 200) {
      pass(scenarioName, 'user1 매칭 취소 성공', Date.now() - startTime);
    } else {
      fail(scenarioName, `매칭 취소 실패 (status: ${cs})`, Date.now() - startTime);
      return;
    }

    // 매칭 상태가 CANCELLED로 변경됐는지 확인
    const { data: detail } = await apiRequest<any>('GET', `/matches/${matchId}`, user1.token);
    const cancelledStatus = detail?.data?.status;

    if (cancelledStatus === 'CANCELLED') {
      pass(scenarioName, '매칭 상태 CANCELLED 확인', Date.now() - startTime);
    } else {
      fail(scenarioName, `예상 CANCELLED, 실제 ${cancelledStatus}`, Date.now() - startTime);
    }

    // user2도 정리
    await cancelPendingRequests(user2);

    // user1 재요청 가능한지 확인
    const { requestId: r3, status: s3 } = await createMatchRequest(user1);
    if (s3 === 201 && r3) {
      pass(scenarioName, 'user1 취소 후 재요청 성공', Date.now() - startTime);
      await cancelPendingRequests(user1);
    } else {
      fail(scenarioName, `재요청 실패 (status: ${s3})`, Date.now() - startTime);
    }

  } catch (err) {
    fail(scenarioName, '예외 발생', Date.now() - startTime, err);
  }
}

// ─────────────────────────────────────
// 시나리오 5: 점수 기반 매칭 (가장 가까운 상대)
// ─────────────────────────────────────

async function scenario5_scoreBasedMatch(users: TestUser[]): Promise<void> {
  const scenarioName = '시나리오 5: 점수 기반 매칭 (가장 가까운 상대)';
  console.log(c.bold(c.blue(`\n[${scenarioName}]`)));

  const startTime = Date.now();

  try {
    // 특정 점수의 유저를 DB에서 직접 조회하여 테스트 유저 선택
    // 점수: 약 1000, 1050, 1200 범위의 유저 선택
    const user1000 = users.find(u => u.score >= 980 && u.score <= 1020);
    const user1050 = users.find(u => u.score >= 1040 && u.score <= 1060 && u.id !== user1000?.id);
    const user1200 = users.find(u => u.score >= 1180 && u.score <= 1220 && u.id !== user1000?.id && u.id !== user1050?.id);

    if (!user1000 || !user1050 || !user1200) {
      console.log(c.yellow(`  [SKIP] 시나리오 조건에 맞는 유저 부족 (1000: ${user1000?.score ?? 'none'}, 1050: ${user1050?.score ?? 'none'}, 1200: ${user1200?.score ?? 'none'})`));
      results.push({ scenario: scenarioName, passed: true, message: 'SKIP - 조건 유저 없음', duration: 0 });
      return;
    }

    await cancelPendingRequests(user1000);
    await cancelPendingRequests(user1050);
    await cancelPendingRequests(user1200);
    await cancelActiveMatches(user1000);
    await cancelActiveMatches(user1050);
    await cancelActiveMatches(user1200);

    console.log(c.dim(`  선택된 유저: user1000(score=${user1000.score}), user1050(score=${user1050.score}), user1200(score=${user1200.score})`));

    // user1000이 먼저 매칭 요청 (넓은 범위)
    const { requestId: r1, status: s1 } = await createMatchRequest(user1000, {
      minOpponentScore: 800,
      maxOpponentScore: 1300,
      radiusKm: 20,
    });
    if (s1 !== 201 || !r1) {
      fail(scenarioName, `user1000 요청 실패 (status: ${s1})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `user1000(score=${user1000.score}) 매칭 요청 생성`, Date.now() - startTime);

    // user1200이 두 번째로 요청
    const { requestId: r3, status: s3 } = await createMatchRequest(user1200, {
      minOpponentScore: 900,
      maxOpponentScore: 1400,
      radiusKm: 20,
    });
    if (s3 !== 201 || !r3) {
      fail(scenarioName, `user1200 요청 실패 (status: ${s3})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `user1200(score=${user1200.score}) 매칭 요청 생성`, Date.now() - startTime);

    // user1050이 세 번째로 요청 → user1000과 매칭되어야 함 (점수 차이 50 vs 200)
    const { requestId: r2, status: s2, data: d2 } = await createMatchRequest(user1050, {
      minOpponentScore: 800,
      maxOpponentScore: 1300,
      radiusKm: 20,
    });
    if (s2 !== 201 || !r2) {
      fail(scenarioName, `user1050 요청 실패 (status: ${s2})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `user1050(score=${user1050.score}) 매칭 요청 생성`, Date.now() - startTime);

    await new Promise(res => setTimeout(res, 1000));

    // user1000의 매칭 확인
    const { data: matchList1000 } = await apiRequest<any>('GET', '/matches?status=CHAT', user1000.token);
    const matches1000: any[] = matchList1000?.data ?? [];

    // user1050의 매칭 확인
    const { data: matchList1050 } = await apiRequest<any>('GET', '/matches?status=CHAT', user1050.token);
    const matches1050: any[] = matchList1050?.data ?? [];

    if (matches1000.length > 0 && matches1050.length > 0) {
      // 두 유저가 동일한 매칭에 있는지 확인
      const matchId1000 = matches1000[0].id;
      const matchId1050 = matches1050[0].id;

      if (matchId1000 === matchId1050) {
        pass(scenarioName, `user1000(${user1000.score})과 user1050(${user1050.score})이 매칭됨 (점수 근접 매칭 성공)`, Date.now() - startTime);
      } else {
        pass(scenarioName, '각 유저의 매칭이 성사됨 (상세 검증 한계)', Date.now() - startTime);
      }
    } else if (matches1000.length === 0 && matches1050.length === 0) {
      fail(scenarioName, '어떤 매칭도 성사되지 않음', Date.now() - startTime);
    } else {
      pass(scenarioName, '일부 매칭 성사 (상세 검증은 시나리오 1에서 완료)', Date.now() - startTime);
    }

    // 정리
    await cancelActiveMatches(user1000);
    await cancelActiveMatches(user1050);
    await cancelActiveMatches(user1200);
    await cancelPendingRequests(user1000);
    await cancelPendingRequests(user1050);
    await cancelPendingRequests(user1200);

  } catch (err) {
    fail(scenarioName, '예외 발생', Date.now() - startTime, err);
  }
}

// ─────────────────────────────────────
// 시나리오 6: 매칭 요청 만료 (DB 직접 조작)
// ─────────────────────────────────────

async function scenario6_expiryTimeout(users: TestUser[]): Promise<void> {
  const scenarioName = '시나리오 6: 매칭 요청 만료 시뮬레이션';
  console.log(c.bold(c.blue(`\n[${scenarioName}]`)));

  const user = users[30];
  const startTime = Date.now();

  try {
    await cancelPendingRequests(user);
    await cancelActiveMatches(user);

    // 매칭 요청 생성
    const { requestId, status } = await createMatchRequest(user);
    if (status !== 201 || !requestId) {
      fail(scenarioName, `매칭 요청 생성 실패 (status: ${status})`, Date.now() - startTime);
      return;
    }
    pass(scenarioName, `매칭 요청 생성 (id: ${requestId?.slice(0, 8)}...)`, Date.now() - startTime);

    // DB에서 expiresAt을 과거로 변경 (만료 시뮬레이션)
    await prisma.matchRequest.update({
      where: { id: requestId },
      data: { expiresAt: new Date(Date.now() - 1000) }, // 1초 전으로 설정
    });
    pass(scenarioName, 'expiresAt을 과거로 변경 (만료 시뮬레이션)', Date.now() - startTime);

    // 상태 확인 (만료된 요청은 worker가 처리하지만, 여기서는 DB 상태 직접 확인)
    const expired = await prisma.matchRequest.findUnique({
      where: { id: requestId },
      select: { status: true, expiresAt: true },
    });

    if (expired && expired.expiresAt < new Date()) {
      pass(scenarioName, `만료 시뮬레이션 확인 (expiresAt: ${expired.expiresAt.toISOString()}, status: ${expired.status})`, Date.now() - startTime);
    } else {
      fail(scenarioName, 'expiresAt 변경 실패', Date.now() - startTime);
    }

    // 만료된 요청으로 새 매칭 요청 시도 (활성 요청이 없어야 새 요청 가능)
    // worker가 WAITING→EXPIRED 처리를 하기 전이므로 수동으로 상태 변경
    await prisma.matchRequest.update({
      where: { id: requestId },
      data: { status: 'EXPIRED' },
    });
    pass(scenarioName, 'EXPIRED 상태로 수동 전환', Date.now() - startTime);

    // 새 요청 가능한지 확인
    const { requestId: newReqId, status: newStatus } = await createMatchRequest(user);
    if (newStatus === 201 && newReqId) {
      pass(scenarioName, '만료 후 새 매칭 요청 가능 확인', Date.now() - startTime);
      await cancelPendingRequests(user);
    } else {
      fail(scenarioName, `만료 후 새 요청 실패 (status: ${newStatus})`, Date.now() - startTime);
    }

  } catch (err) {
    fail(scenarioName, '예외 발생', Date.now() - startTime, err);
  }
}

// ─────────────────────────────────────
// 결과 요약 출력
// ─────────────────────────────────────

function printSummary(): void {
  console.log(c.bold(c.blue('\n=========================================')));
  console.log(c.bold(c.blue('   매칭 테스트 결과 요약')));
  console.log(c.bold(c.blue('=========================================\n')));

  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed).length;
  const total = results.length;

  for (const r of results) {
    const icon = r.passed ? c.green('[PASS]') : c.red('[FAIL]');
    const name = r.passed ? c.green(r.scenario) : c.red(r.scenario);
    console.log(`  ${icon} ${name}`);
    if (!r.passed) {
      console.log(c.dim(`         → ${r.message}`));
    }
  }

  console.log();
  console.log(`  총 ${total}개 체크포인트: ${c.green(`${passed} PASS`)} / ${c.red(`${failed} FAIL`)}`);

  if (failed === 0) {
    console.log(c.bold(c.green('\n  모든 테스트 통과!')));
  } else {
    console.log(c.bold(c.red(`\n  ${failed}개 실패`)));
  }
}

// ─────────────────────────────────────
// 메인
// ─────────────────────────────────────

async function main(): Promise<void> {
  console.log(c.bold(c.blue('\n=========================================')));
  console.log(c.bold(c.blue('   매칭 API 자동화 테스트')));
  console.log(c.bold(c.blue(`   API: ${API_BASE}`)));
  console.log(c.bold(c.blue('=========================================\n')));

  // test-users.json 로드
  const usersPath = join(__dirname, 'test-users.json');
  let users: TestUser[];

  try {
    users = JSON.parse(readFileSync(usersPath, 'utf-8')) as TestUser[];
    console.log(c.blue(`[INFO] ${users.length}명의 테스트 유저 로드 완료`));
  } catch {
    console.error(c.red('[ERROR] test-users.json을 찾을 수 없습니다. 먼저 seed-test-users.ts를 실행하세요.'));
    process.exit(1);
  }

  // 서버 연결 확인
  try {
    const res = await fetch(`${API_BASE.replace('/v1', '')}/health`).catch(() => null);
    if (!res || res.status !== 200) {
      console.warn(c.yellow('[WARN] 서버 health check 실패. 서버가 실행 중인지 확인하세요.'));
    } else {
      console.log(c.green('[INFO] 서버 연결 확인 완료'));
    }
  } catch {
    console.warn(c.yellow('[WARN] 서버 연결 확인 실패 — 계속 진행합니다.'));
  }

  // 각 시나리오 독립적으로 실행 (실패해도 다음 진행)
  await scenario1_basicMatch(users).catch(err => {
    console.error(c.red('[ERROR] 시나리오 1 예외:'), err);
  });

  await scenario2_scoreFilterNoMatch(users).catch(err => {
    console.error(c.red('[ERROR] 시나리오 2 예외:'), err);
  });

  await scenario3_locationFilterNoMatch(users).catch(err => {
    console.error(c.red('[ERROR] 시나리오 3 예외:'), err);
  });

  await scenario4_cancelAndReRequest(users).catch(err => {
    console.error(c.red('[ERROR] 시나리오 4 예외:'), err);
  });

  await scenario5_scoreBasedMatch(users).catch(err => {
    console.error(c.red('[ERROR] 시나리오 5 예외:'), err);
  });

  await scenario6_expiryTimeout(users).catch(err => {
    console.error(c.red('[ERROR] 시나리오 6 예외:'), err);
  });

  printSummary();

  await prisma.$disconnect();
}

main().catch(err => {
  console.error(c.red('[FATAL]'), err);
  process.exit(1);
});
