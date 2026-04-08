# 핀돌 매칭 시스템 최종 설계서

> 작성일: 2026-04-08
> 3명의 전문가(게임 디자이너, 백엔드 엔지니어, 데이터 사이언티스트) 토론 결과 종합

---

## 1. 전체 아키텍처

```
유저 매칭 요청 (핀 + 종목 + 타임슬롯 선택)
    │
    ▼
[매칭 요청 생성] → DB에 WAITING 상태로 저장
    │                expiresAt = 타임슬롯 마감 시간
    ▼
[매칭 큐 워커] — 10초마다 실행
    │
    ├── 1. 핀+종목별 그룹핑
    ├── 2. 각 유저의 waitRatio 계산
    ├── 3. Glicko-2 RD 기반 동적 범위 계산
    ├── 4. 비용 행렬 생성 (최적 페어링)
    ├── 5. 매칭 성사 → PENDING_ACCEPT (10분 타임아웃)
    │       ├── 양측 수락 → CHAT (게임 진행)
    │       ├── 거절 → -15점 패널티
    │       └── 10분 미응답 → 자동 취소 (미응답자 -15점)
    ├── 6. 게임 종료 → Glicko-2 레이팅 업데이트
    └── 7. 포기 → Glicko-2 풀 패배 처리

[배치 게임] — 첫 5게임 동안 점수 비공개
```

---

## 2. 레이팅 시스템: Glicko-2

### 파라미터
| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| μ (rating) | 1000 | 추정 실력 (기존 스케일 유지) |
| φ (RD) | 350 | 불확실성 (높을수록 불확실) |
| σ (volatility) | 0.06 | 성적 변동성 |
| τ (tau) | 0.5 | 시스템 상수 |

### RD 시간 감쇠
- 활동 없으면 RD가 증가 (불확실성 커짐)
- 매칭 전 `decayRD()` 호출로 반영
- RD 최대값: 350 (캡)

### 점수 동기화 / displayScore 분리

| 필드 | 역할 | 유저 노출 |
|------|------|-----------|
| `glickoRating` | 내부 MMR — 매칭 상대 탐색에만 사용 | 비공개 |
| `displayScore` | 유저에게 보이는 점수 = round(glickoRating) + 활동 보너스 | 공개 |
| `currentScore` | deprecated — displayScore와 동기화 유지, 구버전 클라이언트 호환용 | 공개 |

```
displayScore = round(glickoRating) + 활동 보너스
currentScore = displayScore  // 기존 시스템 호환
```

- 거절 시: `displayScore`만 -15점 차감, `glickoRating` 불변
- 클라이언트: `displayScore` 우선 표시, null이면 `currentScore` 폴백

---

## 3. 배치 게임 (첫 5게임)

| 항목 | 값 |
|------|-----|
| 배치 게임 수 | 5판 |
| 점수 공개 | 비공개 ("배치 중 N/5" 표시) |
| 매칭 범위 | 일반의 2배 (비용 0.5배) |
| RD 변화 | 게임 1→350→280, 2→220, 3→170, 4→130, 5→100 |
| 배치 완료 | gamesPlayed ≥ 5 → isPlacement=false, 점수 공개 |

### 배치 유저 매칭 전략
- 배치 유저끼리 우선 매칭 (3분간)
- 3분 후 전체 풀에 합류
- 기존 유저와 매칭 시 기존 유저 보호: 패배 시 레이팅 하락 × 0.7

---

## 4. 타임슬롯

| 슬롯 | 시간 | 코드 |
|------|------|------|
| 새벽 | ~06:00 | DAWN |
| 오전 | ~12:00 | MORNING |
| 오후 | ~18:00 | AFTERNOON |
| 저녁 | ~23:00 | EVENING |
| 하루종일 | ~24:00 | ANY |

`expiresAt` = 선택한 타임슬롯의 마감 시각

---

## 5. 동적 MMR 범위 확장 (핵심)

### 5.1 waitRatio 계산

```typescript
waitRatio = (now - createdAt) / max(expiresAt - createdAt, 30분)
// 최소 30분 윈도우 보장 (마감 직전 신청 보호)
// 0.0 ~ 1.0 범위
```

### 5.2 확장 함수: 보호 구간 20% + 제곱 확장

```
waitRatio: 0.0  0.1  0.2  0.3  0.4  0.5  0.6  0.7  0.8  0.9  1.0
factor:    0.0  0.0  0.0  .02  .06  .14  .25  .39  .56  .77  1.0
```

- **0~20%**: 확장 없음 (보호 구간, 동등 실력만 매칭)
- **20~100%**: 제곱 확장 `((waitRatio - 0.2) / 0.8)²`

### 5.3 RD 기반 동적 기본 범위

```
baseRange = max(50, RD × 1.0)
// 안정 유저(RD=60): 기본 ±60
// 배치 유저(RD=350): 기본 ±350 (어차피 불확실)
```

### 5.4 최종 유효 범위

```
effectiveRange = baseRange + (maxRange - baseRange) × expansionFactor(waitRatio)
// maxRange = 350
// 하드캡 = 250 (어떤 경우든 250점 이상 차이는 매칭 불가)
```

### 5.5 유저 풀 크기 보정

| 핀 내 대기 유저 | 전략 |
|----------------|------|
| ≤ 4명 | MMR 범위 무제한 (하드캡 내) |
| 5~10명 | Phase 1(보호 구간) 축소 |
| 10~20명 | 표준 |
| 20명+ | 타이트 운영 |

---

## 6. 비용 함수 (매칭 품질 점수)

```typescript
function calculateMatchCost(reqA, reqB, now) {
  // 1. 연패 조정 (3연패 시 유효 레이팅 -50)
  adjustedRatingA = reqA.lossStreak >= 3 ? reqA.rating - 50 : reqA.rating
  adjustedRatingB = reqB.lossStreak >= 3 ? reqB.rating - 50 : reqB.rating
  
  ratingDiff = |adjustedRatingA - adjustedRatingB|
  
  // 2. 유효 범위 (양측 중 더 넓은 쪽)
  rangeA = getEffectiveRange(reqA, now)
  rangeB = getEffectiveRange(reqB, now)
  effectiveRange = max(rangeA, rangeB)
  
  // 3. 범위 초과 → 매칭 불가
  if (ratingDiff > effectiveRange) return Infinity
  if (ratingDiff > 250) return Infinity  // 하드캡
  
  // 4. 대기 시간 할인 (오래 기다릴수록 비용 감소, 최대 70% 할인)
  avgWaitRatio = (waitRatioA + waitRatioB) / 2
  waitDiscount = 1.0 - 0.7 × avgWaitRatio
  
  cost = ratingDiff × waitDiscount
  
  // 5. 최근 상대 패널티 (+9999)
  if (isRecentOpponent(reqA, reqB)) cost += 9999
  
  // 6. 배치 보너스 (비용 절반)
  if (reqA.isPlacement || reqB.isPlacement) cost *= 0.5
  
  return cost
}
```

### 핵심 원칙
- **범위 초과는 절대 매칭 불가** (Infinity)
- **범위 내에서도 가까운 상대 우선** (cost ≠ 0)
- **오래 기다린 유저 우선** (waitDiscount)
- **하드캡 250점** (승률 20% 이하 매칭 방지)

---

## 7. 최적 페어링 알고리즘

```
1. 핀+종목별로 WAITING 요청 그룹핑
2. 각 그룹에서 모든 쌍의 비용 계산
3. 비용 오름차순 정렬
4. 그리디 매칭: 최저 비용 쌍 선택 → 양쪽 제거 → 반복
5. 최근 상대(cost >= 9999) 스킵
6. 매칭된 쌍 → Match + ChatRoom + MatchAcceptance 생성
```

---

## 8. 매칭 수락/거절 플로우

| 시나리오 | 결과 | 패널티 |
|----------|------|--------|
| 양측 수락 (10분 이내) | 매칭 성사 (CHAT) | 없음 |
| 한쪽 거절 | 매칭 취소 | 거절자 displayScore -15점 (glickoRating 불변) |
| 양측 미응답 (10분 초과) | 매칭 취소 | 없음 |
| 한쪽 수락, 한쪽 미응답 | 매칭 취소 | 미응답자 displayScore -15점 (glickoRating 불변) |

### 화면 잠금
- PENDING_ACCEPT 상태: 수락 화면 고정, 다른 화면 이동 불가
- CHAT/CONFIRMED 상태: 승부 결과 입력 버튼만 표시, 뒤로가기 차단
  - 포기 버튼 없음 — 매칭 성사 후 승/패/무만 존재
- 앱 재시작 시 활성 매칭으로 자동 리다이렉트

---

## 9. 게임 결과 처리

### Glicko-2 업데이트
```
승자: rating 상승, RD 감소
패자: rating 하락, RD 감소
무승부: 양측 소폭 조정, RD 감소
```

### 활동 보너스 (Glicko-2 위에 추가)
- K계수 가산: 주간 3게임+ → +2, 5게임+ → +4
- 연승 보너스: 2연승 +3, 3연승 +5, 5연승+ +8
- 일간 첫 게임 승리: +5

### 포기 제거
- 매칭 성사(CHAT/CONFIRMED) 이후에는 포기 없음
- 결과는 승/패/무 세 가지만 존재
- 노쇼(결과 미입력)는 별도 처리: noShowCount 증가 → 누적 시 매칭 제한

---

## 10. 부가 로직

### 최근 상대 제외
- `recentOpponentIds`: 최근 5명 추적
- 24시간 이내 동일 상대 재매칭 방지 (비용 +9999)

### 연패 보호
- 3연패 이상: 유효 레이팅 -50 (더 쉬운 상대와 매칭)
- 연패 카운터: 패배 시 +1, 승리/무승부 시 리셋

### 노쇼 제재
| 누적 | 제재 |
|------|------|
| 3회 | 24시간 매칭 제한 |
| 5회 | 3일 매칭 제한 |
| 10회 | 7일 매칭 제한 |

---

## 11. 모니터링 지표

매칭 생성 시 로그에 기록:
- 매칭 대기 시간 (createdAt ~ 매칭 시점)
- waitRatio 분포
- 레이팅 차이 분포
- effectiveRange 분포
- 수락률 / 거절률
- 배치 vs 일반 매칭 비율

---

## 12. 구현된 기능 체크리스트

- [x] Glicko-2 레이팅 시스템 (`shared/utils/glicko2.ts`)
- [x] 배치 게임 5판 (isPlacement, 점수 비공개)
- [x] 안정 매칭 알고리즘 (비용 행렬 + 그리디 최적 페어링)
- [x] 최근 상대 제외 (recentOpponentIds, 5명, cost +9999)
- [x] 연패 보호 (lossStreak, 유효 레이팅 -50)
- [x] 배치 유저 보너스 (비용 0.5배)
- [x] 매칭 수락/거절 (10분 타임아웃)
- [x] 거절 시 displayScore만 차감 (-15점), glickoRating 불변
- [x] 수락자 대기 복귀 + 소량 점수 보상
- [x] 화면 잠금 (PopScope, 앱 시작 시 리다이렉트)
- [x] 활동 보너스 (K계수 가산, 연승, 일간 보너스)
- [x] 타임슬롯 5종 (새벽/오전/오후/저녁/하루종일)
- [x] 앱 UI (ScoreText, 배치 뱃지, 카운트다운)
- [x] 동적 MMR 범위 확장 (waitRatio 기반)
- [x] displayScore / MMR 분리 (glickoRating 비공개 MMR, displayScore 표시 점수)
- [x] 매칭 성사 후 포기 제거 — 승/패/무만 존재
- [x] 거절 시 displayScore만 차감, MMR 불변
- [x] 하드캡 250점
- [x] decayRD 매칭 전 호출

---

## 13. P2/P3 향후 과제

- [ ] 시간대별 동적 T_max 조정
- [ ] 인접 핀 풀링 — 안 함 (단일 핀 정책 유지)
- [ ] 유저 동의 기반 불균형 매칭 — 안 함

---

## 14. 3명 전문가 핵심 합의점

> **"매칭이 안 잡히는 것은 일시적 불편이지만, 불공정한 매칭은 영구적 이탈을 만든다."**

1. **하드캡 250점 필수** — 어떤 대기 시간이든 250점 이상 차이 매칭 불가
2. **3단계 확장이 10단계보다 현실적** — 소규모 풀에서 10단계는 초반이 무의미
3. **RD 활용이 핵심** — Glicko-2의 강점을 매칭에 반영
4. **보호 구간(20%) 필수** — 첫 대기 시간은 타이트 매칭
5. **초기 서비스는 친선 매칭이 안전판** — 랭크 안 잡히면 친선으로 유도
