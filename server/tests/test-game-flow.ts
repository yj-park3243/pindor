/**
 * 경기 전체 플로우 테스트
 * 매칭 성사 → 경기 확정 → 결과 제출 → 점수 반영까지의 End-to-End 테스트
 *
 * 실행: npx tsx tests/test-game-flow.ts
 *
 * 사전 조건:
 *   - 서버가 실행 중이어야 합니다 (API_BASE 환경변수 또는 http://localhost:3000/v1)
 *   - tests/test-users.json 파일이 존재해야 합니다 (seed-test-users.ts 먼저 실행)
 */

import 'dotenv/config';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

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
  tier: string;
  sportsProfileId: string;
  token: string;
}

// ─────────────────────────────────────
// 테스트 결과 집계
// ─────────────────────────────────────

interface StepResult {
  step: string;
  passed: boolean;
  message: string;
  duration: number;
}

const results: StepResult[] = [];

function pass(step: string, message: string, durationMs: number): void {
  results.push({ step, passed: true, message, duration: durationMs });
  console.log(c.green(`  [PASS] ${step}: ${message}`) + c.dim(` (${durationMs}ms)`));
}

function fail(step: string, message: string, durationMs: number, err?: unknown): void {
  results.push({ step, passed: false, message, duration: durationMs });
  console.log(c.red(`  [FAIL] ${step}: ${message}`) + c.dim(` (${durationMs}ms)`));
  if (err) {
    const msg = err instanceof Error ? err.message : JSON.stringify(err);
    console.log(c.dim(`         ${msg}`));
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
): Promise<{ status: number; data: T }> {
  const res = await fetch(`${API_BASE}${path}`, {
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

  return { status: res.status, data };
}

// ─────────────────────────────────────
// 정리 헬퍼
// ─────────────────────────────────────

async function cleanup(user: TestUser): Promise<void> {
  // 대기 중인 요청 취소
  const { data: reqData } = await apiRequest<any>('GET', '/matches/requests?status=WAITING', user.token);
  for (const req of (reqData?.data ?? [])) {
    await apiRequest('DELETE', `/matches/requests/${req.id}`, user.token);
  }

  // 진행 중인 매칭 취소
  for (const status of ['CHAT', 'CONFIRMED']) {
    const { data } = await apiRequest<any>('GET', `/matches?status=${status}`, user.token);
    for (const m of (data?.data ?? [])) {
      await apiRequest('PATCH', `/matches/${m.id}/cancel`, user.token, { reason: '게임 플로우 테스트 정리' });
    }
  }
}

// ─────────────────────────────────────
// 매칭 성사 헬퍼
// ─────────────────────────────────────

const BASE_LAT = 37.5009;
const BASE_LNG = 127.0363;

async function createAndMatchUsers(user1: TestUser, user2: TestUser): Promise<string | null> {
  const body = {
    sportType: 'GOLF',
    latitude: BASE_LAT,
    longitude: BASE_LNG,
    locationName: '역삼동 테스트',
    radiusKm: 20,
    minOpponentScore: 800,
    maxOpponentScore: 1600,
  };

  // user1 요청
  const { status: s1 } = await apiRequest('POST', '/matches/requests', user1.token, body);
  if (s1 !== 201) return null;

  // user2 요청 (자동 매칭 트리거)
  const { status: s2 } = await apiRequest('POST', '/matches/requests', user2.token, {
    ...body,
    latitude: BASE_LAT + 0.001,
    longitude: BASE_LNG + 0.001,
  });
  if (s2 !== 201) return null;

  // 매칭 대기
  await new Promise(res => setTimeout(res, 1000));

  const { data } = await apiRequest<any>('GET', '/matches?status=CHAT', user1.token);
  const matches: any[] = data?.data ?? [];
  return matches.length > 0 ? matches[0].id : null;
}

// ─────────────────────────────────────
// 게임 플로우 메인 테스트
// ─────────────────────────────────────

async function testGameFlow(users: TestUser[]): Promise<void> {
  console.log(c.bold(c.blue('\n=========================================')));
  console.log(c.bold(c.blue('   경기 전체 플로우 테스트')));
  console.log(c.bold(c.blue('=========================================\n')));

  // 테스트에 사용할 유저 선택 (index 40, 41)
  const user1 = users[40];
  const user2 = users[41];

  console.log(c.blue(`[INFO] 테스트 유저: ${user1.nickname}(${user1.score}점) vs ${user2.nickname}(${user2.score}점)`));
  console.log();

  // 사전 정리
  await cleanup(user1);
  await cleanup(user2);

  // ─── STEP 1: 매칭 요청 및 성사 ───
  let t = Date.now();
  const matchId = await createAndMatchUsers(user1, user2);

  if (!matchId) {
    fail('STEP 1', '매칭 성사 실패 — 이후 테스트 불가', Date.now() - t);
    printSummary();
    return;
  }
  pass('STEP 1', `매칭 성사 (matchId: ${matchId.slice(0, 8)}..., status: CHAT)`, Date.now() - t);

  // ─── STEP 2: 매칭 상세 조회 ───
  t = Date.now();
  const { status: gs, data: matchDetail } = await apiRequest<any>('GET', `/matches/${matchId}`, user1.token);

  if (gs === 200 && matchDetail?.data?.status === 'CHAT') {
    pass('STEP 2', `매칭 상세 조회 성공 (status: CHAT)`, Date.now() - t);
  } else {
    fail('STEP 2', `매칭 상세 조회 실패 (httpStatus: ${gs}, matchStatus: ${matchDetail?.data?.status})`, Date.now() - t);
  }

  // ─── STEP 3: user1 경기 확정 ───
  t = Date.now();
  const { status: cs1 } = await apiRequest('PATCH', `/matches/${matchId}/confirm`, user1.token, {
    scheduledDate: '2026-04-20',
    scheduledTime: '14:00',
    venueName: '강남 골프 클럽',
    venueLatitude: BASE_LAT,
    venueLongitude: BASE_LNG,
  });

  if (cs1 === 200) {
    pass('STEP 3', 'user1 경기 확정 (scheduledDate, venueName 설정)', Date.now() - t);
  } else {
    fail('STEP 3', `user1 경기 확정 실패 (status: ${cs1})`, Date.now() - t);
    // 계속 진행 시도
  }

  // ─── STEP 3-B: user2 경기 확정 ───
  t = Date.now();
  const { status: cs2 } = await apiRequest('PATCH', `/matches/${matchId}/confirm`, user2.token, {});

  if (cs2 === 200) {
    pass('STEP 3-B', 'user2 경기 확정 → CONFIRMED 상태로 전환', Date.now() - t);
  } else {
    fail('STEP 3-B', `user2 경기 확정 실패 (status: ${cs2})`, Date.now() - t);
  }

  // 매칭 상태 CONFIRMED 확인
  const { data: confirmedDetail } = await apiRequest<any>('GET', `/matches/${matchId}`, user1.token);
  const matchStatus = confirmedDetail?.data?.status;
  console.log(c.dim(`         현재 매칭 상태: ${matchStatus}`));

  // ─── STEP 4: 게임 ID 조회 ───
  t = Date.now();

  // 게임 목록에서 해당 매칭의 게임 찾기
  const { data: gameListData } = await apiRequest<any>('GET', '/games', user1.token);
  const games: any[] = gameListData?.data ?? [];

  // 가장 최근 게임 (매칭과 연결된 것)
  const game = games.find((g: any) => g.matchId === matchId) ?? games[0];

  if (!game) {
    fail('STEP 4', '게임 레코드를 찾을 수 없음 (매칭 시 자동 생성되어야 함)', Date.now() - t);
    printSummary();
    await cleanup(user1);
    await cleanup(user2);
    return;
  }

  const gameId = game.id;
  pass('STEP 4', `게임 레코드 확인 (gameId: ${gameId.slice(0, 8)}..., status: ${game.resultStatus})`, Date.now() - t);

  // ─── STEP 5: user1 점수 조회 (경기 전) ───
  t = Date.now();
  const { data: user1Before } = await apiRequest<any>('GET', '/users/me', user1.token);
  const scoreBefore1 = user1Before?.data?.sportsProfiles?.find((p: any) => p.sportType === 'GOLF')?.currentScore ?? user1.score;
  pass('STEP 5', `user1 경기 전 점수: ${scoreBefore1}`, Date.now() - t);

  const { data: user2Before } = await apiRequest<any>('GET', '/users/me', user2.token);
  const scoreBefore2 = user2Before?.data?.sportsProfiles?.find((p: any) => p.sportType === 'GOLF')?.currentScore ?? user2.score;
  pass('STEP 5', `user2 경기 전 점수: ${scoreBefore2}`, Date.now() - t);

  // ─── STEP 6: user1이 결과 제출 (user1 승리) ───
  t = Date.now();
  const { status: rs, data: resultData } = await apiRequest('POST', `/games/${gameId}/result`, user1.token, {
    myScore: 72,
    opponentScore: 85,
    winnerId: user1.sportsProfileId,
    playedAt: new Date().toISOString(),
    venueName: '강남 골프 클럽',
    scoreData: {
      format: 'stroke',
      holes: 18,
    },
  });

  if (rs === 201) {
    pass('STEP 6', `결과 제출 성공 — user1 승리 신고 (myScore: 72, opponentScore: 85)`, Date.now() - t);
    console.log(c.dim(`         resultData: ${JSON.stringify(resultData?.data?.resultStatus ?? resultData?.data)}`));
  } else {
    fail('STEP 6', `결과 제출 실패 (status: ${rs})`, Date.now() - t, resultData);
    // 계속 진행 시도
  }

  // ─── STEP 7: user2가 결과 확인 (동의) ───
  t = Date.now();
  const { status: cfs, data: confirmData } = await apiRequest('POST', `/games/${gameId}/confirm`, user2.token, {
    isConfirmed: true,
    comment: '결과 확인했습니다.',
  });

  if (cfs === 200) {
    pass('STEP 7', `user2 결과 확인 동의 (resultStatus: ${confirmData?.data?.resultStatus ?? 'unknown'})`, Date.now() - t);
  } else {
    fail('STEP 7', `user2 결과 확인 실패 (status: ${cfs})`, Date.now() - t, confirmData);
  }

  // ─── STEP 8: 게임 상태 확인 (VERIFIED) ───
  t = Date.now();
  await new Promise(res => setTimeout(res, 500)); // 처리 대기

  const { data: gameDetail } = await apiRequest<any>('GET', `/games/${gameId}`, user1.token);
  const gameStatus = gameDetail?.data?.resultStatus;

  if (gameStatus === 'VERIFIED') {
    pass('STEP 8', `게임 상태 VERIFIED 확인`, Date.now() - t);
  } else {
    fail('STEP 8', `예상 상태 VERIFIED, 실제: ${gameStatus}`, Date.now() - t);
  }

  // ─── STEP 9: 점수 변동 확인 ───
  t = Date.now();
  const { data: user1After } = await apiRequest<any>('GET', '/users/me', user1.token);
  const scoreAfter1 = user1After?.data?.sportsProfiles?.find((p: any) => p.sportType === 'GOLF')?.currentScore;

  const { data: user2After } = await apiRequest<any>('GET', '/users/me', user2.token);
  const scoreAfter2 = user2After?.data?.sportsProfiles?.find((p: any) => p.sportType === 'GOLF')?.currentScore;

  if (scoreAfter1 !== undefined && scoreAfter1 !== scoreBefore1) {
    const diff1 = scoreAfter1 - scoreBefore1;
    pass('STEP 9', `user1 점수 변동 확인: ${scoreBefore1} → ${scoreAfter1} (${diff1 > 0 ? '+' : ''}${diff1})`, Date.now() - t);
  } else if (scoreAfter1 === undefined) {
    fail('STEP 9', 'user1 점수 조회 실패 (GET /users/me)', Date.now() - t);
  } else {
    fail('STEP 9', `user1 점수 변동 없음: ${scoreBefore1} → ${scoreAfter1}`, Date.now() - t);
  }

  if (scoreAfter2 !== undefined && scoreAfter2 !== scoreBefore2) {
    const diff2 = scoreAfter2 - scoreBefore2;
    pass('STEP 9', `user2 점수 변동 확인: ${scoreBefore2} → ${scoreAfter2} (${diff2 > 0 ? '+' : ''}${diff2})`, Date.now() - t);
  } else if (scoreAfter2 === undefined) {
    fail('STEP 9', 'user2 점수 조회 실패 (GET /users/me)', Date.now() - t);
  } else {
    fail('STEP 9', `user2 점수 변동 없음: ${scoreBefore2} → ${scoreAfter2}`, Date.now() - t);
  }

  // ─── STEP 10: 점수 이력 확인 (bonus) ───
  t = Date.now();
  const { data: scoreHistData } = await apiRequest<any>('GET', '/users/me/score-history?sportType=GOLF', user1.token);
  const scoreHistories: any[] = scoreHistData?.data ?? [];

  if (scoreHistories.length > 0) {
    const latest = scoreHistories[0];
    pass('STEP 10', `점수 이력 확인 — 최근 변동: ${latest.scoreBefore} → ${latest.scoreAfter} (${latest.changeType})`, Date.now() - t);
  } else {
    console.log(c.yellow(`  [SKIP] STEP 10: 점수 이력 API 응답 없음 (선택사항)`));
  }
}

// ─────────────────────────────────────
// 결과 요약
// ─────────────────────────────────────

function printSummary(): void {
  console.log(c.bold(c.blue('\n=========================================')));
  console.log(c.bold(c.blue('   경기 플로우 테스트 결과 요약')));
  console.log(c.bold(c.blue('=========================================\n')));

  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed).length;
  const total = results.length;

  for (const r of results) {
    const icon = r.passed ? c.green('[PASS]') : c.red('[FAIL]');
    const label = r.passed ? c.green(r.step) : c.red(r.step);
    console.log(`  ${icon} ${label}: ${r.message}`);
  }

  console.log();
  console.log(`  총 ${total}개 스텝: ${c.green(`${passed} PASS`)} / ${c.red(`${failed} FAIL`)}`);

  if (failed === 0) {
    console.log(c.bold(c.green('\n  모든 게임 플로우 테스트 통과!')));
  } else {
    console.log(c.bold(c.yellow(`\n  ${failed}개 스텝 실패 — 서버 로그를 확인하세요.`)));
  }
}

// ─────────────────────────────────────
// 메인
// ─────────────────────────────────────

async function main(): Promise<void> {
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
    }
  } catch {
    // 무시
  }

  await testGameFlow(users);
  printSummary();
}

main().catch(err => {
  console.error(c.red('[FATAL]'), err);
  process.exit(1);
});
