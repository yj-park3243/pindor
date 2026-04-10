/**
 * 매칭 알고리즘 단위 테스트
 *
 * DB/서버 의존 없이 순수 알고리즘 로직만 검증.
 * 입력: tests/matching-test-data.json
 * 출력: tests/matching-test-results.json
 *
 * 실행: npx tsx tests/matching-algorithm.test.ts
 */

import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

// ─── 알고리즘 함수 (워커에서 추출) ───

interface WaitingRequest {
  id: string;
  requesterId: string;
  sportsProfileId: string;
  pinId: string;
  sportType: string;
  desiredTimeSlot: string | null;
  createdAt: Date;
  expiresAt: Date;
  currentScore: number;
  glickoRating: number;
  glickoRd: number;
  glickoVolatility: number | null;
  glickoLastUpdatedAt: Date | null;
  isPlacement: boolean;
  lossStreak: number;
  recentOpponentIds: string[];
  winStreak: number;
  // 테스트용 추가 필드
  label?: string;
}

function getWaitRatio(req: WaitingRequest, now: number): number {
  const created = new Date(req.createdAt).getTime();
  const expires = new Date(req.expiresAt).getTime();
  const MIN_WINDOW_MS = 30 * 60 * 1000;
  const totalWindow = Math.max(expires - created, MIN_WINDOW_MS);
  return Math.min(1.0, Math.max(0.0, (now - created) / totalWindow));
}

function expansionFactor(waitRatio: number): number {
  if (waitRatio <= 0.2) return 0.0;
  const adjusted = (waitRatio - 0.2) / 0.8;
  return adjusted * adjusted;
}

function getEffectiveRange(req: WaitingRequest, now: number): number {
  const BASE_RANGE = 50;
  const MAX_RANGE = 350;
  const waitRatio = getWaitRatio(req, now);
  const range = BASE_RANGE + (MAX_RANGE - BASE_RANGE) * expansionFactor(waitRatio);
  const rd = req.glickoRd || 350;
  const rdMultiplier = req.isPlacement
    ? Math.min(1.3, 1.0 + (rd - 50) / 350 * 0.3)
    : 1.0 + (rd - 50) / 350;
  return Math.min(range * rdMultiplier, 250);
}

function isRecentOpponent(a: WaitingRequest, b: WaitingRequest): boolean {
  return (a.recentOpponentIds || []).includes(b.sportsProfileId) ||
         (b.recentOpponentIds || []).includes(a.sportsProfileId);
}

interface PairInfo {
  i: number;
  j: number;
  cost: number;
  ratingDiff: number;
  effectiveRange: number;
  adjustedRatingI: number;
  adjustedRatingJ: number;
  waitRatioI: number;
  waitRatioJ: number;
}

function findOptimalPairs(
  requests: WaitingRequest[],
  now: number,
  smallPool: boolean = false,
): { pairs: [WaitingRequest, WaitingRequest][]; details: PairInfo[] } {
  if (requests.length < 2) return { pairs: [], details: [] };

  const n = requests.length;
  const allPairs: PairInfo[] = [];

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (requests[i].requesterId === requests[j].requesterId) continue;

      const adjustedRatingI = requests[i].lossStreak >= 3
        ? requests[i].glickoRating - 50
        : requests[i].glickoRating;
      const adjustedRatingJ = requests[j].lossStreak >= 3
        ? requests[j].glickoRating - 50
        : requests[j].glickoRating;

      const rangeA = getEffectiveRange(requests[i], now);
      const rangeB = getEffectiveRange(requests[j], now);
      const effectiveRange = Math.max(rangeA, rangeB);
      const ratingDiff = Math.abs(adjustedRatingI - adjustedRatingJ);

      if (ratingDiff > 250) continue;
      if (!smallPool && ratingDiff > effectiveRange) continue;

      const avgWaitRatio = (getWaitRatio(requests[i], now) + getWaitRatio(requests[j], now)) / 2;
      const waitDiscount = 1.0 - 0.7 * avgWaitRatio;
      let cost = ratingDiff * waitDiscount;

      if (isRecentOpponent(requests[i], requests[j])) {
        cost += 9999;
      }
      if (requests[i].isPlacement || requests[j].isPlacement) {
        cost *= 0.5;
      }

      allPairs.push({
        i, j, cost, ratingDiff, effectiveRange,
        adjustedRatingI, adjustedRatingJ,
        waitRatioI: getWaitRatio(requests[i], now),
        waitRatioJ: getWaitRatio(requests[j], now),
      });
    }
  }

  allPairs.sort((a, b) => a.cost - b.cost);

  const matched = new Set<number>();
  const result: [WaitingRequest, WaitingRequest][] = [];
  const selectedDetails: PairInfo[] = [];

  for (const pair of allPairs) {
    if (matched.has(pair.i) || matched.has(pair.j)) continue;
    if (pair.cost >= 9999) continue;
    matched.add(pair.i);
    matched.add(pair.j);
    result.push([requests[pair.i], requests[pair.j]]);
    selectedDetails.push(pair);
  }

  return { pairs: result, details: selectedDetails };
}

// ─── 테스트 실행 ───

interface TestScenario {
  name: string;
  description: string;
  simulatedTime: string; // ISO date — "now" 기준 시각
  requests: Array<{
    label: string;
    requesterId: string;
    sportsProfileId: string;
    pinId: string;
    sportType: string;
    glickoRating: number;
    glickoRd: number;
    isPlacement: boolean;
    lossStreak: number;
    winStreak: number;
    recentOpponentIds: string[];
    createdAt: string;   // ISO date
    expiresAt: string;   // ISO date
  }>;
  expectedMatches?: Array<{
    playerA: string; // label
    playerB: string;
  }>;
  expectedUnmatched?: string[]; // labels
}

interface TestResult {
  scenario: string;
  description: string;
  simulatedTime: string;
  totalRequests: number;
  matchedPairs: Array<{
    playerA: { label: string; rating: number; adjustedRating: number; waitRatio: number };
    playerB: { label: string; rating: number; adjustedRating: number; waitRatio: number };
    cost: number;
    ratingDiff: number;
    effectiveRange: number;
  }>;
  unmatchedPlayers: string[];
  expectedMatches: Array<{ playerA: string; playerB: string }> | null;
  matchesExpected: boolean;
  pass: boolean;
}

function runScenario(scenario: TestScenario): TestResult {
  const now = new Date(scenario.simulatedTime).getTime();

  const requests: WaitingRequest[] = scenario.requests.map((r) => ({
    id: r.sportsProfileId,
    requesterId: r.requesterId,
    sportsProfileId: r.sportsProfileId,
    pinId: r.pinId,
    sportType: r.sportType,
    desiredTimeSlot: null,
    createdAt: new Date(r.createdAt),
    expiresAt: new Date(r.expiresAt),
    currentScore: r.glickoRating,
    glickoRating: r.glickoRating,
    glickoRd: r.glickoRd,
    glickoVolatility: 0.06,
    glickoLastUpdatedAt: null,
    isPlacement: r.isPlacement,
    lossStreak: r.lossStreak,
    winStreak: r.winStreak,
    recentOpponentIds: r.recentOpponentIds,
    label: r.label,
  }));

  // 그룹핑 (pinId + sportType)
  const groups = new Map<string, WaitingRequest[]>();
  for (const req of requests) {
    const key = `${req.pinId}::${req.sportType}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(req);
  }

  const allMatchedPairs: TestResult['matchedPairs'] = [];
  const allMatchedLabels = new Set<string>();

  for (const [, groupReqs] of groups) {
    const smallPool = groupReqs.length <= 4;
    const { pairs, details } = findOptimalPairs(groupReqs, now, smallPool);

    for (let k = 0; k < pairs.length; k++) {
      const [a, b] = pairs[k];
      const d = details[k];
      allMatchedPairs.push({
        playerA: { label: a.label!, rating: a.glickoRating, adjustedRating: d.adjustedRatingI, waitRatio: +d.waitRatioI.toFixed(3) },
        playerB: { label: b.label!, rating: b.glickoRating, adjustedRating: d.adjustedRatingJ, waitRatio: +d.waitRatioJ.toFixed(3) },
        cost: +d.cost.toFixed(2),
        ratingDiff: d.ratingDiff,
        effectiveRange: +d.effectiveRange.toFixed(1),
      });
      allMatchedLabels.add(a.label!);
      allMatchedLabels.add(b.label!);
    }
  }

  const unmatchedPlayers = requests
    .filter((r) => !allMatchedLabels.has(r.label!))
    .map((r) => r.label!);

  // 기대값 검증
  let pass = true;
  if (scenario.expectedMatches) {
    for (const exp of scenario.expectedMatches) {
      const found = allMatchedPairs.some(
        (p) =>
          (p.playerA.label === exp.playerA && p.playerB.label === exp.playerB) ||
          (p.playerA.label === exp.playerB && p.playerB.label === exp.playerA),
      );
      if (!found) pass = false;
    }
  }
  if (scenario.expectedUnmatched) {
    for (const label of scenario.expectedUnmatched) {
      if (!unmatchedPlayers.includes(label)) pass = false;
    }
  }

  return {
    scenario: scenario.name,
    description: scenario.description,
    simulatedTime: scenario.simulatedTime,
    totalRequests: requests.length,
    matchedPairs: allMatchedPairs,
    unmatchedPlayers,
    expectedMatches: scenario.expectedMatches ?? null,
    matchesExpected: !!scenario.expectedMatches,
    pass,
  };
}

// ─── 메인 ───

import { fileURLToPath } from 'url';
import { dirname } from 'path';
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const dataPath = join(__dirname, 'matching-test-data.json');
const resultPath = join(__dirname, 'matching-test-results.json');

const scenarios: TestScenario[] = JSON.parse(readFileSync(dataPath, 'utf-8'));
const results: TestResult[] = scenarios.map(runScenario);

writeFileSync(resultPath, JSON.stringify(results, null, 2), 'utf-8');

// 콘솔 출력
console.log('\n========== 매칭 알고리즘 테스트 결과 ==========\n');
let passCount = 0;
for (const r of results) {
  const status = r.pass ? '✅ PASS' : '❌ FAIL';
  if (r.pass) passCount++;
  console.log(`${status}  ${r.scenario}`);
  console.log(`   ${r.description}`);
  console.log(`   요청 ${r.totalRequests}명 → 매칭 ${r.matchedPairs.length}쌍, 미매칭 ${r.unmatchedPlayers.length}명`);
  for (const p of r.matchedPairs) {
    console.log(`     ${p.playerA.label}(${p.playerA.rating}) ↔ ${p.playerB.label}(${p.playerB.rating})  cost=${p.cost} diff=${p.ratingDiff} range=${p.effectiveRange}`);
  }
  if (r.unmatchedPlayers.length > 0) {
    console.log(`     미매칭: ${r.unmatchedPlayers.join(', ')}`);
  }
  console.log();
}
console.log(`\n총 ${results.length}개 시나리오: ${passCount} PASS / ${results.length - passCount} FAIL`);
console.log(`결과 저장: ${resultPath}\n`);
