# 매칭 알고리즘 설계

> 작성일: 2026-04-04

## 1. 참고 알고리즘/논문

### 1.1 ELO 레이팅 시스템 (현행)
- **원본**: Arpad Elo, 1960. 체스 레이팅 시스템 (FIDE)
- **수식**: `E_A = 1 / (1 + 10^((R_B - R_A) / 400))`, `R'_A = R_A + K * (S_A - E_A)`
- **K-팩터 (FIDE 기준)**: 신규 K=40, 일반 K=20, 고수(2400+) K=10
- **한계**: 레이팅 불확실성(confidence) 미반영, 비활성 유저 처리 어려움, 팀 게임 부적합, 점수 인플레이션

### 1.2 Glicko-2
- **논문**: Mark Glickman, "The Glicko-2 Rating System" (2001, Boston University)
- **3개 파라미터**: mu(실력 추정, 기본 1500) + phi/RD(레이팅 편차/신뢰도) + sigma(변동성)
- RD가 높으면(오래 미활동) → 변동폭 커짐. RD가 낮으면(많이 플레이) → 변동폭 작아짐
- 시스템 상수 τ(tau): 0.3~1.2 적정
- **사용**: Chess.com, Lichess, CS2, Dota 2, Pokemon Showdown
- **라이선스**: 퍼블릭 도메인 (무료)

### 1.3 Microsoft TrueSkill / TrueSkill 2
- **논문**: Herbrich et al., "TrueSkill: A Bayesian Skill Rating System" (2007, Microsoft Research)
- **2개 파라미터**: mu(실력 평균, 기본 25) + sigma(불확실성, 기본 8.33)
- **표시 레이팅**: `Rating = mu - 3*sigma` (99.7% 신뢰 구간 하한)
- 팩터 그래프 + 기대 전파(EP) 기반, **다인수 팀 매치 지원**
- TrueSkill 2 (2018): 개인 성과, 파티 멤버십, 이탈 경향 반영. 예측 정확도 68% (1세대 52%)
- 스머프 탐지: **약 5경기** 만에 정확한 등급 배치 (기존 대비 3배 빠름)
- **주의**: Microsoft 특허 보유 (상업적 사용 시 라이선스 필요)

### 1.4 OpenSkill (Weng-Lin) - **추천**
- **논문**: Weng & Lin, "A Bayesian Approximation Method for Online Ranking" (2011)
- TrueSkill과 유사한 베이지안 기반이지만 **오픈소스 (라이선스 무료)**
- **npm 패키지** `openskill` 존재 → Node.js/Fastify 즉시 적용 가능
- 5종 모델 중 **Plackett-Luce** 모델이 가장 범용적
- 1v1 + 팀 매치 모두 지원, TrueSkill 대비 3배 빠른 연산
- **Spots 플랫폼에 가장 적합**: 오픈소스 + Node.js + 팀매칭

### 1.5 League of Legends MMR 시스템 (실전 참고)
- 숨겨진 MMR + 표시용 LP(League Points) 이중 구조
- 매칭은 MMR 기반, 표시는 LP/티어 기반
- 승률 50%에 수렴하도록 매칭 조절
- 연승/연패 보너스로 빠른 배치 조정
- MMR > 표시 랭크: LP 획득량 증가 → 빠른 승급 유도
- 스머프/부스터/봇 탐지 시스템 (2025 Riot 발표)

### 1.6 핵심 학술 참고 자료
| 자료 | 출처 |
|------|------|
| Glicko-2 공식 문서 | glicko.net/glicko/glicko2.pdf |
| TrueSkill 2 논문 | Microsoft Research (2018) |
| Elo-MMR 대규모 랭킹 | Stanford CS (2021) |
| 팀 스킬 집계 평가 | arxiv.org/abs/2106.11397 |
| OpenSkill 논문 | arxiv.org/html/2401.05451v1 |
| MOBA ELO 분석 | arxiv.org/pdf/2310.13719 |

### 1.7 추천 마이그레이션 로드맵
1. **Phase 1 (현재)**: 기본 ELO — 이미 구현됨, MVP용
2. **Phase 2**: OpenSkill로 전환 — `npm install openskill`, 팀매칭 지원, 불확실성 처리
3. **Phase 3**: 위치/일정 가중 매칭, 이탈 패널티, 스머프 감지

## 2. Spots 매칭 알고리즘 설계

### 2.1 매칭 모드 분류

| 모드 | 설명 | MMR 적용 | 전적 반영 |
|------|------|----------|-----------|
| **랭크 매칭** | 실력 기반 공정 매칭 | O | O (ELO 변동) |
| **연습 매칭** (신규) | 부담 없는 캐주얼 | 별도 MMR | X (전적만 기록) |
| **팀 매칭** | 팀 vs 팀 | 팀 평균 MMR | O (개인+팀 ELO) |

### 2.2 핀 기반 매칭 원칙

> **핵심: 위치 기반 매칭이 아니라, 핀 기반 매칭이다.**
>
> - GPS 위치는 "가까운 핀 찾기"에만 사용
> - 매칭은 유저가 **직접 선택한 핀**에서 이루어짐
> - 팀도 핀 소속, 게시판도 핀 소속
> - 유저는 여러 핀을 "즐겨찾기"로 등록하고, 원하는 핀에 매칭 신청

**매칭 플로우:**
```
유저가 핀 선택 (강남역)
  → 종목 선택 (GOLF)
  → 매칭 요청 (시간대, 날짜)
  → 같은 핀 + 같은 종목의 대기 풀에서 매칭
```

### 2.3 매칭 스코어 함수

**같은 핀 내에서** 매칭 후보 간 적합도 점수 계산:

```
MatchScore = w_skill * SkillScore + w_time * TimeScore + w_activity * ActivityBonus
```

| 가중치 | 기본값 | 설명 |
|--------|--------|------|
| w_skill | 0.60 | 실력 차이 적합도 |
| w_time | 0.25 | 시간대 일치도 |
| w_activity | 0.15 | 활동량 보너스 |

> 위치 가중치 제거 — 같은 핀이면 이미 같은 지역이므로 불필요

#### 2.3.1 SkillScore (실력 적합도)
```typescript
function calcSkillScore(ratingA: number, ratingB: number, maxRange: number): number {
  const diff = Math.abs(ratingA - ratingB);
  if (diff > maxRange) return 0;
  return 1 - (diff / maxRange); // 0~1, 점수 차이가 적을수록 높음
}
```

#### 2.3.2 TimeScore (시간 일치도)
- 동일 시간대(MORNING/AFTERNOON/EVENING): 1.0
- ANY와 특정 시간대: 0.8
- 인접 시간대: 0.5 (MORNING-AFTERNOON, AFTERNOON-EVENING)
- 불일치: 0.0

#### 2.3.3 ActivityBonus (활동량 보너스)
```typescript
function calcActivityBonus(gamesLast30Days: number): number {
  // 30일 내 게임 수에 따른 보너스 (매칭 우선순위 가중)
  return Math.min(1.0, gamesLast30Days / 10); // 10게임 이상이면 만점
}
```

### 2.4 대기 시간에 따른 MMR 범위 확대

같은 핀 내에서 매칭 대기가 길어지면 MMR 범위를 점진적으로 확대.
**핀 확장은 하지 않음** — 유저가 다른 핀에서도 매칭하고 싶으면 직접 추가 신청해야 함.

| 대기 시간 | MMR 범위 | 설명 |
|-----------|----------|------|
| 0~2분 | ±100 | 타이트 매칭 |
| 2~5분 | ±200 | 표준 매칭 |
| 5~10분 | ±300 | 완화 매칭 |
| 10분+ | ±500 | 최대 범위 |

```typescript
function getMMRRange(waitTimeMinutes: number): number {
  if (waitTimeMinutes <= 2) return 100;
  if (waitTimeMinutes <= 5) return 100 + (waitTimeMinutes - 2) * (100/3);
  if (waitTimeMinutes <= 10) return 200 + (waitTimeMinutes - 5) * 20;
  return 500;
}
```

### 2.5 매칭 큐 워커 (BullMQ)

```
유저가 핀 선택 + 종목 + 시간 → 매칭 요청 생성
  → 해당 핀의 매칭 풀에 추가
  → 워커가 핀별로 매칭 풀 스캔 (10초 주기)
  → 같은 핀 + 같은 종목에서 MatchScore 최고 쌍 매칭
  → 양측 알림 발송 → 수락/거절 대기 (5분)
```

워커 실행 주기: **10초**마다 **핀별** 매칭 풀 스캔

```typescript
// 의사코드
async function processMatchingQueue() {
  // 핀별로 그룹화하여 처리
  const requestsByPin = await getActivePendingRequestsGroupedByPin();
  
  for (const [pinId, requests] of requestsByPin) {
    // 같은 핀 내에서만 매칭
    for (const request of requests) {
      const waitTime = getWaitTimeMinutes(request);
    const mmrRange = getMMRRange(waitTime);
    
    const candidates = await findCandidates({
      sportType: request.sportType,
      mmrMin: request.score - mmrRange,
      mmrMax: request.score + mmrRange,
      excludeUserId: request.requesterId,
      timeSlot: request.timeSlot,
      pinId: request.pinId,
    });
    
    if (candidates.length > 0) {
      // 매칭 스코어 계산 후 최적 매칭
      const scored = candidates.map(c => ({
        ...c,
        matchScore: calcMatchScore(request, c),
      }));
      scored.sort((a, b) => b.matchScore - a.matchScore);
      
      await createMatch(request, scored[0]);
    }
  }
}
```

## 3. 연습 게임 (캐주얼 모드)

### 3.1 개요
- 랭크 점수에 영향 없음
- 별도의 **Casual MMR** 사용 (매칭 품질 유지)
- 전적 기록은 별도 카운트 (casualWin/casualLoss)
- 등급/티어 무관하게 매칭 가능

### 3.2 스키마 변경
```prisma
enum RequestType {
  SCHEDULED
  INSTANT
  CASUAL     // 신규
}

model SportsProfile {
  // 기존...
  casualScore   Int     @default(1000) @map("casual_score")
  casualWin     Int     @default(0) @map("casual_win")
  casualLoss    Int     @default(0) @map("casual_loss")
}

model MatchRequest {
  // 기존...
  isCasual      Boolean @default(false) @map("is_casual")
}
```

### 3.3 캐주얼 매칭 규칙
- MMR 범위: 랭크 매칭보다 2배 넓게 (초기 ±200)
- 대기 시간 확대 속도: 랭크의 1.5배
- 승패 시 casualScore만 변동 (K=20 고정)
- 연습 게임도 핀 게시판 입장 조건 1회에 포함

## 4. 매칭 포기(노쇼) 패널티

### 4.1 포기 시나리오
| 시나리오 | 포기 판정 | 패널티 |
|----------|-----------|--------|
| 매칭 수락 후 취소 | 확정 전 취소 | 경미 (경고) |
| 매칭 확정 후 당일 취소 | 노쇼 | 중간 |
| 매칭 확정 후 불참 (무응답) | 노쇼 | 심각 |
| 게임 결과 미입력 (48시간) | 회피 | 경미 |

### 4.2 점수 패널티

```typescript
const NO_SHOW_PENALTY = {
  // 포기자 점수 변동
  forfeitScoreChange: -30,  // 고정 30점 감점
  
  // 상대방 점수 변동
  opponentScoreChange: +15, // 고정 15점 가점 (승리의 절반)
  
  // 노쇼 누적에 따른 추가 패널티
  consecutiveMultiplier: (count: number) => {
    if (count >= 3) return 2.0;  // 3회 이상 연속: 2배
    if (count >= 2) return 1.5;  // 2회 연속: 1.5배
    return 1.0;
  },
  
  // 매칭 제한
  matchBanDuration: (totalNoShows: number) => {
    if (totalNoShows >= 10) return 7 * 24 * 60; // 7일
    if (totalNoShows >= 5) return 3 * 24 * 60;  // 3일
    if (totalNoShows >= 3) return 24 * 60;       // 24시간
    return 0; // 제한 없음
  },
};
```

### 4.3 구현
```prisma
model SportsProfile {
  // 기존...
  noShowCount     Int @default(0) @map("no_show_count")
  matchBanUntil   DateTime? @map("match_ban_until") @db.Timestamptz
}
```

## 5. 활동량 보너스 (많이 하면 점수 올리기 쉬운 구조)

### 5.1 개요
"많이 플레이할수록 점수를 올릴 기회가 많다"

**절대 보너스 점수는 아님**. 대신:
- 활동 보너스 K계수 증가
- 연승 스트릭 보너스
- 일간/주간 첫 게임 보너스

### 5.2 활동 보너스 구조

#### (1) K계수 활동 가산
```typescript
function getAdjustedKFactor(base: number, gamesThisWeek: number): number {
  // 주간 3게임 이상 시 K계수 +2 (승리 시 더 많이 오름)
  // 주간 5게임 이상 시 K계수 +4
  if (gamesThisWeek >= 5) return base + 4;
  if (gamesThisWeek >= 3) return base + 2;
  return base;
}
```

#### (2) 연승 스트릭 보너스
```
2연승: +3 보너스 점수
3연승: +5 보너스 점수
5연승+: +8 보너스 점수
```

#### (3) 일간 첫 게임 보너스
- 하루 첫 게임 승리 시: +5 보너스 점수
- 효과: 매일 꾸준히 플레이하는 유저에게 유리

#### (4) 주간 목표 달성 보상
- 주 3게임 완료: 보너스 점수 +10
- 주 5게임 완료: 보너스 점수 +20
- 효과: 활동량 많은 유저에게 추가 점수 기회

### 5.3 점수 변동 최종 공식

```
최종 변동 = ELO 변동 + 연승보너스 + 일간보너스 + 주간목표보너스
```

```typescript
function calculateFinalScoreChange(params: {
  eloChange: number;       // 기본 ELO 변동
  result: 'WIN' | 'LOSS' | 'DRAW';
  winStreak: number;       // 현재 연승 수
  isFirstGameToday: boolean;
  gamesThisWeek: number;
  weeklyTargetHit: 3 | 5 | null;
}): number {
  let bonus = 0;
  
  if (params.result === 'WIN') {
    // 연승 보너스 (승리 시만)
    if (params.winStreak >= 5) bonus += 8;
    else if (params.winStreak >= 3) bonus += 5;
    else if (params.winStreak >= 2) bonus += 3;
    
    // 일간 첫 게임 보너스 (승리 시만)
    if (params.isFirstGameToday) bonus += 5;
  }
  
  // 주간 목표 (승패 무관, 완료 시점에 1회만)
  if (params.weeklyTargetHit === 5) bonus += 20;
  else if (params.weeklyTargetHit === 3) bonus += 10;
  
  return params.eloChange + bonus;
}
```

## 6. 팀 매칭 알고리즘

### 6.1 팀 MMR 계산

학술 연구(PUBG, LoL, CS:GO 데이터 10만+ 경기 분석)에 따르면:

| 집계 방법 | 정확도 | 설명 |
|-----------|--------|------|
| MAX (최대) | **가장 높음** | 팀 최고 실력자가 성과를 가장 좌우 |
| SUM (합산) | 보통 | |
| AVG (평균) | 보통 | |
| MIN (최소) | 낮음 | |

**추천 공식**: 가중 평균 (MAX + AVG 혼합)
```
Team_Skill = 0.5 * max(player_skills) + 0.5 * avg(player_skills)
```

추가 보정:
- **파티/프리메이드 보정**: 함께 플레이하는 팀은 소통 이점으로 MMR +50~100 보너스 적용
- **캡틴 가중치**: 캡틴 1.2, 부캡틴 1.1, 일반 1.0

### 6.2 팀 밸런싱 알고리즘

**그리디 밸런싱 (권장)**:
```
1. 플레이어를 MMR 내림차순 정렬
2. 각 플레이어를 현재 총 MMR이 가장 낮은 팀에 배정
3. 최종 팀간 MMR 차이 검증
```

### 6.3 팀 매칭 적합도
- 팀 MMR 차이 ±150 이내
- 인원 수 동일 (또는 ±1명 허용)
- 같은 핀 또는 인접 핀

## 7. 랭크 조작 방지

| 대책 | 구현 방법 |
|------|-----------|
| 스머프 탐지 | MMR 급상승 패턴, 승률 이상치 분석 (5게임 이내 감지) |
| 부스팅 방지 | 파티 MMR 차이 제한 (800점 이상 차이 시 파티 불가) |
| 본인 인증 | 전화번호 인증, 고랭크에서 추가 인증 |
| 신고 시스템 | "랭크 조작" 카테고리 신고 기능 |
| 빠른 배치 수렴 | OpenSkill sigma 기반 5경기 내 정확한 배치 |

## 8. 향후 고려사항

- **OpenSkill 마이그레이션**: `npm install openskill`로 즉시 적용. mu/sigma 기반으로 신규 유저 빠른 배치, 팀매칭 지원.
- **시즌 시스템**: 3개월 단위 시즌, 시즌 리셋 시 MMR 소프트 리셋 (중앙값 방향으로 30% 회귀)
- **매칭 품질 모니터링**: 매칭 후 실제 게임 진행률, 승률 분포, 유저 만족도 추적
- **MMR vs 표시 랭크 분리**: 내부 MMR은 매칭용, 표시 티어는 동기부여용. LP 시스템으로 점진적 수렴.
