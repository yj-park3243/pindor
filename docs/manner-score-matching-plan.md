# 매너 점수 매칭 반영 기획서

> 작성일: 2026-04-27
> 최종 수정: 2026-04-27
> 상태: **✅ 구현 완료 + 운영 배포 완료 + E2E 테스트 PASS**
> 목적: 평가 시스템으로만 사용되는 매너 점수를 매칭 알고리즘에 반영해, 매너 좋은 유저는 좋은 상대와 만나고, 매너 나쁜 유저는 자체 정화/격리되도록 한다.

## 변경 이력
- 2026-04-27 v1.0 초안 작성
- 2026-04-27 v1.1 노쇼 기획서와 통합 구현 (`manner_ratings` 테이블 신설로 voided 추적 가능)
- 2026-04-27 v1.2 코드 리뷰: `manner_ratings` UNIQUE 제약에 `source` 추가 (USER + NOSHOW_AUTO 동시 저장 허용)

---

## 1. 배경 & 현황

### 현재 상태
- `sports_profiles.manner_total / manner_count` 누적 (1~5점 평가)
- 평균은 매칭 카드/상대 프로필 시트에 **표시만** 됨
- 매칭 큐 워커(`matching-queue.worker.ts`)의 cost 계산에 매너 점수 변수 **없음**
- → 매너 1.0인 유저도 매너 5.0인 유저와 동일한 확률로 매칭됨

### 문제
- 매너 평가가 매칭 행동에 어떤 영향도 안 주므로 **평가 인센티브 부재**
  - 평가해봐야 의미가 없으니 점차 평가율이 떨어짐
- 매너 나쁜 유저가 매너 좋은 유저와 계속 매칭되어 **신규/충성 유저 이탈** 가능
- 노쇼 시스템(`match_ban_until`)은 이미 작동 중이지만, "노쇼는 안 했지만 매너가 나쁜" 케이스(과한 트래시토크, 약속 변경 등)는 무방비

---

## 2. 목표 & 비목표

### 목표
1. 매너 평가가 **매칭 결과에 실질적 영향**을 주는 구조 만들기
2. 매너 나쁜 유저끼리 만나도록 자연스러운 분리 (banishment 아닌 self-segregation)
3. 매너 평가 인센티브 → 평가율 상승 → 데이터 신뢰도 상승

### 비목표
- 매너 점수 낮다고 매칭 자체를 **차단하지 않는다** (그건 노쇼/신고 시스템의 영역)
- 매너 점수가 점수/티어를 직접 변경하지 않는다 (Glicko-2 순수성 유지)
- 표본이 적은 신규 유저에게 불이익 없도록 한다 (cold start 보호)

---

## 3. 핵심 설계 원칙

### 3-1. 표본 최소치 — Cold Start 보호
- `manner_count < 5` 유저 → **매너 가중치 0** (기존 매칭 동일)
- 5건 이상 평가받은 유저만 매너 영향 받음
- 신규 유저 보호 + 적은 표본의 통계적 노이즈 제거

### 3-2. 매너 등급 정의 (3단계)
| 등급 | 매너 평균 | 분류 |
|---|---|---|
| GOOD | ≥ 4.0 | 우대 |
| NORMAL | 2.5 ~ 3.99 | 기본 |
| BAD | < 2.5 | 페널티 |

> ⚠ 평균이지 합계가 아님 (`manner_total / manner_count`)

### 3-3. 매칭 cost 보정 (`matching-queue.worker.ts`)

기존 cost 식:
```
cost = ratingDiff × waitDiscount
     + (최근 상대면 +9999)
     × (같은 핀이면 0.5)
```

**신규 추가 — 매너 매칭 cost 보정:**
| 조합 | 추가 cost | 의미 |
|---|---|---|
| GOOD ↔ GOOD | -50 | 우선 매칭 |
| GOOD ↔ NORMAL | 0 | 기본 |
| GOOD ↔ BAD | **+200** | 강력 회피 (매너 좋은 사람은 매너 나쁜 사람 잘 안 만남) |
| NORMAL ↔ NORMAL | 0 | 기본 |
| NORMAL ↔ BAD | +50 | 약한 회피 |
| BAD ↔ BAD | -100 | 끼리끼리 매칭 우대 (격리 효과) |

> 표본 부족(`< 5건`) 측은 NORMAL로 간주.

### 3-4. 하드캡 유지
- 기존 `cost > 9999` 차단(최근 상대) + `ratingDiff > 250` 하드캡 그대로
- 매너 보정은 일반 cost와 합산되어 우선순위에만 영향. 절대 매칭 가능 여부에 영향 X
- → "매너 나쁘다고 매칭 못 함" 사고 방지

---

## 4. 데이터 모델

### 추가 테이블/컬럼 — **없음**
- `sports_profiles.manner_total / manner_count` 그대로 사용
- 등급은 워커가 매번 계산 (`avg = total / count`) — 캐시 불필요 (조회 빈도 낮음)

### 매칭 큐 워커 SQL 수정
`getWaitingRequests()` 같은 부분에서 매너 누적값 함께 SELECT:
```sql
SELECT
  mr.id, mr.requester_id, mr.sports_profile_id, ...
  sp.manner_total,
  sp.manner_count
FROM match_requests mr
JOIN sports_profiles sp ON sp.id = mr.sports_profile_id
WHERE mr.status = 'WAITING'
```

`WaitingRequest` 타입에 필드 추가:
```typescript
interface WaitingRequest {
  ...
  mannerTotal: number;
  mannerCount: number;
}
```

---

## 5. 구현 — 매칭 워커 변경

### 5-1. 매너 등급 분류 함수
`server/src/workers/matching-queue.worker.ts` 상단:
```typescript
type MannerTier = 'GOOD' | 'NORMAL' | 'BAD';

const MANNER_MIN_SAMPLES = 5;
const GOOD_THRESHOLD = 4.0;
const BAD_THRESHOLD = 2.5;

function getMannerTier(req: WaitingRequest): MannerTier {
  if (req.mannerCount < MANNER_MIN_SAMPLES) return 'NORMAL';
  const avg = req.mannerTotal / req.mannerCount;
  if (avg >= GOOD_THRESHOLD) return 'GOOD';
  if (avg < BAD_THRESHOLD) return 'BAD';
  return 'NORMAL';
}
```

### 5-2. 매너 cost 보정 함수
```typescript
function mannerCostAdjustment(a: WaitingRequest, b: WaitingRequest): number {
  const ta = getMannerTier(a);
  const tb = getMannerTier(b);
  const pair = [ta, tb].sort().join('-');
  // 'BAD-BAD' | 'BAD-GOOD' | 'BAD-NORMAL' | 'GOOD-GOOD' | 'GOOD-NORMAL' | 'NORMAL-NORMAL'
  switch (pair) {
    case 'GOOD-GOOD':       return -50;
    case 'BAD-GOOD':        return +200;
    case 'BAD-NORMAL':      return +50;
    case 'BAD-BAD':         return -100;
    case 'GOOD-NORMAL':
    case 'NORMAL-NORMAL':
    default:                return 0;
  }
}
```

### 5-3. cost 계산에 합산
`findOptimalPairs` 안의 cost 계산:
```typescript
let cost = ratingDiff * waitDiscount;
cost += mannerCostAdjustment(requests[i], requests[j]); // ← 추가

if (isRecentOpponent(...)) cost += 9999;
if (samePin(...)) cost *= 0.5;
```

> ⚠ 매너 보정은 `* 0.5`(같은 핀) **앞에** 더한다. 그래야 같은 핀일 때 매너 보정도 절반으로 약화됨 — 동네 매칭에서는 매너 보정 효과를 줄여 매칭률 우선.

---

## 6. 어드민 — 모니터링 & 정책 조정

### 어드민 페이지에 추가할 정보
1. **유저 매너 등급 분포** (활성 유저 기준 GOOD/NORMAL/BAD 비율)
2. **유저 상세 페이지에 매너 평균 + 표본 수 표시**
3. **(선택) 매너 임계치 환경변수 노출**: 운영 중 GOOD_THRESHOLD/BAD_THRESHOLD 조정 가능
   ```
   MANNER_GOOD_THRESHOLD=4.0
   MANNER_BAD_THRESHOLD=2.5
   MANNER_MIN_SAMPLES=5
   ```

---

## 7. 효과 측정 (KPI)

### 단기 (1주)
- 매너 평가 입력률 (경기 결과 제출 중 mannerScore != null 비율)
- BAD ↔ GOOD 매칭 비율 (목표: 도입 전 대비 50% 감소)

### 중기 (1달)
- BAD 등급 유저의 잔존율 (격리되어 이탈하는지 vs 매너 개선되는지)
- 신고 발생 건수 (목표: 도입 전 대비 30% 감소)

### 장기 (3달)
- 신규 유저 잔존율 (매너 좋은 환경 → 잔존 증가)

---

## 8. 리스크 & 대응

| 리스크 | 대응 |
|---|---|
| 표본 적은 유저가 BAD로 잘못 분류 | `MANNER_MIN_SAMPLES = 5` 보호. 5건 미만은 NORMAL 강제 |
| 악의적 평가 담합으로 특정 유저 BAD화 | 매너 평가는 결과 입력 시 1번만 + 같은 상대에게 반복 평가 차단 (별도 작업 필요) |
| BAD 끼리만 매칭되어 매칭 풀 부족 | 대기 시간 길어지면 `waitDiscount` 효과로 자연스럽게 NORMAL과 매칭됨 |
| 매너 점수 없는 신규 유저가 BAD와 매칭 | 신규 유저는 NORMAL → BAD-NORMAL = +50으로 약한 회피, 큰 영향 X |
| 매칭 알고리즘 디버깅 어려움 | 매칭 결과 로그에 매너 보정 cost 명시 (`debugLog: { mannerAdj: -50 }`) |

---

## 9. 구현 범위 (한 번에 출시)

1. `matching-queue.worker.ts`:
   - `WaitingRequest` 타입에 `mannerTotal`, `mannerCount` 추가
   - DB 조회 시 함께 SELECT
   - `getMannerTier()` 헬퍼
   - `mannerCostAdjustment()` 헬퍼
   - cost 계산에 합산
2. (선택) 환경변수 노출:
   - `MANNER_MIN_SAMPLES` (기본 5)
   - `MANNER_GOOD_THRESHOLD` (기본 4.0)
   - `MANNER_BAD_THRESHOLD` (기본 2.5)
3. (선택) 매칭 결과 로그에 `mannerAdj` 디버그 필드 추가
4. 어드민 유저 상세 페이지에 매너 평균/표본 수 표시 (이미 일부 표시 중일 수 있음 — 확인 필요)

> 데이터 모델 변경/마이그레이션 **없음**. 기존 `sports_profiles` 컬럼 재활용.

---

## 10. 채택된 결정사항 (구현 완료)

- [x] 매너 등급 임계치: **`GOOD ≥ 4.0`, `BAD < 2.5`** (디폴트 채택)
- [x] 표본 최소치: **`MANNER_MIN_SAMPLES = 5`** (5건 미만은 NORMAL)
- [x] cost 보정: GOOD-GOOD `-50`, BAD-GOOD `+200`, BAD-NORMAL `+50`, BAD-BAD `-100`, 그 외 `0`
- [x] **환경변수로 임계치 노출** (`MANNER_GOOD_THRESHOLD`, `MANNER_BAD_THRESHOLD`, `MANNER_MIN_SAMPLES`)
- [x] BAD-BAD `-100` 격리 우대 도입
- [x] **랭크/친선 동일 적용** (분리 X)
- [ ] 어드민 매너 분포 대시보드 — 향후 작업 (이번 출시 범위 X)
- [x] cost 보정은 `* 0.5`(같은 핀) **앞**에 합산 (동네 매칭 우선 안 채택)
- [x] 매칭 결과 디버그 로그에 `mannerAdj` 필드 출력

---

## 11. 구현 산출물

### 신규/수정 파일
- **신규**: `server/src/entities/manner-rating.entity.ts` — UNIQUE `(matchId, raterId, ratedUserId, source)`
- **수정**: `server/src/workers/matching-queue.worker.ts`
  - `WaitingRequest`에 `mannerTotal`, `mannerCount` 필드 추가
  - DB 조회 시 `manner_total`, `manner_count` 함께 SELECT
  - `getMannerTier()`, `mannerCostAdjustment()` 헬퍼 추가
  - cost 계산식에 `mannerAdj` 합산 (같은 핀 `* 0.5` 앞)
  - `pairs[]`에 `mannerAdj` 디버그 필드 포함
- **수정**: `server/src/modules/games/games.service.ts` — 매너 평가 입력 시 `manner_ratings` INSERT + `sports_profiles.manner_total/count` 동시 갱신 (트랜잭션)
- **수정**: `server/src/server.ts` — `manner_ratings` 테이블 + UNIQUE 제약 마이그레이션

### 환경변수
- `MANNER_MIN_SAMPLES` (기본 5)
- `MANNER_GOOD_THRESHOLD` (기본 4.0)
- `MANNER_BAD_THRESHOLD` (기본 2.5)

### E2E 테스트 PASS (`server/tests/test-noshow-manner-e2e.ts` S8)
- tier 분류 5케이스 (NORMAL/GOOD/BAD) 모두 일치
- cost 매트릭스 6종 (GOOD-GOOD/-50, BAD-GOOD/+200, NORMAL-BAD/+50, BAD-BAD/-100, GOOD-NORMAL/0, NORMAL-NORMAL/0) 모두 일치

## 12. 참고 시스템 (관계 정리)

| 시스템 | 강도 | 설명 |
|---|---|---|
| 차단 (`user_blocks`) | Hard ban | 절대 매칭 안 됨 |
| 노쇼 ban (`match_ban_until`) | Hard ban | 일정 기간 매칭 신청 자체 차단 |
| 거절 페널티 (`-5 displayScore`) | Score | 매너와 무관, MMR에만 영향 |
| **매너 cost 보정** | **Soft** | 매칭 우선순위만 조정, 매칭 자체는 가능 |

> 매너 시스템은 위 3개 시스템과 **독립적이고 보완적**이다. 노쇼/차단은 hard ban, 매너는 soft preference.
>
> 단, **노쇼 확정(APPROVED) 시 자동으로 `manner_ratings`에 1점(NOSHOW_AUTO) 누적**되어 매너 평균이 떨어진다 → 매너 cost 보정에 자연스럽게 반영. 두 시스템은 결과 차원에서 단일 채널로 수렴.

### 관련 파일 (참조)
- 매너 평가 UI: `app/lib/screens/game/game_result_input_screen.dart`
- 매너 점수 표시: `app/lib/widgets/common/match_card.dart`
- 노쇼 처리 기획서: [./noshow-admin-plan.md](./noshow-admin-plan.md)
