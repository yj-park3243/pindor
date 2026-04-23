# 등급(티어) 시스템 설계

> 작성일: 2026-04-04
> 최종 업데이트: 2026-04-22 (코드 기반 최신화)

## 1. 티어 정의

`server/src/entities/enums.ts`의 `Tier` enum:

| 티어 | enum 값 |
|------|---------|
| IRON | `IRON` |
| BRONZE | `BRONZE` |
| SILVER | `SILVER` |
| GOLD | `GOLD` |
| PLATINUM | `PLATINUM` |
| MASTER | `MASTER` |
| GRANDMASTER | `GRANDMASTER` |

7단계 체계. `SportsProfile.tier` 필드에 저장됨 (기본값: `BRONZE`).

## 2. 티어+세부단계 (3세부단계, 구현 완료)

### 2.1 구조

각 티어를 **I (하위), II (중위), III (상위)** 3단계로 분리.
총 **7티어 x 3 = 21단계**.

`server/src/shared/utils/elo.ts`의 `getTierInfo()` 함수에 구현:

| 티어 | 세부단계 | 점수 범위 | 승급 기준점 |
|------|----------|-----------|-------------|
| **GRANDMASTER** | III | 1900+ | - |
| | II | 1850~1899 | 1900 |
| | I | 1800~1849 | 1850 |
| **MASTER** | III | 1750~1799 | 1800 |
| | II | 1700~1749 | 1750 |
| | I | 1650~1699 | 1700 |
| **PLATINUM** | III | 1600~1649 | 1650 |
| | II | 1550~1599 | 1600 |
| | I | 1500~1549 | 1550 |
| **GOLD** | III | 1430~1499 | 1500 |
| | II | 1360~1429 | 1430 |
| | I | 1300~1359 | 1360 |
| **SILVER** | III | 1230~1299 | 1300 |
| | II | 1160~1229 | 1230 |
| | I | 1100~1159 | 1160 |
| **BRONZE** | III | 1030~1099 | 1100 |
| | II | 960~1029 | 1030 |
| | I | 900~959 | 960 |
| **IRON** | III | 600~899 | 900 |
| | II | 300~599 | 600 |
| | I | 0~299 | 300 |

### 2.2 getTierInfo() 구현

```typescript
export interface TierInfo {
  tier: string;              // IRON, BRONZE, ..., GRANDMASTER
  subTier: 1 | 2 | 3;       // I=1, II=2, III=3
  rangeMin: number;
  rangeMax: number;
  nextThreshold: number | null; // null for GRANDMASTER III
  pointsToNext: number | null;
  progress: number;          // 0.0 ~ 1.0
}
```

내부적으로 21개의 서브 티어 경계를 배열로 정의하고, 점수에 해당하는 구간을 선형 탐색:

```typescript
const subTiers = [
  { tier: 'IRON', subTier: 1, rangeMin: 0, rangeMax: 299, nextThreshold: 300 },
  { tier: 'IRON', subTier: 2, rangeMin: 300, rangeMax: 599, nextThreshold: 600 },
  // ... 21개 항목
  { tier: 'GRANDMASTER', subTier: 3, rangeMin: 1900, rangeMax: Infinity, nextThreshold: null },
];
```

### 2.3 "승급까지 N점" 표시 예시

```
현재: GOLD II (1,385점)
다음 단계: GOLD III까지 45점 필요
Progress: 64%
```

### 2.4 DB 저장 방식

현재 구현에서 `subTier`는 **DB에 별도 컬럼으로 저장하지 않음**.
`sports_profiles` 테이블에는 `tier` (enum) 필드만 존재하며, 세부단계(`subTier`)와 프로그레스 정보는 `getTierInfo(score)` 함수로 점수 기반 실시간 계산.

```typescript
// SportsProfile 엔티티 (subTier 컬럼 없음)
@Column({ type: 'enum', enum: Tier, enumName: 'Tier', default: Tier.BRONZE })
tier!: Tier;
```

## 3. 티어 결정 방식 (이중 체계)

현재 두 가지 티어 결정 방식이 공존:

### 3.1 절대 점수 기반 (폴백)

`calculateTierFallback(score)` -- 유저 수가 적을 때 사용:

| 점수 범위 | 티어 |
|-----------|------|
| 1800+ | GRANDMASTER |
| 1500~1799 | PLATINUM |
| 1300~1499 | GOLD |
| 1100~1299 | SILVER |
| 900~1099 | BRONZE |
| 0~899 | BRONZE (최저) |

**참고**: IRON과 MASTER는 폴백 함수에서 반환되지 않음. 최저 티어도 BRONZE로 처리.

### 3.2 등수(퍼센타일) 기반 (기본)

`calculateTierByRank(rank, totalPlayers)` -- 랭킹 리프레시 워커에서 사용:

| 퍼센타일 | 티어 |
|----------|------|
| 상위 3% | GRANDMASTER |
| 상위 7% | MASTER |
| 상위 15% | PLATINUM |
| 상위 30% | GOLD |
| 상위 55% | SILVER |
| 상위 80% | BRONZE |
| 나머지 | IRON |

이 함수가 `ranking_entries.tier`에 반영됨. 랭킹 리프레시 워커와 매칭 결과 반영(`applyEloChanges`) 양쪽에서 사용.

## 4. ELO 점수 시스템 (구현 완료)

### 4.1 ELO 계산

`server/src/shared/utils/elo.ts`의 `calculateElo()`:

```
E_A = 1 / (1 + 10^((R_B - R_A) / 400))
새 점수 = R_A + K * (S_A - E_A)
최소 점수: 100
```

### 4.2 K 계수

`getKFactor(gamesPlayed, tier)`:

| 조건 | K 계수 |
|------|--------|
| PLATINUM 또는 GRANDMASTER 티어 | 10 |
| 첫 10게임 | 24 |
| 11~30게임 | 18 |
| 31게임 이상 | 12 |

**참고**: MASTER 티어는 K 계수 감소 대상에 포함되지 않음 (PLATINUM과 GRANDMASTER만).

### 4.3 양측 ELO 동시 계산

`calculateBothElo()`: 한 경기의 양측 점수 변동을 동시 계산.

### 4.4 골프 특수 규칙

`determineGolfWinner()`: 핸디캡 적용 순 타수(Net Score)로 승자 결정.

```
순 타수 = 타수 - 핸디캡
순 타수 낮은 쪽이 승
```

### 4.5 G핸디 -> 초기 점수 변환

`gHandicapToInitialScore(gHandicap)`:

```
선형 매핑: G핸디 0 -> 1050점, G핸디 54 -> 950점
범위: 950~1050점 (변동폭 작게 유지, 배치 게임에서 실력 반영)
```

## 5. Glicko-2 레이팅 (구현 완료)

### 5.1 개요

`server/src/shared/utils/glicko2.ts` -- ELO와 별도로 Glicko-2 시스템도 병행 운영.

**용도**: 매치메이킹 MMR 전용 (표시 점수/랭킹에는 ELO 기반 점수 사용)

### 5.2 Glicko-2 파라미터

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| rating | 1000 | 기본 레이팅 (Glicko-1 스케일) |
| rd | 350 | Rating Deviation (불확실성) |
| volatility | 0.06 | 변동성 (시스템 상수 TAU=0.5) |

```typescript
// SportsProfile 엔티티의 Glicko-2 필드
@Column({ name: 'glicko_rating', type: 'float', default: 1000.0 })
glickoRating!: number;

@Column({ name: 'glicko_rd', type: 'float', default: 350.0 })
glickoRd!: number;

@Column({ name: 'glicko_volatility', type: 'float', default: 0.06 })
glickoVolatility!: number;

@Column({ name: 'glicko_last_updated_at', type: 'timestamptz', nullable: true })
glickoLastUpdatedAt!: Date | null;
```

### 5.3 RD 감쇠

비활성 유저의 불확실성(RD)은 시간 경과에 따라 증가:

```typescript
function decayRD(rd, volatility, periodsSinceLastGame): number
// RD 상한: 350
```

## 6. 핀별 독립 점수 체계

### 6.1 동작 방식

- 각 핀+종목 조합마다 `ranking_entries` 에 독립 점수 보관
- 매칭 결과 반영 시 해당 핀의 `ranking_entries.score`를 개별 업데이트
- `sports_profiles.currentScore`는 해당 유저의 모든 `ranking_entries` 중 최고점으로 갱신

```typescript
// applyEloChanges 내부 — 핀별 독립 점수로 ELO 계산
if (match.pinId) {
  const reqPinEntry = await rankingEntryRepo.findOne({
    where: { pinId: match.pinId, sportsProfileId: requesterProfile.id, ... },
  });
  requesterBaseScore = reqPinEntry?.score ?? requesterProfile.currentScore;
}
```

### 6.2 currentScore 갱신

```typescript
// 해당 유저의 모든 ranking_entries 중 최고 점수를 currentScore로 사용
const reqMaxResult = await rankingEntryRepo
  .createQueryBuilder('re')
  .select('MAX(re.score)', 'maxScore')
  .where('re.sportsProfileId = :id AND re.sportType = :sportType', ...)
  .getRawOne();

reqNewCurrentScore = reqMaxResult?.maxScore ?? finalDisplayScoreA;
```

## 7. 강등 보호

`calculateTierWithBuffer(score, currentTier, gamesInCurrentTier)`:

- 티어 경계에서 **3게임 유예** (대티어 강등 시)
- `gamesInCurrentTier < 3` 이면 현재 티어 유지

현재 구현에서 `tierOrder`에 IRON과 MASTER가 빠져 있음:

```typescript
const tierOrder: Tier[] = [
  Tier.BRONZE,
  Tier.SILVER,
  Tier.GOLD,
  Tier.PLATINUM,
  Tier.GRANDMASTER,
];
```

## 8. SportsProfile 주요 필드

`server/src/entities/sports-profile.entity.ts`:

| 필드 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| userId | uuid | - | 사용자 ID |
| sportType | enum | - | 종목 (유저+종목 UNIQUE) |
| initialScore | int | 1000 | 초기 점수 |
| currentScore | int | 1000 | 현재 점수 (핀별 최고점) |
| displayScore | int | 1000 | 표시용 점수 |
| tier | enum | BRONZE | 현재 티어 |
| gamesPlayed | int | 0 | 총 게임 수 |
| wins / losses / draws | int | 0 | 승/패/무 |
| winStreak / lossStreak | int | 0 | 연승/연패 수 |
| casualScore | int | 1000 | 캐주얼 모드 점수 |
| casualWin / casualLoss | int | 0 | 캐주얼 승/패 |
| isPlacement | boolean | true | 배치 게임 중 여부 |
| glickoRating | float | 1000.0 | Glicko-2 레이팅 |
| glickoRd | float | 350.0 | Rating Deviation |
| glickoVolatility | float | 0.06 | 변동성 |
| gHandicap | decimal(4,1) | null | 골프 G핸디 |
| noShowCount | int | 0 | 노쇼 횟수 |
| matchBanUntil | timestamptz | null | 매칭 금지 기한 |
| mannerTotal / mannerCount | int | 0 | 매너 점수 합산/횟수 |
| recentOpponentIds | uuid[] | {} | 최근 상대 목록 |
| isActive | boolean | true | 활성 여부 |
