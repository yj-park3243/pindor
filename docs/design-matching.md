# 핀돌 매칭 시스템 설계서

> 최종 업데이트: 2026-04-22 (코드 기준 최신화)
> 대상: 핀돌(PINDOR) 스포츠 매칭 플랫폼 — Fastify + TypeORM + PostgreSQL / 앱: Flutter

---

## 1. 전체 아키텍처

```
유저 매칭 요청 (핀 + 종목 + 날짜 + 타임슬롯 선택)
    │
    ▼
[매칭 요청 생성] → DB에 WAITING 상태로 저장
    │                expiresAt = 타임슬롯 종료 시각 (KST)
    │                desiredDate = 오늘 또는 내일 (YYYY-MM-DD)
    ▼
[자동 매칭 시도] → 같은 핀+종목+WAITING 중 점수 범위 내 후보 검색
    │                → 성별/나이 양방향 필터 → 최적 후보와 즉시 매칭
    │                → 매칭 안 되면 큐 워커에 이벤트 발행
    ▼
[매칭 큐 워커] — BullMQ 이벤트 기반 + 60초 fallback 폴링
    │
    ├── 1. (pinId + sportType + desiredDate) 기준 그룹핑
    ├── 2. 각 유저의 RD 시간 감쇠 (decayRD)
    ├── 3. 차단 관계 조회 (UserBlock)
    ├── 4. waitRatio → 동적 MMR 범위 계산
    ├── 5. 비용 행렬 생성 (최적 페어링)
    ├── 6. 매칭 성사 → PENDING_ACCEPT (10분 타임아웃)
    │       ├── 양측 수락 → CHAT (게임 진행)
    │       ├── 거절 → displayScore -15점
    │       └── 10분 미응답 → 자동 취소 (미응답자 -15점)
    ├── 7. 게임 종료 → Glicko-2 레이팅 업데이트
    └── 8. recentOpponentIds 양측 업데이트 (최근 5명)

[배치 게임] — 첫 5게임 동안 점수 비공개
```

---

## 2. 핀 기반 매칭 원칙

> **핵심: 위치 기반 매칭이 아니라, 핀 기반 매칭이다.**

- GPS 위치는 "가까운 핀 찾기"에만 사용
- 매칭은 유저가 **직접 선택한 핀**에서 이루어짐
- 팀도 핀 소속, 게시판도 핀 소속
- 유저는 여러 핀을 즐겨찾기로 등록하고, 원하는 핀에 매칭 신청
- **핀 확장 없음** — 다른 핀에서도 매칭하고 싶으면 직접 추가 신청

**매칭 플로우:**
```
유저가 핀 선택 (강남역)
  → 종목 선택 (GOLF)
  → 날짜 선택 (오늘 또는 내일)
  → 타임슬롯 선택 (AFTERNOON)
  → 매칭 요청 (WAITING)
  → 같은 핀 + 같은 종목 + 같은 날짜의 대기 풀에서 매칭
```

---

## 3. 레이팅 시스템: Glicko-2

핀돌은 ELO 대신 **Glicko-2**를 채택한다. ELO 대비 주요 장점은 세 가지다: (1) 불확실성(RD)을 수치로 관리해 신규 유저 매칭 품질 향상, (2) 비활동 기간 동안 RD 자동 증가로 복귀 유저 보호, (3) σ(볼라틸리티)로 성적 일관성을 반영해 MMR 조작에 강건.

기본 파라미터: μ=1000 (기존 스케일 유지), φ=350 (불확실성), σ=0.06 (변동성), τ=0.5 (시스템 상수).

- **glickoRating**: 내부 MMR — 매칭 상대 탐색에만 사용, 비공개
- **displayScore**: 유저에게 보이는 점수 = round(glickoRating) + 활동 보너스, 공개
- **currentScore**: deprecated — displayScore와 동기화, 구버전 클라이언트 호환용
- 거절 시: `displayScore`만 -15점 차감, `glickoRating` 불변
- 비활동 시 RD 증가: 매칭 큐 워커 실행 시 마지막 게임 이후 경과일(1 period = 1 day) 기준으로 `decayRD` 자동 적용 (상한 350)

상세 알고리즘: [design-matching-glicko2.md](design-matching-glicko2.md)

---

## 4. 배치 게임 (첫 5게임)

| 항목 | 값 |
|------|-----|
| 배치 게임 수 | 5판 |
| 점수 공개 | 비공개 ("배치 중 N/5" 표시) |
| 매칭 범위 | RD 멀티플라이어 최대 1.3배 적용 |
| RD 변화 | 게임 1→350→280, 2→220, 3→170, 4→130, 5→100 |
| 배치 완료 | gamesPlayed >= 5 → isPlacement=false, 점수 공개 |

### 배치 유저 매칭 전략
- 배치 유저 포함 페어: 비용(cost) 0.5배 적용 (더 넓은 범위 수용)
- RD 기반 멀티플라이어: 배치 유저는 `min(1.3, 1.0 + (rd - 50) / 350 * 0.3)`, 일반 유저는 `1.0 + (rd - 50) / 350`

---

## 5. 매칭 제한 규칙

> **코드 참조:** `matching.service.ts` → `createMatchRequest()`

### 5.1 날짜 제한

- **오늘 또는 내일만 가능**: `desiredDate`는 KST 기준 오늘 또는 내일만 허용
- **밤 11시 이후 당일 매칭 차단**: KST 23시 이후에는 `desiredDate === today` 요청 거부

### 5.2 같은 날짜 중복 차단 (desiredDate 지정 시)

1. **같은 날짜에 WAITING 요청 존재** → 차단 ("해당 날짜에 이미 대기 중인 매칭 요청이 있습니다.")
2. **같은 날짜에 활성 매칭 존재** (PENDING_ACCEPT / CHAT / CONFIRMED, `scheduled_date` 기준) → 차단 ("해당 날짜에 이미 진행 중인 매칭이 있습니다.")

### 5.3 desiredDate 없는 요청 차단

- desiredDate 미지정 시, **어떤 활성 매칭이든 존재하면** (PENDING_ACCEPT / CHAT / CONFIRMED) 차단
- desiredDate 미지정 시, **어떤 WAITING 요청이든 존재하면** 차단

### 5.4 CONFIRMED + 결과 미입력 차단

- `matches.status = 'CONFIRMED'` AND `games.result_status = 'PENDING'`인 매칭이 있으면 신규 매칭 차단
- 메시지: "결과 입력 대기 중인 매칭이 있습니다. 결과 입력 후 다시 신청해주세요."

### 5.5 총 활성 개수 제한 (최대 2개)

- `WAITING 요청 수 + 활성 매칭 수(PENDING_ACCEPT/CHAT/CONFIRMED) >= 2` → 차단
- 사실상 **오늘 1개 + 내일 1개** 구조

### 5.6 기타 차단 조건

| 조건 | 메시지 |
|------|--------|
| 거절 쿨다운 (`rejectionCooldownUntil > now`) | "거절 쿨다운 중입니다. N분 후에 다시 시도해 주세요." |
| 노쇼 밴 (`matchBanUntil > now`) | "노쇼 패널티로 인해 매칭이 제한되었습니다. N시간 후에 다시 시도해 주세요." |

### 5.7 제한 규칙 요약 다이어그램

```
createMatchRequest()
  │
  ├── 거절 쿨다운 체크
  ├── 노쇼 밴 체크
  ├── 스포츠 프로필 확인 (없으면 자동 생성)
  │
  ├── desiredDate 있는 경우:
  │     ├── 오늘 or 내일만 가능
  │     ├── KST 23시 이후 당일 차단
  │     ├── 같은 날짜 WAITING 요청 중복 차단
  │     └── 같은 날짜 활성 매칭 중복 차단
  │
  ├── desiredDate 없는 경우:
  │     ├── 어떤 활성 매칭이든 존재하면 차단
  │     └── 어떤 WAITING 요청이든 존재하면 차단
  │
  ├── CONFIRMED + 결과 미입력 매칭 존재 → 차단
  └── WAITING + 활성 매칭 합계 >= 2 → 차단
```

---

## 6. 타임슬롯 및 만료 시간

### 6.1 타임슬롯 정의

| 슬롯 | 시간 범위 | 코드 | 종료 시각 (만료 기준) |
|------|----------|------|---------------------|
| 새벽 | 00~03 | DAWN | 03:00 KST |
| 이른 아침 | 03~06 | EARLY_MORNING | 06:00 KST |
| 오전 | 06~09 | MORNING | 09:00 KST |
| 늦은 오전 | 09~12 | LATE_MORNING | 12:00 KST |
| 오후 | 12~15 | AFTERNOON | 15:00 KST |
| 늦은 오후 | 15~18 | LATE_AFTERNOON | 18:00 KST |
| 저녁 | 18~21 | EVENING | 21:00 KST |
| 밤 | 21~24 | NIGHT | 23:59 KST |
| 하루종일 | ~24 | ANY | 23:59 KST |

### 6.2 만료 시간 (`expiresAt`) 계산 로직

```typescript
const timeSlotEndHour = {
  DAWN: 3, EARLY_MORNING: 6, MORNING: 9, LATE_MORNING: 12,
  AFTERNOON: 15, LATE_AFTERNOON: 18, EVENING: 21, NIGHT: 24, ANY: 24,
};

if (requestType === 'INSTANT' || requestType === 'CASUAL') {
  expiresAt = now + 2시간;
} else if (desiredDate 있음) {
  endHour = timeSlotEndHour[desiredTimeSlot ?? 'ANY'];
  if (endHour >= 24) {
    expiresAt = desiredDate + 'T23:59:59+09:00';
  } else {
    expiresAt = desiredDate + 'T{endHour}:00:00+09:00';
  }
} else {
  expiresAt = 오늘 + 'T23:59:59+09:00';
}
```

**핵심 원칙:** 타임슬롯의 종료 시각이 만료 시각이다. AFTERNOON(12~15시) 선택 시 해당 날짜 15:00 KST에 만료.

---

## 7. 매칭 큐 워커 (그룹핑 및 페어링)

> **코드 참조:** `matching-queue.worker.ts`

### 7.1 실행 방식

- **이벤트 기반**: BullMQ Worker (`matching-process` 큐) — 매칭 요청 생성 시 `triggerMatchingProcess()` 호출로 즉시 처리
- **Fallback 폴링**: 60초 간격 (이벤트 누락 대비)
- **동시성 제한**: `concurrency: 1`, 최소 2초 간격 (연속 트리거 방어)

### 7.2 그룹핑 키

```
groupKey = `${pinId}::${sportType}::${desiredDate ?? 'ANY'}`
```

- **같은 날짜끼리만 매칭**: `desiredDate`가 그룹 키에 포함
- desiredDate가 null인 요청은 `'ANY'` 키로 별도 그룹

### 7.3 처리 순서

```
1. WAITING + expires_at > NOW() 인 모든 매칭 요청 조회 (Glicko-2 필드 JOIN)
2-a. 각 요청의 RD를 마지막 게임 이후 경과일 기준으로 decay 적용
2-b. 차단 관계(UserBlock) 일괄 조회 → blockedPairs Set 생성
2-c. (pinId, sportType, desiredDate) 기준 그룹핑
3. 각 그룹에서 최적 페어 찾기 (min-cost 그리디)
4. 각 페어에 대해 트랜잭션으로 매칭 생성:
   - 최신 상태 재확인 (race condition 방지)
   - ChatRoom 생성 (MATCH 타입)
   - Match 생성 (PENDING_ACCEPT 상태)
     - desiredDate = pairA.desiredDate ?? pairA.createdAt
     - scheduledDate = pairA.desiredDate ?? null
     - desiredTimeSlot: ANY가 아닌 쪽 우선
   - MatchAcceptance 2개 생성 (expiresAt: 10분 후)
   - MatchRequest 상태 → MATCHED
   - 시스템 메시지 생성
5. recentOpponentIds 양측 업데이트 (트랜잭션 외부)
6. Redis pub/sub 알림 (system_notification + match_lifecycle)
```

### 7.4 소규모 풀 처리

- **4명 이하**: 동적 MMR 범위 필터 비활성화 (하드캡 250점만 적용)
- **5명 이상**: 표준 동적 범위 필터 적용

---

## 8. 동적 MMR 범위 확장

### 8.1 waitRatio 계산

```typescript
waitRatio = (now - createdAt) / max(expiresAt - createdAt, 30분)
// 최소 30분 윈도우 보장 (마감 직전 신청 보호)
// 0.0 ~ 1.0 범위
```

### 8.2 확장 함수: 보호 구간 20% + 제곱 확장

```
waitRatio: 0.0  0.1  0.2  0.3  0.4  0.5  0.6  0.7  0.8  0.9  1.0
factor:    0.0  0.0  0.0  .02  .06  .14  .25  .39  .56  .77  1.0
```

- **0~20%**: 확장 없음 (보호 구간, 동등 실력만 매칭)
- **20~100%**: 제곱 확장 `((waitRatio - 0.2) / 0.8)^2`

### 8.3 유효 MMR 범위 계산

```typescript
function getEffectiveRange(req) {
  const BASE_RANGE = 50;
  const MAX_RANGE = 350;
  const range = BASE_RANGE + (MAX_RANGE - BASE_RANGE) * expansionFactor(waitRatio);

  // RD 기반 멀티플라이어
  const rdMultiplier = req.isPlacement
    ? min(1.3, 1.0 + (rd - 50) / 350 * 0.3)   // 배치: 최대 1.3배
    : 1.0 + (rd - 50) / 350;                    // 일반: RD에 비례

  return min(range * rdMultiplier, 250);  // 하드캡 250
}
```

### 8.4 유효 범위 적용

- 양측의 effectiveRange 중 **더 넓은 쪽** 적용 (`max(rangeA, rangeB)`)
- 소규모 풀(4명 이하)에서는 동적 범위 필터 비활성화

---

## 9. 비용 함수 (매칭 품질 점수)

```typescript
function calculateMatchCost(reqA, reqB) {
  // 1. 동일 유저 매칭 방지
  if (reqA.requesterId === reqB.requesterId) → skip

  // 2. 차단 관계 → skip
  if (blockedPairs.has(blockKey)) → skip

  // 3. 연패 조정 (3연패 시 유효 레이팅 -50)
  adjustedRatingA = reqA.lossStreak >= 3 ? reqA.glickoRating - 50 : reqA.glickoRating
  adjustedRatingB = reqB.lossStreak >= 3 ? reqB.glickoRating - 50 : reqB.glickoRating

  ratingDiff = |adjustedRatingA - adjustedRatingB|

  // 4. 하드캡: 250 초과 → 절대 불가
  if (ratingDiff > 250) → skip

  // 5. 유효 범위 (양측 중 넓은 쪽)
  effectiveRange = max(getEffectiveRange(reqA), getEffectiveRange(reqB))
  if (!smallPool && ratingDiff > effectiveRange) → skip

  // 6. 대기 시간 할인 (오래 기다릴수록 비용 감소, 최대 70% 할인)
  avgWaitRatio = (waitRatioA + waitRatioB) / 2
  waitDiscount = 1.0 - 0.7 * avgWaitRatio
  cost = ratingDiff * waitDiscount

  // 7. 최근 상대 패널티 (+9999)
  if (isRecentOpponent(reqA, reqB)) cost += 9999

  // 8. 배치 보너스 (비용 절반)
  if (reqA.isPlacement || reqB.isPlacement) cost *= 0.5

  return cost  // cost >= 9999이면 페어링 시 skip
}
```

**핵심 원칙:**
- 하드캡 250점 초과는 절대 매칭 불가
- 차단 관계는 절대 매칭 불가
- 범위 내에서도 가까운 상대 우선 (cost != 0)
- 오래 기다린 유저 우선 (waitDiscount)
- 최근 상대(24시간 내)는 cost >= 9999로 실질 차단

---

## 10. 최적 페어링 알고리즘

```
1. (pinId + sportType + desiredDate) 기준 WAITING 요청 그룹핑
2. 각 그룹에서 모든 쌍의 비용 계산
3. 비용 오름차순 정렬
4. 그리디 매칭: 최저 비용 쌍 선택 → 양쪽 제거 → 반복
5. cost >= 9999 스킵 (최근 상대 패널티)
6. 한 사이클 내 이미 매칭된 요청 ID 추적 (중복 매칭 방지)
7. 매칭된 쌍 → Match + ChatRoom + MatchAcceptance 생성 (트랜잭션)
```

> n=30 수준에서 O(n^2) 그리디는 10ms 이내 처리 가능. 실제 운영에서 문제 발생 시 `minCostFlow` 라이브러리 도입 검토.

---

## 11. 매칭 수락/거절 플로우

| 시나리오 | 결과 | 패널티 |
|----------|------|--------|
| 양측 수락 (10분 이내) | 매칭 성사 (CHAT) | 없음 |
| 한쪽 거절 | 매칭 취소 (CANCELLED) | 거절자 displayScore -15점 (glickoRating 불변) |
| 양측 미응답 (10분 초과) | 매칭 취소 | 없음 |
| 한쪽 수락, 한쪽 미응답 | 매칭 취소 | 미응답자 displayScore -15점 (glickoRating 불변) |

### 화면 잠금
- PENDING_ACCEPT 상태: 수락 화면 고정, 다른 화면 이동 불가
- CHAT/CONFIRMED 상태: 승부 결과 입력 버튼만 표시, 뒤로가기 차단
  - 포기 버튼 없음 — 매칭 성사 후 승/패/무만 존재
- 앱 재시작 시 활성 매칭으로 자동 리다이렉트

---

## 12. 게임 결과 처리

### Glicko-2 업데이트
```
승자: rating 상승, RD 감소
패자: rating 하락, RD 감소
무승부: 양측 소폭 조정, RD 감소
```

### 활동 보너스 (Glicko-2 위에 추가)

| 보너스 종류 | 조건 | 점수 |
|-----------|------|------|
| K계수 가산 | 주간 3게임+ | K+2 |
| K계수 가산 | 주간 5게임+ | K+4 |
| 연승 보너스 | 2연승 | +3 |
| 연승 보너스 | 3연승 | +5 |
| 연승 보너스 | 5연승+ | +8 |
| 일간 첫 게임 승리 | 당일 첫 승 | +5 |
| 주간 목표 | 주 3게임 완료 | +10 |
| 주간 목표 | 주 5게임 완료 | +20 |

최종 변동 = Glicko-2 변동 + 연승보너스 + 일간보너스 + 주간목표보너스

### 포기 제거
- 매칭 성사(CHAT/CONFIRMED) 이후에는 포기 없음
- 결과는 승/패/무 세 가지만 존재
- 노쇼(결과 미입력)는 별도 처리: noShowCount 증가 → 누적 시 매칭 제한

---

## 13. 부가 로직

### 최근 상대 제외
- `recentOpponentIds`: UUID 배열, 최근 5명 추적 (`array_prepend` 방식)
- 24시간 이내 동일 상대 재매칭 방지 (비용 +9999)
- 매칭 성사 시 양측 recentOpponentIds 업데이트 (트랜잭션 외부, 비치명적 실패 허용)

### 차단 관계 제외
- `UserBlock` 테이블 조회 (blockerId / blockedId 양방향)
- 차단된 쌍은 `blockedPairs` Set에 저장 → 비용 계산 시 절대 매칭 불가

### 연패 보호
- 3연패 이상: 유효 레이팅 -50 (더 쉬운 상대와 매칭)
- 연패 카운터: 패배 시 +1, 승리/무승부 시 리셋

### 노쇼 제재

| 누적 | 제재 |
|------|------|
| 3회 | 24시간 매칭 제한 |
| 5회 | 3일 매칭 제한 |
| 10회 | 7일 매칭 제한 |

### 캐주얼 매칭
- `isCasual: true` 시 `requestType = CASUAL`, MMR 범위 +-600 자동 설정
- 만료 시간: 생성 시점 + 2시간

---

## 14. 목록 조회 시 필터링

### 매칭 요청 목록 (`listMatchRequests`)
- **기본 동작**: `EXPIRED`, `CANCELLED` 상태 숨김
- `status` 파라미터 지정 시: 해당 상태만 조회

### 매칭 목록 (`listMatches`)
- **기본 동작**: `CANCELLED` 상태 숨김
- `status` 파라미터 지정 시: 해당 상태만 조회

---

## 15. DB 스키마

**sports_profiles 추가 컬럼**: `glicko_rating DOUBLE(1000.0)`, `glicko_rd DOUBLE(350.0)`, `glicko_volatility DOUBLE(0.06)`, `glicko_last_updated_at TIMESTAMPTZ`, `is_placement BOOLEAN(true)`, `loss_streak INT(0)`, `win_streak INT(0)`, `no_show_count INT(0)`, `match_ban_until TIMESTAMPTZ`, `recent_opponent_ids UUID[]`

**match_requests 주요 컬럼**: `requester_id`, `sports_profile_id`, `pin_id`, `sport_type`, `request_type`, `desired_date DATE`, `desired_time_slot "TimeSlot"`, `location_point GEOGRAPHY`, `location_name`, `min_opponent_score`, `max_opponent_score`, `gender_preference`, `min_age`, `max_age`, `message`, `is_casual BOOLEAN`, `status`, `expires_at TIMESTAMPTZ`

**matches 주요 컬럼**: `match_request_id`, `requester_profile_id`, `opponent_profile_id`, `pin_id`, `sport_type`, `status`, `chat_room_id`, `desired_date`, `scheduled_date`, `desired_time_slot`

**score_histories 추가 컬럼**: `rd_before`, `rd_after`, `volatility_before`, `volatility_after DOUBLE`, `is_placement_game BOOLEAN`

**users 추가 컬럼**: `rejection_count INT`, `rejection_cooldown_until TIMESTAMPTZ`

---

## 16. API 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/matches/requests` | 매칭 요청 생성 |
| POST | `/matches/instant` | 즉시 매칭 (오늘 대결, createMatchRequest 래핑) |
| GET | `/matches/requests` | 내 매칭 요청 목록 (EXPIRED/CANCELLED 기본 숨김) |
| DELETE | `/matches/requests/:id` | 매칭 요청 취소 |
| GET | `/matches` | 내 매칭 목록 (CANCELLED 기본 숨김) |
| GET | `/matches/active` | 활성 매칭 조회 (앱 시작 시 리다이렉트용) |
| GET | `/matches/:id` | 매칭 상세 조회 |
| PATCH | `/matches/:id/confirm` | 경기 확정 |
| PATCH | `/matches/:id/cancel` | 경기 취소 |
| POST | `/matches/:matchId/accept` | 매칭 수락 |
| POST | `/matches/:matchId/reject` | 매칭 거절 |
| GET | `/matches/:matchId/status` | 매칭 수락 상태 조회 (양측 수락 여부) |
| POST | `/matches/:id/report-noshow` | 노쇼 신고 (증거 사진 1~3장 필수) |
| POST | `/matches/:id/forfeit` | 매칭 포기 (패배 처리) |

---

## 17. 앱 UI 변경 사항

배치 진행 중: `████░░░░░ 3/5` 프로그레스바, 점수 비공개 표시.
배치 완료 시: 레이팅 공개 다이얼로그 (`PlacementCompleteDialog`).
게임 결과: 레이팅 변동 표시 `1,230 → 1,248 (+18)`.

**변경 위젯**: `RatingWidget`(isPlacement 분기), `PlacementProgressBar`(신규), `PlacementCompleteDialog`(신규), `MatchingWaitingScreen`(isPlacementMode 배지), `GameResultScreen`(ratingChange, placementCompleted).

---

## 18. 모니터링 지표

매칭 생성 시 로그에 기록:
- 매칭 대기 시간 (createdAt ~ 매칭 시점)
- waitRatio 분포
- 레이팅 차이 분포 (ratingDiff)
- effectiveRange 분포
- 수락률 / 거절률
- 배치 vs 일반 매칭 비율
- RD 값 (양측)

---

## 19. 구현 체크리스트

- [x] Glicko-2 레이팅 시스템 (`shared/utils/glicko2.ts`) / RD 시간 감쇠 (`decayRD`)
- [x] 배치 게임 5판 (isPlacement, 점수 비공개) / 배치 유저 비용 0.5배
- [x] 비용 행렬 + 그리디 최적 페어링 / 최근 상대 5명 제외 (cost +9999)
- [x] 연패 보호 (lossStreak, 유효 레이팅 -50) / 하드캡 250점
- [x] 매칭 수락/거절 10분 타임아웃 / 거절 시 displayScore -15점 (glickoRating 불변)
- [x] 화면 잠금 (PopScope, 앱 시작 리다이렉트) / 포기 제거 (승/패/무만 존재)
- [x] 활동 보너스 (K계수 가산, 연승, 일간) / displayScore/glickoRating 분리
- [x] 타임슬롯 8종(+ANY) / 동적 MMR 범위 확장 (waitRatio 기반)
- [x] 날짜 기반 매칭 제한 (오늘+내일 최대 2개, 같은 날짜 1개)
- [x] desiredDate 기반 큐 그룹핑 (pinId + sportType + desiredDate)
- [x] 만료 시간: 타임슬롯 종료 시각 기준 / INSTANT/CASUAL: 2시간
- [x] CONFIRMED + 결과 미입력 시 신규 매칭 차단
- [x] 차단 관계(UserBlock) 매칭 제외
- [x] 목록 조회 시 EXPIRED/CANCELLED 기본 숨김
- [x] BullMQ 이벤트 기반 매칭 큐 + 60초 fallback 폴링
- [x] 매칭 성사 시 Redis pub/sub 알림 (system_notification + match_lifecycle)
- [x] 캐주얼 매칭 (isCasual, MMR +-600, 2시간 만료)

---

## 20. 향후 과제 (P2/P3)

- [ ] 시간대별 동적 T_max 조정
- [ ] 인접 핀 풀링 — 현재 안 함 (단일 핀 정책 유지)
- [ ] 시즌 시스템 — 3개월 단위, MMR 소프트 리셋 (중앙값 방향 30% 회귀)
- [ ] OpenSkill 마이그레이션 검토 (`npm install openskill`) — 팀매칭 지원 시
- [ ] 팀 매칭 MMR — `0.5 * max(skills) + 0.5 * avg(skills)` + 프리메이드 보정 +50~100
- [ ] 랭크 조작 방지 — 스머프 탐지(5게임 내), 파티 MMR 차이 제한(800점), 부스팅 방지
- [ ] recent_opponents 정리 크론 — 24시간 이상 된 레코드 일 1회 삭제

---

## 21. 전문가 합의 원칙

> **"매칭이 안 잡히는 것은 일시적 불편이지만, 불공정한 매칭은 영구적 이탈을 만든다."**

1. **하드캡 250점 필수** — 어떤 대기 시간이든 250점 이상 차이 매칭 불가
2. **RD 활용이 핵심** — Glicko-2의 강점을 매칭에 반영
3. **보호 구간(20%) 필수** — 첫 대기 시간은 타이트 매칭
4. **초기 서비스는 친선 매칭이 안전판** — 랭크 안 잡히면 친선으로 유도
