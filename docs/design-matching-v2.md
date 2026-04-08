# 매칭 시스템 V2 설계 문서

> 작성일: 2026-04-07  
> 버전: 2.0  
> 대상 시스템: 핀돌 (Spots) 스포츠 매칭 플랫폼  
> 현재 서버: Fastify + TypeORM + PostgreSQL / 앱: Flutter

---

## 목차

1. [변경 개요 및 동기](#1-변경-개요-및-동기)
2. [데이터베이스 스키마 변경](#2-데이터베이스-스키마-변경)
3. [Glicko-2 레이팅 시스템](#3-glicko-2-레이팅-시스템)
4. [배치 게임 시스템](#4-배치-게임-시스템)
5. [안정 매칭 알고리즘](#5-안정-매칭-알고리즘)
6. [부가 로직](#6-부가-로직)
7. [API 변경 사항](#7-api-변경-사항)
8. [앱 UI 변경 사항](#8-앱-ui-변경-사항)
9. [TODO 및 구현 계획](#9-todo-및-구현-계획)
10. [마이그레이션 전략](#10-마이그레이션-전략)

---

## 1. 변경 개요 및 동기

### 1.1 현행 시스템 문제점

| 항목 | 현행 | 문제 |
|------|------|------|
| 레이팅 | ELO (K-factor 가변) | 비활동 유저 불확실성 미반영, 신규 유저 배치 느림 |
| 매칭 알고리즘 | 그리디 (최고 점수 쌍 선택) | 전체 최적화 아님, 일부 유저 반복 매칭 가능 |
| 배치 게임 | 없음 | 신규 유저 점수 노출로 낮은 점수 기피 |
| 연속 매칭 | 동일 상대 제한 없음 | 같은 상대와 반복 매칭 발생 가능 |
| 연패 보호 | 없음 | 연패 유저 이탈 위험 |

### 1.2 V2 변경 요약

- **ELO → Glicko-2**: 불확실성(RD)과 변동성(σ) 도입으로 정확한 실력 추정
- **배치 게임**: 첫 5게임 동안 레이팅 비공개, 넓은 MMR 범위 적용
- **그리디 → 헝가리안 알고리즘**: 전체 대기 풀에서 최적 페어링
- **최근 상대 제외**: 24시간 내 동일 상대 재매칭 방지
- **연패 보호**: 3연패 시 유효 레이팅 -50 적용

---

## 2. 데이터베이스 스키마 변경

### 2.1 sports_profiles 테이블 변경

```sql
-- Glicko-2 파라미터 추가
ALTER TABLE sports_profiles
  ADD COLUMN glicko_rating      DOUBLE PRECISION NOT NULL DEFAULT 1500.0,
  ADD COLUMN glicko_rd          DOUBLE PRECISION NOT NULL DEFAULT 350.0,
  ADD COLUMN glicko_volatility  DOUBLE PRECISION NOT NULL DEFAULT 0.06,
  ADD COLUMN glicko_last_updated_at TIMESTAMPTZ,

  -- 배치 게임
  ADD COLUMN is_placement       BOOLEAN NOT NULL DEFAULT true,

  -- 연패 추적 (연승은 기존 win_streak 활용)
  ADD COLUMN loss_streak        INT NOT NULL DEFAULT 0,

  -- 최근 상대 (last 5 opponents, sportsProfileId 배열)
  ADD COLUMN recent_opponent_ids UUID[] NOT NULL DEFAULT '{}';
```

**컬럼 설명:**

| 컬럼 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `glicko_rating` | DOUBLE PRECISION | 1500.0 | Glicko-2 μ (레이팅 추정치) |
| `glicko_rd` | DOUBLE PRECISION | 350.0 | Rating Deviation — 높을수록 불확실 |
| `glicko_volatility` | DOUBLE PRECISION | 0.06 | σ — 플레이어 성적 변동성 |
| `glicko_last_updated_at` | TIMESTAMPTZ | NULL | RD 시간 감쇠 계산용 |
| `is_placement` | BOOLEAN | true | games_played < 5이면 true |
| `loss_streak` | INT | 0 | 연속 패배 수 |
| `recent_opponent_ids` | UUID[] | {} | 최근 5명 상대 sportsProfileId |

> **`current_score`는 유지한다.** Glicko-2 rating을 표시 점수로 동기화하여 기존 tier 시스템, 랭킹, 히스토리 API와의 하위 호환성을 보장한다. `current_score = round(glicko_rating)`으로 매 업데이트 시 동기화.

### 2.2 score_histories 테이블 변경

```sql
-- Glicko-2 상세 기록을 위한 컬럼 추가
ALTER TABLE score_histories
  ADD COLUMN rd_before     DOUBLE PRECISION,
  ADD COLUMN rd_after      DOUBLE PRECISION,
  ADD COLUMN volatility_before DOUBLE PRECISION,
  ADD COLUMN volatility_after  DOUBLE PRECISION,
  ADD COLUMN is_placement_game BOOLEAN NOT NULL DEFAULT false;
```

기존 `k_factor` 컬럼은 NULL 허용이므로 Glicko-2 전환 후 NULL로 남겨도 스키마 변경 불필요.

### 2.3 recent_opponents 테이블 (선택적 정규화)

`recent_opponent_ids` UUID[] 배열로 충분하지만, 24시간 조건 검사가 필요하므로 별도 테이블이 명확하다.

```sql
CREATE TABLE recent_opponents (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sports_profile_id UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
  opponent_id       UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
  matched_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_recent_opponent UNIQUE (sports_profile_id, opponent_id)
);

CREATE INDEX idx_recent_opponents_profile ON recent_opponents(sports_profile_id);
CREATE INDEX idx_recent_opponents_matched_at ON recent_opponents(matched_at);
```

> **결정**: 별도 테이블 방식 채택. UUID 배열은 매칭 시 `matched_at` 조건(24h 이내)을 검사할 수 없어서 배열만으로는 부족하다.

### 2.4 전체 마이그레이션 SQL

```sql
-- Migration: 20260407_matching_v2

BEGIN;

-- 1. sports_profiles Glicko-2 컬럼
ALTER TABLE sports_profiles
  ADD COLUMN IF NOT EXISTS glicko_rating      DOUBLE PRECISION NOT NULL DEFAULT 1500.0,
  ADD COLUMN IF NOT EXISTS glicko_rd          DOUBLE PRECISION NOT NULL DEFAULT 350.0,
  ADD COLUMN IF NOT EXISTS glicko_volatility  DOUBLE PRECISION NOT NULL DEFAULT 0.06,
  ADD COLUMN IF NOT EXISTS glicko_last_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_placement       BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS loss_streak        INT NOT NULL DEFAULT 0;

-- 2. 기존 유저 is_placement 초기화 (5게임 이상 플레이한 유저는 false)
UPDATE sports_profiles
  SET is_placement = false
  WHERE games_played >= 5;

-- 3. 기존 유저 glicko_rating을 current_score 기준으로 초기화
-- current_score 기본값이 1000이므로, Glicko-2 기본 1500과 맞추려면
-- 기존 점수 그대로 사용 (score range가 다르므로 별도 조정 없이 그냥 매핑)
UPDATE sports_profiles
  SET glicko_rating = current_score::DOUBLE PRECISION,
      glicko_rd = CASE
        WHEN games_played >= 30 THEN 100.0  -- 많이 한 유저: 확신도 높음
        WHEN games_played >= 10 THEN 200.0
        ELSE 350.0                            -- 신규/초보: 불확실
      END,
      glicko_last_updated_at = NOW();

-- 4. score_histories Glicko-2 컬럼
ALTER TABLE score_histories
  ADD COLUMN IF NOT EXISTS rd_before          DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS rd_after           DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS volatility_before  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS volatility_after   DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS is_placement_game  BOOLEAN NOT NULL DEFAULT false;

-- 5. recent_opponents 테이블
CREATE TABLE IF NOT EXISTS recent_opponents (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sports_profile_id UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
  opponent_id       UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
  matched_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_recent_opponent UNIQUE (sports_profile_id, opponent_id)
);

CREATE INDEX IF NOT EXISTS idx_recent_opponents_profile
  ON recent_opponents(sports_profile_id);
CREATE INDEX IF NOT EXISTS idx_recent_opponents_matched_at
  ON recent_opponents(matched_at);

COMMIT;
```

---

## 3. Glicko-2 레이팅 시스템

### 3.1 개요

Glicko-2는 Mark Glickman(Boston University, 2001)이 ELO의 한계를 보완하여 설계한 레이팅 시스템이다. 핵심 파라미터:

| 파라미터 | 기호 | 기본값 | 의미 |
|----------|------|--------|------|
| Rating | μ (mu) | 1500 | 실력 추정치 |
| Rating Deviation | φ (phi / RD) | 350 | 불확실성 — 낮을수록 신뢰도 높음 |
| Volatility | σ (sigma) | 0.06 | 성적 변동성 — 오락가락하는 유저일수록 높음 |
| System constant | τ (tau) | 0.5 | σ 변화량 제한 (0.3~1.2 범위, 핀돌은 0.5 사용) |

**Glicko-2 내부 스케일:** μ' = (μ - 1500) / 173.7178, φ' = φ / 173.7178

### 3.2 알고리즘 의사코드

```
/**
 * Glicko-2 레이팅 업데이트
 * 입력: 플레이어의 현재 (μ, φ, σ), 상대방 목록과 결과
 * 출력: 새로운 (μ', φ', σ')
 *
 * 핀돌 단순화: 각 게임 = 1개의 레이팅 기간 (배치 기간 없음)
 */

function updateGlicko2(player, opponents):
  τ = 0.5  // 시스템 상수

  // Step 1: Glicko-2 내부 스케일 변환
  μ = player.rating
  φ = player.rd
  σ = player.volatility

  μ_prime = (μ - 1500) / 173.7178
  φ_prime = φ / 173.7178

  // Step 2: 상대방별 E(s|μ, μ_j, φ_j) 계산
  // 게임이 없으면 φ만 증가시키고 종료
  if opponents is empty:
    φ_star = sqrt(φ_prime^2 + σ^2)
    // RD 시간 감쇠만 적용 (레이팅, 변동성 변경 없음)
    player.rd = φ_star * 173.7178
    return

  v = 0  // 분산 추정량
  Δ = 0  // 추정 점수 개선량

  for each (opponent, result) in opponents:
    μ_j = (opponent.rating - 1500) / 173.7178
    φ_j = opponent.rd / 173.7178

    g_φ_j = 1 / sqrt(1 + 3 * φ_j^2 / π^2)
    E_j = 1 / (1 + exp(-g_φ_j * (μ_prime - μ_j)))
    s_j = result  // 1.0 = 승, 0.5 = 무, 0.0 = 패

    v += g_φ_j^2 * E_j * (1 - E_j)
    Δ += g_φ_j * (s_j - E_j)

  v = 1 / v
  Δ = v * Δ

  // Step 3: 새로운 변동성 σ' 계산 (Illinois 알고리즘)
  a = ln(σ^2)
  f(x) = (exp(x) * (Δ^2 - φ_prime^2 - v - exp(x))) /
         (2 * (φ_prime^2 + v + exp(x))^2) - (x - a) / τ^2

  // 이분법으로 f(x) = 0 찾기
  A = a
  if Δ^2 > φ_prime^2 + v:
    B = ln(Δ^2 - φ_prime^2 - v)
  else:
    k = 1
    while f(a - k * τ) < 0:
      k++
    B = a - k * τ

  f_A = f(A)
  f_B = f(B)

  // 수렴 조건: |B - A| < ε = 0.000001
  while |B - A| > 0.000001:
    C = A + (A - B) * f_A / (f_B - f_A)
    f_C = f(C)
    if f_C * f_B < 0:
      A = B
      f_A = f_B
    else:
      f_A = f_A / 2
    B = C
    f_B = f_C

  σ_new = exp(A / 2)

  // Step 4: 새로운 RD (사전 업데이트)
  φ_star = sqrt(φ_prime^2 + σ_new^2)

  // Step 5: 새로운 φ', μ'
  φ_new = 1 / sqrt(1/φ_star^2 + 1/v)
  μ_new = μ_prime + φ_new^2 * (Δ / v)

  // Step 6: Glicko-2 → 원래 스케일 역변환
  player.rating = μ_new * 173.7178 + 1500
  player.rd = φ_new * 173.7178
  player.volatility = σ_new

  // Step 7: 최솟값 보호
  player.rd = max(player.rd, 30.0)     // RD 최솟값 30
  player.rating = max(player.rating, 100.0)  // 레이팅 최솟값 100
```

### 3.3 RD 시간 감쇠 (비활동 유저)

비활동 기간에 따라 RD가 자동으로 증가하여 불확실성을 반영한다. 매칭 요청 시 또는 매칭 큐 워커 실행 시 계산:

```
/**
 * 비활동 기간 RD 감쇠 적용
 * 레이팅 기간 = 1게임 단위 (단순화)
 * 비활동 기간을 "상상의 레이팅 기간"으로 환산
 */

function applyRdDecay(player, currentTime):
  if player.glickoLastUpdatedAt is null:
    return  // 첫 게임 전

  daysSinceLastGame = (currentTime - player.glickoLastUpdatedAt) / (1000 * 60 * 60 * 24)

  // 30일 이상 비활동 시 RD 감쇠 적용
  // 30일마다 σ^2 만큼 φ^2 증가
  if daysSinceLastGame >= 30:
    periods = floor(daysSinceLastGame / 30)
    φ = player.glickoRd / 173.7178
    σ = player.glickoVolatility

    for i in range(periods):
      φ = sqrt(φ^2 + σ^2)
      // RD 상한: 350 (초기값 초과 불가)
      φ = min(φ, 350 / 173.7178)

    player.glickoRd = φ * 173.7178
```

### 3.4 TypeScript 구현 구조

```
server/src/shared/utils/glicko2.ts  (신규)
  - updateGlicko2(player, opponents): Glicko2Result
  - applyRdDecay(player, now): void
  - glicko2ToDisplayScore(rating): number

server/src/modules/games/games.service.ts  (수정)
  - applyEloChanges() → applyRatingChanges()
  - 내부에서 glicko2.ts 호출
```

```typescript
// glicko2.ts 인터페이스 정의

export interface Glicko2Player {
  rating: number;       // μ (기본 1500)
  rd: number;           // φ (기본 350)
  volatility: number;   // σ (기본 0.06)
}

export interface Glicko2Opponent {
  rating: number;
  rd: number;
  result: 1 | 0.5 | 0;  // 승/무/패
}

export interface Glicko2Result {
  newRating: number;
  newRd: number;
  newVolatility: number;
  ratingChange: number;  // 표시용 변동량
}

export function updateGlicko2(
  player: Glicko2Player,
  opponents: Glicko2Opponent[],
  tau: number = 0.5,
): Glicko2Result { ... }
```

### 3.5 current_score 동기화

레거시 티어 시스템과의 호환 유지를 위해:

```typescript
// games.service.ts applyRatingChanges() 내부
const newDisplayScore = Math.round(glickoResult.newRating);
await manager.update(SportsProfile, profileId, {
  glickoRating: glickoResult.newRating,
  glickoRd: glickoResult.newRd,
  glickoVolatility: glickoResult.newVolatility,
  glickoLastUpdatedAt: new Date(),
  currentScore: newDisplayScore,  // 티어 계산용 동기화
  // ... 기타 필드
});
```

---

## 4. 배치 게임 시스템

### 4.1 정의

- **배치 게임**: `games_played < 5`인 상태의 게임
- `is_placement` 컬럼: `games_played < 5`이면 `true` (게임 완료 후 자동 갱신)
- 배치 완료 후: `is_placement = false`로 변경, 실제 레이팅 공개

### 4.2 배치 게임 중 매칭 규칙

| 항목 | 배치 중 | 일반 |
|------|---------|------|
| MMR 매칭 범위 | ±500 고정 | 대기 시간 기반 ±100~±500 |
| 레이팅 표시 | 숨김 ("배치 중") | 공개 |
| 점수 변동 | Glicko-2 적용 (내부만) | Glicko-2 적용 + 표시 |
| 상대 배치 여부 | 무관 (배치 중인 상대와도 매칭 가능) | 무관 |

### 4.3 배치 완료 처리

```
/**
 * 게임 결과 반영 후 배치 상태 갱신
 */

function updatePlacementStatus(profile):
  newGamesPlayed = profile.gamesPlayed + 1
  profile.gamesPlayed = newGamesPlayed

  if newGamesPlayed >= 5 and profile.isPlacement == true:
    profile.isPlacement = false
    // 배치 완료 알림 트리거 → 실제 레이팅 공개
    return { placementCompleted: true, finalRating: profile.glickoRating }

  return { placementCompleted: false }
```

### 4.4 배치 게임 중 레이팅 추정 표시 (앱)

배치 완료 전에도 앱 내부적으로는 잠정 레이팅을 계산하여 보여줄 수 있다 (선택 사항):

```
// 앱 표시 로직 (Flutter)
if (profile.isPlacement) {
  display = "배치 중 (${profile.gamesPlayed}/5)";
  // 잠정 레이팅은 서버에 있지만 숨김
} else {
  display = "${profile.currentScore}점";
}
```

---

## 5. 안정 매칭 알고리즘

### 5.1 현행 vs V2 비교

| | 현행 (그리디) | V2 (헝가리안) |
|--|--------------|--------------|
| 방식 | 최고 점수 쌍을 순차적으로 선택 | 전체 페어링 비용 최소화 |
| 복잡도 | O(n²) | O(n³) |
| 최적성 | 지역 최적 | 전역 최적 |
| 짝수 보장 | 홀수이면 마지막 1명 잔류 | 동일 (짝수만 매칭) |
| 구현 난이도 | 낮음 | 중간 |

**실용적 판단**: 핀 당 동시 대기 인원이 현실적으로 10~30명 수준이면, O(n³)은 n=30에서 27,000번 연산으로 10ms 이내 처리 가능. 부담 없음.

### 5.2 비용 함수 정의

매칭 비용 = 레이팅 차이 점수 (낮을수록 좋은 매칭):

```
/**
 * 매칭 비용 계산
 * 반환값이 낮을수록 더 좋은 매칭 (헝가리안은 최소 비용을 찾음)
 */

function matchingCost(reqA, reqB):
  // 1. 기본 레이팅 차이 비용
  ratingA = getEffectiveRating(reqA)  // 연패 보호 적용
  ratingB = getEffectiveRating(reqB)

  ratingDiff = abs(ratingA - ratingB)
  skillCost = ratingDiff / 500.0  // 0.0 ~ 1.0+

  // 2. 시간대 불일치 패널티
  timeSlotCost = calcTimeSlotCost(reqA.desiredTimeSlot, reqB.desiredTimeSlot)
  //   동일: 0.0, ANY와 특정: 0.1, 불일치: 0.4

  // 3. 최근 상대 페널티 (최근 24시간 내 동일 상대)
  recentOpponentCost = isRecentOpponent(reqA, reqB) ? 999.0 : 0.0
  // 999.0은 사실상 매칭 불가 처리

  // 4. MMR 범위 초과 페널티
  maxRange = getMMRRange(min(waitMinutesA, waitMinutesB))
  outOfRangeCost = ratingDiff > maxRange ? 999.0 : 0.0

  return skillCost + timeSlotCost + recentOpponentCost + outOfRangeCost


function calcTimeSlotCost(slotA, slotB):
  if slotA == slotB: return 0.0
  if slotA == 'ANY' or slotB == 'ANY': return 0.1
  // 인접 시간대 (MORNING-AFTERNOON, AFTERNOON-EVENING)
  adjacent = {MORNING: AFTERNOON, AFTERNOON: [MORNING, EVENING], EVENING: AFTERNOON}
  if slotB in adjacent[slotA]: return 0.25
  return 0.4  // 완전 불일치
```

### 5.3 연패 보호 — 유효 레이팅 계산

```
/**
 * 매칭용 유효 레이팅 계산
 * 실제 레이팅에는 영향 없음 — 매칭 비용 계산에서만 사용
 */

function getEffectiveRating(request):
  baseRating = request.glickoRating

  // 연패 보호: 3연패 이상이면 -50 적용
  if request.lossStreak >= 3:
    return max(100, baseRating - 50)

  return baseRating
```

### 5.4 헝가리안 알고리즘 구현 (의사코드)

```
/**
 * 최소 비용 완전 매칭 (헝가리안 알고리즘)
 * 입력: 대기 요청 목록 (짝수면 전부, 홀수면 마지막 1명 제외)
 * 출력: 최적 페어 목록
 *
 * 구현 참고: https://en.wikipedia.org/wiki/Hungarian_algorithm
 * n <= 50 수준에서는 단순한 이분 매칭 또는 Jonker-Volgenant 사용 가능
 */

function findOptimalPairs(requests):
  n = len(requests)
  if n < 2: return []

  // 홀수이면 마지막 1명 제외 (가장 짧게 기다린 사람 유지)
  // 실제로는 대기 시간이 가장 짧은 사람을 제외 → 다음 사이클에서 매칭 우선
  if n % 2 == 1:
    requests = requests[:-1]  // 최신 요청 1명 제외

  n = len(requests)  // 이제 짝수

  // n×n 비용 행렬 구성
  // 단, 매칭은 이분 그래프가 아니라 일반 그래프이므로
  // (i,j) == (j,i)인 대칭 행렬
  cost = n×n 행렬, 초기값 INF

  for i in 0..n-1:
    for j in i+1..n-1:
      c = matchingCost(requests[i], requests[j])
      cost[i][j] = c
      cost[j][i] = c  // 대칭

  // 최소 가중치 완전 매칭 (General Matching)
  // Blossom 알고리즘이 정확하나, 실용적으로는 n<=50에서
  // 단순 재귀 탐색 + memoization으로 충분
  pairs = minWeightMatching(cost, n)

  // 비용 999 이상인 페어는 매칭 불가 → 제거
  validPairs = pairs.filter(pair => cost[pair[0]][pair[1]] < 999.0)

  return validPairs


/**
 * 단순 최소 비용 완전 매칭 (Blossom 경량 대안)
 * n <= 30 수준에서 실용적
 */

function minWeightMatching(cost, n):
  matched = boolean 배열, 크기 n, 초기값 false
  result = []

  // 그리디하게 최소 비용 쌍 반복 선택
  // (Blossom 알고리즘 대신 단순 그리디 — 완전 최적은 아니지만 충분히 좋음)
  while 매칭 안 된 요청이 2개 이상:
    bestI, bestJ = -1, -1
    bestCost = INF

    for i in unmatched:
      for j in unmatched where j > i:
        if cost[i][j] < bestCost:
          bestCost = cost[i][j]
          bestI = i
          bestJ = j

    if bestI == -1 or bestCost >= 999.0: break
    result.append((bestI, bestJ))
    matched[bestI] = true
    matched[bestJ] = true

  return result
```

> **구현 노트**: 완전한 헝가리안(Blossom) 알고리즘은 구현 복잡도가 높다. 핀 당 동시 대기 인원이 현실적으로 10~20명이면 위의 그리디 반복 방식으로 실질적으로 동일한 결과를 낸다. 실제 운영에서 문제가 생기면 `minCostFlow` 라이브러리 도입을 검토한다.

### 5.5 V2 매칭 큐 워커 전체 흐름

```
/**
 * processMatchingQueue() V2 — 전체 흐름
 */

async function processMatchingQueue():
  // 1. 모든 WAITING 상태 요청 조회
  //    + glickoRating, glickoRd, lossStreak JOIN
  waitingRequests = await queryWaitingRequests()

  if waitingRequests.length == 0: return

  // 2. (pinId, sportType) 기준 그룹핑
  groups = groupBy(waitingRequests, req => `${req.pinId}::${req.sportType}`)

  matchedIds = new Set()

  for each [groupKey, requests] in groups:
    available = requests.filter(r => r.id not in matchedIds)
    if available.length < 2: continue

    // 3. 최근 상대 정보 조회 (24시간 이내)
    recentOpponents = await queryRecentOpponents(
      profileIds: available.map(r => r.sportsProfileId),
      since: now - 24h
    )

    // 4. 배치 게임 여부에 따른 MMR 범위 조정
    //    각 request에 isPlacement 플래그 포함 (JOIN으로 가져옴)

    // 5. 최적 페어 탐색
    pairs = findOptimalPairs(available, recentOpponents)

    // 6. 각 페어에 대해 트랜잭션으로 매칭 생성
    for each (reqA, reqB) in pairs:
      if reqA.id in matchedIds or reqB.id in matchedIds: continue

      await createMatchTransaction(reqA, reqB)
      matchedIds.add(reqA.id)
      matchedIds.add(reqB.id)

      // 7. 최근 상대 기록 업데이트
      await upsertRecentOpponents(reqA.sportsProfileId, reqB.sportsProfileId)

      // 8. 양측 알림
      await publishMatchNotification(reqA.requesterId, reqB.requesterId)
```

---

## 6. 부가 로직

### 6.1 최근 상대 제외

**규칙**: 24시간 이내에 매칭된 상대와는 재매칭하지 않는다. 단, 대기 풀이 2명뿐이라면 예외적으로 매칭한다.

```typescript
// matching-queue.worker.ts 수정

async function queryRecentOpponents(
  profileIds: string[],
  since: Date,
): Promise<Map<string, Set<string>>> {
  const rows = await AppDataSource.query<
    { sportsProfileId: string; opponentId: string }[]
  >(
    `SELECT sports_profile_id AS "sportsProfileId", opponent_id AS "opponentId"
     FROM recent_opponents
     WHERE sports_profile_id = ANY($1)
       AND matched_at > $2`,
    [profileIds, since],
  );

  const map = new Map<string, Set<string>>();
  for (const row of rows) {
    if (!map.has(row.sportsProfileId)) map.set(row.sportsProfileId, new Set());
    map.get(row.sportsProfileId)!.add(row.opponentId);
  }
  return map;
}

function isRecentOpponent(
  profileIdA: string,
  profileIdB: string,
  recentOpponentsMap: Map<string, Set<string>>,
): boolean {
  return (
    recentOpponentsMap.get(profileIdA)?.has(profileIdB) ||
    recentOpponentsMap.get(profileIdB)?.has(profileIdA) ||
    false
  );
}
```

**최근 상대 업데이트 (매칭 생성 시):**

```typescript
async function upsertRecentOpponents(
  profileIdA: string,
  profileIdB: string,
  manager: EntityManager,
): Promise<void> {
  // UPSERT — 이미 있으면 matched_at 갱신
  await manager.query(
    `INSERT INTO recent_opponents (sports_profile_id, opponent_id, matched_at)
     VALUES ($1, $2, NOW()), ($2, $1, NOW())
     ON CONFLICT (sports_profile_id, opponent_id)
     DO UPDATE SET matched_at = NOW()`,
    [profileIdA, profileIdB],
  );

  // 각 유저당 최근 5명만 유지 (오래된 것 삭제)
  await manager.query(
    `DELETE FROM recent_opponents
     WHERE sports_profile_id = $1
       AND id NOT IN (
         SELECT id FROM recent_opponents
         WHERE sports_profile_id = $1
         ORDER BY matched_at DESC
         LIMIT 5
       )`,
    [profileIdA],
  );
  await manager.query(
    `DELETE FROM recent_opponents
     WHERE sports_profile_id = $2
       AND id NOT IN (
         SELECT id FROM recent_opponents
         WHERE sports_profile_id = $2
         ORDER BY matched_at DESC
         LIMIT 5
       )`,
    [profileIdB],
  );
}
```

### 6.2 연패 보호

**규칙**: 연속 3패 이상이면 매칭 시 유효 레이팅에서 -50을 적용한다. 더 낮은 레이팅 상대와 매칭될 확률을 높인다.

**연패 카운터 관리:**

```typescript
// games.service.ts applyRatingChanges() 내부

// 요청자 연패 업데이트
if (resultForRequester === 'WIN') {
  updates.lossStreak = 0;
  updates.winStreak = () => 'win_streak + 1';
} else if (resultForRequester === 'LOSS') {
  updates.lossStreak = () => 'loss_streak + 1';
  updates.winStreak = 0;
} else {
  // DRAW: 연패 초기화
  updates.lossStreak = 0;
  updates.winStreak = 0;
}
```

**연패 보호 적용 (매칭 비용 계산 시):**

```typescript
function getEffectiveRating(req: WaitingRequest): number {
  const base = req.glickoRating;
  if (req.lossStreak >= 3) {
    return Math.max(100, base - 50);
  }
  return base;
}
```

### 6.3 배치 게임 MMR 범위

```typescript
function getMMRRange(waitMinutes: number, isPlacement: boolean): number {
  if (isPlacement) return 500;  // 배치 게임: 고정 ±500

  // 일반: 기존 로직 유지
  if (waitMinutes <= 2) return 100;
  if (waitMinutes <= 5) return 200;
  if (waitMinutes <= 10) return 300;
  return 500;
}
```

---

## 7. API 변경 사항

### 7.1 SportsProfile 응답 변경

**GET /profiles/me** 및 **GET /profiles/:userId** 응답에 Glicko-2 관련 필드 추가:

```typescript
// 현행 응답
{
  currentScore: 1250,
  tier: "GOLD",
  gamesPlayed: 42,
  wins: 25,
  losses: 17,
  winStreak: 3,
  ...
}

// V2 응답 (배치 완료 후)
{
  currentScore: 1250,        // Glicko-2 rating과 동기화됨
  tier: "GOLD",
  gamesPlayed: 42,
  wins: 25,
  losses: 17,
  winStreak: 3,
  lossStreak: 0,             // 신규
  isPlacement: false,        // 신규
  glicko: {                  // 신규 — 상세 Glicko-2 정보
    rating: 1250.4,
    rd: 87.3,                // RD가 낮을수록 신뢰도 높음
    volatility: 0.058,
    confidence: "HIGH"       // rd < 100: HIGH, < 200: MEDIUM, else: LOW
  }
}

// V2 응답 (배치 중)
{
  gamesPlayed: 3,
  isPlacement: true,
  placementProgress: "3/5",  // 신규 — 앱 표시용
  // currentScore, tier, glicko 필드 응답에서 제거 또는 null 처리
  currentScore: null,
  tier: null,
  glicko: null,
  ...
}
```

**주의**: 배치 중인 유저의 실제 점수를 API에서 완전히 숨기려면, 서비스 레이어에서 `isPlacement` 조건에 따라 필드를 마스킹해야 한다. 본인 프로필 조회 시에도 숨기는 방식을 권장한다 (자기 점수를 알면 상대 점수 추정이 가능하므로).

### 7.2 ScoreHistory 응답 변경

**GET /profiles/me/score-history**:

```typescript
// V2 추가 필드
{
  id: "...",
  changeType: "GAME_WIN",
  scoreBefore: 1230,
  scoreChange: 18,
  scoreAfter: 1248,
  rdBefore: 95.2,      // 신규
  rdAfter: 87.3,       // 신규
  isPlacementGame: false,  // 신규
  ...
}
```

### 7.3 매칭 요청 API 변경

**POST /matching/requests** — 요청 바디 변경 없음. 서버 내부에서 `isPlacement` 기반 MMR 범위 자동 적용.

**GET /matching/requests/:id/status** — 추가 필드:

```typescript
{
  status: "WAITING",
  waitMinutes: 3.5,
  mmrRange: 500,          // 현재 적용 중인 MMR 범위
  isPlacementMode: true,  // 배치 게임 모드 여부 (앱 표시용)
}
```

### 7.4 게임 결과 응답 변경

**POST /games/:id/confirm** 응답에 배치 완료 여부 추가:

```typescript
// V2 추가
{
  status: "VERIFIED",
  isCasual: false,
  placementCompleted: true,   // 신규 — 5번째 게임 완료 시 true
  ratingChange: +18,           // 신규 — Glicko-2 변동량
  newRating: 1248,             // 신규
  message: "5번의 배치 게임이 완료되었습니다! 당신의 레이팅: 1248점"
}
```

### 7.5 신규 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/profiles/:id/rating-history` | Glicko-2 상세 이력 (RD 변화 포함) |
| GET | `/matching/pool/:pinId/:sport` | 현재 핀의 대기 인원 수 (익명) |

---

## 8. 앱 UI 변경 사항

### 8.1 프로필 화면 — 레이팅 표시

**배치 중:**
```
┌─────────────────────────┐
│  [?] 배치 게임 진행 중  │
│                         │
│  ████░░░░░  3/5         │
│  배치 완료 후 레이팅    │
│  공개됩니다             │
└─────────────────────────┘
```

**배치 완료:**
```
┌─────────────────────────┐
│  GOLD III               │
│  1,250점                │
│  ████████░░ 80%         │
│  다음 티어까지 50점     │
└─────────────────────────┘
```

**변경 항목:**
- `ProfileScreen` — `isPlacement` 조건 분기 추가
- `RatingWidget` — 배치 중 / 일반 모드 상태 렌더링
- 배치 진행 바 (`PlacementProgressBar`) 신규 위젯 추가

### 8.2 매칭 대기 화면

**배치 게임 모드 표시:**
```
┌─────────────────────────┐
│  매칭 중...             │
│  ◉ 배치 게임 모드       │
│  (넓은 범위에서 매칭)   │
│                         │
│  대기 시간: 00:45       │
└─────────────────────────┘
```

**변경 항목:**
- `MatchingWaitingScreen` — `isPlacementMode` 플래그 수신 (API `/matching/requests/:id/status`)
- 배치 모드 배지 추가

### 8.3 게임 결과 화면

**배치 완료 시 특별 화면:**
```
┌─────────────────────────┐
│  배치 완료!             │
│  🎉                     │
│  당신의 레이팅: 1,248점 │
│  티어: GOLD III         │
│                         │
│     [확인]              │
└─────────────────────────┘
```

**일반 결과 화면 (Glicko-2 변동량 표시):**
```
┌─────────────────────────┐
│  경기 결과 인증 완료    │
│                         │
│  레이팅: 1,230 → 1,248  │
│           (+18)         │
│                         │
│  GOLD III ████████░░    │
└─────────────────────────┘
```

**변경 항목:**
- `GameResultScreen` — `placementCompleted`, `ratingChange`, `newRating` 필드 처리
- `PlacementCompleteDialog` 신규 다이얼로그 위젯 추가
- 레이팅 변동 애니메이션 추가 (숫자 카운트업/다운)

### 8.4 상대 프로필 — 배치 중 유저 표시

매칭 상대가 배치 중인 경우 레이팅 대신 "배치 중" 표시:

```
[상대방]
닉네임: 테니스왕
레이팅: 배치 중 (2/5)
```

---

## 9. TODO 및 구현 계획

### Phase 1 — DB 마이그레이션 및 Glicko-2 코어 (예상 소요: 2~3일)

- [ ] **[DB-001]** 마이그레이션 SQL 작성 및 검증
  - [ ] `sports_profiles` 컬럼 추가 (glicko_rating, glicko_rd, glicko_volatility, glicko_last_updated_at, is_placement, loss_streak)
  - [ ] `score_histories` 컬럼 추가 (rd_before, rd_after, volatility_before, volatility_after, is_placement_game)
  - [ ] `recent_opponents` 테이블 생성
  - [ ] 기존 유저 데이터 초기화 SQL (games_played 기반 RD 설정, is_placement 갱신)

- [ ] **[ENTITY-001]** TypeORM 엔티티 업데이트
  - [ ] `SportsProfile` 엔티티에 Glicko-2 컬럼 추가
  - [ ] `ScoreHistory` 엔티티에 Glicko-2 컬럼 추가
  - [ ] `RecentOpponent` 엔티티 신규 생성

- [ ] **[UTIL-001]** `glicko2.ts` 유틸리티 구현
  - [ ] `updateGlicko2(player, opponents, tau)` 함수 — Glicko-2 핵심 알고리즘
  - [ ] `applyRdDecay(player, now)` 함수 — 비활동 RD 감쇠
  - [ ] 단위 테스트 작성 (Mark Glickman 예제 데이터로 검증)
    - 참고: http://www.glicko.net/glicko/glicko2.pdf 예시 데이터 (μ=1500, φ=200, σ=0.06, 3경기 후 μ'=1464.06, φ'=151.52, σ'=0.05999)

- [ ] **[GAME-001]** `games.service.ts` — ELO → Glicko-2 전환
  - [ ] `applyEloChanges()` → `applyRatingChanges()` 리팩토링
  - [ ] `glicko2.ts` 연동
  - [ ] `current_score` 동기화 (Glicko-2 rating → 반올림)
  - [ ] `ScoreHistory` 저장 시 RD/volatility 컬럼 포함
  - [ ] 배치 완료 감지 및 `is_placement = false` 업데이트
  - [ ] 연패 카운터 (`loss_streak`) 업데이트 로직
  - [ ] `placementCompleted` 플래그 응답 포함

### Phase 2 — 안정 매칭 알고리즘 (예상 소요: 2일)

- [ ] **[WORKER-001]** `matching-queue.worker.ts` 전면 개편
  - [ ] SQL 쿼리에 `glicko_rating`, `glicko_rd`, `loss_streak`, `is_placement` JOIN 추가
  - [ ] `getEffectiveRating()` 함수 구현 (연패 보호 -50)
  - [ ] `getMMRRange()` 함수 수정 (is_placement 파라미터 추가)
  - [ ] `queryRecentOpponents()` 함수 구현
  - [ ] `matchingCost()` 비용 함수 구현
  - [ ] `findOptimalPairs()` 그리디 최소 비용 매칭 구현
  - [ ] 매칭 생성 트랜잭션에 `upsertRecentOpponents()` 포함
  - [ ] 배치 게임 케이스 테스트 (양측 모두 배치, 한쪽만 배치, 양측 일반)

- [ ] **[WORKER-002]** `recent_opponents` 정리 크론 추가
  - [ ] 24시간 이상 된 `recent_opponents` 레코드 주기적 삭제 (일 1회면 충분)
  - [ ] PM2 ecosystem 설정에 크론 워커 추가 또는 기존 ranking-refresh.worker에 통합

### Phase 3 — API 및 스키마 응답 변경 (예상 소요: 1~2일)

- [ ] **[API-001]** 프로필 API 응답 업데이트
  - [ ] `isPlacement`, `lossStreak` 필드 추가
  - [ ] `glicko` 객체 추가 (rating, rd, volatility, confidence)
  - [ ] 배치 중 유저 레이팅 마스킹 로직 추가

- [ ] **[API-002]** 게임 결과 API 응답 업데이트
  - [ ] `placementCompleted`, `ratingChange`, `newRating` 필드 추가

- [ ] **[API-003]** 매칭 요청 상태 API 업데이트
  - [ ] `mmrRange`, `isPlacementMode` 필드 추가

- [ ] **[API-004]** Score History API 업데이트
  - [ ] `rdBefore`, `rdAfter`, `isPlacementGame` 필드 추가

### Phase 4 — 앱 UI 변경 (예상 소요: 2~3일)

- [ ] **[APP-001]** `RatingWidget` 업데이트
  - [ ] `isPlacement` 조건 분기 (배치 중 표시 vs 실제 레이팅 표시)
  - [ ] `PlacementProgressBar` 위젯 신규 작성

- [ ] **[APP-002]** `MatchingWaitingScreen` 업데이트
  - [ ] 배치 게임 모드 배지 표시
  - [ ] `/matching/requests/:id/status`의 `isPlacementMode` 필드 반영

- [ ] **[APP-003]** `GameResultScreen` 업데이트
  - [ ] `placementCompleted` 시 `PlacementCompleteDialog` 표시
  - [ ] 레이팅 변동 표시 (이전 → 이후, 변동량)
  - [ ] 배치 중 게임 결과 화면 ("배치 게임 N/5 완료")

- [ ] **[APP-004]** 상대 프로필에서 배치 중 유저 처리
  - [ ] `isPlacement: true`인 상대는 레이팅 대신 "배치 중 (N/5)" 표시

### Phase 5 — 검증 및 배포 (예상 소요: 1일)

- [ ] **[TEST-001]** Glicko-2 알고리즘 단위 테스트
  - [ ] Mark Glickman 공식 예제 데이터로 수치 검증
  - [ ] RD 감쇠 경계값 테스트 (0일, 29일, 30일, 90일)
  - [ ] 배치 완료 경계 테스트 (4경기 후 vs 5경기 후)

- [ ] **[TEST-002]** 매칭 알고리즘 테스트
  - [ ] 최근 상대 제외 동작 검증
  - [ ] 연패 보호 유효 레이팅 계산 검증
  - [ ] 배치 게임 MMR 범위 ±500 동작 검증
  - [ ] 홀수 대기 인원 처리 검증

- [ ] **[DEPLOY-001]** 배포
  - [ ] RDS에 마이그레이션 실행 (기존 데이터 무중단)
  - [ ] 서버 배포 (deploy.sh 실행)
  - [ ] 배포 후 glicko_rating = current_score 동기화 확인
  - [ ] 매칭 큐 워커 로그 확인 (10초 간격 정상 동작)

---

## 10. 마이그레이션 전략

### 10.1 데이터 마이그레이션 원칙

1. **무중단**: 컬럼 추가는 `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`로 안전하게
2. **하위 호환**: `current_score` 유지, Glicko-2 rating과 동기화
3. **기존 유저 처리**: games_played 기준으로 초기 RD 설정 (많이 플레이한 유저 = 낮은 RD)
4. **배치 플래그**: 기존 유저 중 games_played < 5인 경우 `is_placement = true` (극소수)

### 10.2 점수 스케일 불일치 주의

현행 `current_score` 기본값은 1000, Glicko-2 기본값은 1500이다. 마이그레이션 시 **현재 current_score를 그대로 glicko_rating에 복사**한다. 즉, 유저의 현재 점수 체계(1000 기준)를 Glicko-2 rating으로 그대로 사용한다.

이렇게 하면:
- 기존 티어 경계(IRON: 0~899, BRONZE: 900~1099 등)가 그대로 유지된다
- Glicko-2 "표준 1500" 기준과는 다르지만, 이 시스템에서는 1000 기준으로 재정의한 것으로 간주한다
- 신규 유저 기본값은 `glicko_rating = 1000`, `glicko_rd = 350`, `glicko_volatility = 0.06`으로 변경 (기존 1000 유지)

### 10.3 롤백 계획

Glicko-2 전환 후 문제 발생 시:
1. `current_score`는 항상 동기화 유지했으므로 `applyEloChanges()` 복원만으로 롤백 가능
2. Glicko-2 컬럼은 삭제하지 않고 무시하면 됨 (워커 코드만 이전 버전으로 복원)
3. `recent_opponents` 테이블은 영향 없이 유지

### 10.4 모니터링 포인트

배포 후 다음 메트릭을 확인한다:

| 메트릭 | 정상 범위 | 확인 방법 |
|--------|-----------|-----------|
| 매칭 성공률 | 이전과 유사 또는 향상 | 매칭 큐 로그 |
| 평균 대기 시간 | 10분 이내 | 매칭 큐 워커 로그 |
| glicko_rd 분포 | 대부분 50~200 범위 | DB 쿼리 |
| recent_opponents 테이블 크기 | 24시간 내 안정화 | DB 모니터링 |
| 배치 완료 유저 비율 | 신규 유저의 게임 활성도에 비례 | 집계 쿼리 |

```sql
-- 모니터링 쿼리 예시
SELECT
  sport_type,
  count(*) AS total,
  count(*) FILTER (WHERE is_placement) AS in_placement,
  avg(glicko_rd) AS avg_rd,
  min(glicko_rd) AS min_rd,
  max(glicko_rd) AS max_rd
FROM sports_profiles
WHERE is_active = true
GROUP BY sport_type;
```

---

## 부록 A — Glicko-2 검증 테스트 케이스

Mark Glickman의 공식 예제 (http://www.glicko.net/glicko/glicko2.pdf):

```
입력:
  플레이어: μ=1500, φ=200, σ=0.06
  상대1: μ_j=1400, φ_j=30, 결과=승
  상대2: μ_j=1550, φ_j=100, 결과=패
  상대3: μ_j=1700, φ_j=300, 결과=패

기대 출력:
  μ'  = 1464.06
  φ'  = 151.52
  σ'  = 0.05999
```

단위 테스트에서 이 값과의 오차가 ±0.01 이내여야 통과.

## 부록 B — 관련 파일 위치

| 파일 | 역할 |
|------|------|
| `server/src/shared/utils/glicko2.ts` | Glicko-2 알고리즘 (신규) |
| `server/src/shared/utils/elo.ts` | 기존 ELO (유지, 캐주얼 게임 참조용) |
| `server/src/workers/matching-queue.worker.ts` | 매칭 큐 워커 (전면 수정) |
| `server/src/modules/games/games.service.ts` | 게임 결과 처리 (applyRatingChanges 수정) |
| `server/src/entities/sports-profile.entity.ts` | SportsProfile 엔티티 (컬럼 추가) |
| `server/src/entities/score-history.entity.ts` | ScoreHistory 엔티티 (컬럼 추가) |
| `server/src/entities/recent-opponent.entity.ts` | RecentOpponent 엔티티 (신규) |
| `server/src/modules/profiles/` | 프로필 API 응답 수정 |
| `server/src/modules/games/games.schema.ts` | 게임 결과 응답 스키마 수정 |
