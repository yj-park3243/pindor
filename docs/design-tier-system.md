# 등급(티어) 시스템 재설계

> 작성일: 2026-04-04

## 1. 현행 시스템

| 티어 | 최소 점수 | 퍼센타일 기준 |
|------|-----------|---------------|
| GRANDMASTER | 1800 | 상위 1% |
| MASTER | 1650 | 상위 3% |
| PLATINUM | 1500 | 상위 10% |
| GOLD | 1300 | 상위 30% |
| SILVER | 1100 | 상위 60% |
| BRONZE | 900 | 상위 80% |
| IRON | 0~899 | 하위 20% |

- 7단계, 각 단계 내 세분화 없음
- 초기 점수: 1000 (BRONZE)
- 골프 G핸디 → ELO 변환 지원 (0핸디=1800, 54핸디=800)

## 2. 개편안: 등급별 3세부단계

### 2.1 세부단계 구조

각 티어를 **I (하위) → II (중위) → III (상위)** 3단계로 분리.
총 **7티어 x 3 = 21단계**.

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
| **IRON** | III | 800~899 | 900 |
| | II | 700~799 | 800 |
| | I | 0~699 | 700 |

### 2.2 "승급까지 N점" 표시

```
현재: GOLD II (1,385점)
다음 단계: GOLD III까지 45점 필요
━━━━━━━━━━━━━━━━━░░░░ 64%
```

**계산 로직:**
```typescript
function getPromotionInfo(score: number) {
  const { tier, subTier, rangeMin, rangeMax } = getTierDetails(score);
  const nextThreshold = rangeMax + 1; // 다음 세부단계 최소 점수
  const pointsNeeded = nextThreshold - score;
  const progress = (score - rangeMin) / (rangeMax - rangeMin + 1);
  
  return { tier, subTier, pointsNeeded, progress };
}
```

### 2.3 DB 스키마 변경

**방법 A (권장): subTier 필드 추가**
```prisma
model SportsProfile {
  // 기존
  tier         Tier
  // 추가
  subTier      Int     @default(1) @map("sub_tier") // 1, 2, 3
}
```

**방법 B: Tier enum 확장** (비권장 - enum 값이 21개로 증가)

### 2.4 강등 보호 개선

현행: 티어 경계에서 3게임 유예
개편안: 세부단계 강등은 즉시, **대티어 강등만 3게임 유예**

예시:
- GOLD III → GOLD II: 즉시 강등 (점수 기준)
- GOLD I → SILVER III: 3게임 유예 적용

## 3. 구현 계획

### 3.1 서버 변경
1. `elo.ts`에 `calculateSubTier(score)` 함수 추가
2. `calculateTierWithBuffer()` 수정 — 대티어 강등만 유예
3. `SportsProfile` 모델에 `subTier` 필드 추가
4. 기존 유저 데이터 마이그레이션 (score 기반으로 subTier 자동 계산)

### 3.2 API 변경
- `GET /users/me` 응답에 `subTier`, `pointsToNext`, `progress` 추가
- `GET /rankings/*` 응답에 세부단계 표시

### 3.3 클라이언트 변경
- 프로필 화면: 세부단계 표시 + 프로그레스바
- 매칭 결과 화면: 점수 변동 + 승급/강등 애니메이션
- 랭킹 화면: 세부단계 뱃지

## 4. 세부단계 계산 함수 (의사코드)

```typescript
interface TierInfo {
  tier: Tier;
  subTier: 1 | 2 | 3;  // I=1, II=2, III=3
  rangeMin: number;
  rangeMax: number;
  nextThreshold: number | null; // GRANDMASTER III는 null
  pointsToNext: number | null;
  progress: number; // 0.0 ~ 1.0
}

const TIER_RANGES = [
  { tier: 'IRON',         base: 0,    width: [700, 100, 100] },  // I:0-699, II:700-799, III:800-899
  { tier: 'BRONZE',       base: 900,  width: [60, 70, 70] },     // I:900-959, II:960-1029, III:1030-1099
  { tier: 'SILVER',       base: 1100, width: [60, 70, 70] },
  { tier: 'GOLD',         base: 1300, width: [60, 70, 70] },
  { tier: 'PLATINUM',     base: 1500, width: [50, 50, 50] },
  { tier: 'MASTER',       base: 1650, width: [50, 50, 50] },
  { tier: 'GRANDMASTER',  base: 1800, width: [50, 50, Infinity] },
];

function getTierInfo(score: number): TierInfo {
  // 점수 → 티어 + 세부단계 매핑
  for (const range of TIER_RANGES.reverse()) {
    if (score >= range.base) {
      let offset = score - range.base;
      for (let sub = 0; sub < 3; sub++) {
        if (offset < range.width[sub] || sub === 2) {
          const rangeMin = range.base + range.width.slice(0, sub).reduce((a,b) => a+b, 0);
          const rangeMax = rangeMin + range.width[sub] - 1;
          const nextThreshold = sub < 2 ? rangeMax + 1 : 
            (range !== TIER_RANGES[0] ? range.base + range.width.reduce((a,b)=>a+b,0) : null);
          
          return {
            tier: range.tier,
            subTier: (sub + 1) as 1 | 2 | 3,
            rangeMin,
            rangeMax: Math.min(rangeMax, 9999),
            nextThreshold,
            pointsToNext: nextThreshold ? nextThreshold - score : null,
            progress: offset / range.width[sub],
          };
        }
        offset -= range.width[sub];
      }
    }
  }
  return { tier: 'IRON', subTier: 1, rangeMin: 0, rangeMax: 699, nextThreshold: 700, pointsToNext: 700 - score, progress: score / 700 };
}
```
