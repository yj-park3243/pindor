# 팀 랭크 (Team Ranked / Duo Queue)

> 상태: 기획 / 미개발
> 작성일: 2026-05-12
> 참고: LoL 듀오 큐 모델

## 개요

기존 1:1 랭크와 **독립적**으로 운영되는 2v2 팀 랭크. 친구 시스템을 기반으로 2명이 한 팀을 이뤄 상대 2명과 매칭. 매칭 종료 후 팀은 해산되고 다른 친구와 다시 팀을 짤 수 있음.

## 핵심 규칙

### 팀 구성
- **2명 1팀** — 단판제 (3인 이상 팀은 별도 기능 — 기존 팀 기능과 다름)
- 팀 생성 시점에 한 명이 "팀 리더" 역할 (먼저 큐 진입한 사람)
- 친구 관계가 있어야 팀 가능 — 모르는 사람과는 듀오 X (스팸/조작 방지)

### 매칭 큐 진입 조건
- 두 멤버 모두:
  - 동일 종목 (예: 둘 다 골프 팀 랭크 신청)
  - 동일 핀 또는 동일 지역 (반경 N km 이내)
  - 동일 날짜/시간대
- 두 멤버 간 **팀 MMR 차이 ≤ THRESHOLD** (기본 300점) — 차이 너무 크면 매칭 신청 자체 불가
- 한 명이 큐 진입 → 다른 멤버에게 푸시 → 수락하면 큐 등록

### 매칭 알고리즘
- 큐에서 같은 조건의 다른 듀오 탐색
- 매칭 기준: **두 팀의 평균 팀 MMR 차이 최소화**
- 또한 두 팀 내 멤버 점수 차이도 일정 범위 (예: A팀 600/1200, B팀 800/1000 → 평균은 같지만 분산 큼 → 조정 필요)
- 워커: 기존 1:1 matching-queue.worker 와 별개 큐 (`team-matching-queue.worker`)

### 점수 변동 (팀 Glicko-2)
- **개인 랭크와 완전히 독립된 `team_mmr`** 컬럼
- 승리 팀: 각 멤버 +X (자신의 team_mmr이 낮을수록 더 많이 상승 — 동반 캐리 보상)
- 패배 팀: 각 멤버 -Y (자신의 team_mmr이 높을수록 더 많이 하락 — 부진 페널티)
- 듀오 멤버끼리 같이 받지만 **각자 다른 값** (LoL과 동일 모델)

### 매칭 종료 후
- 팀 해산 → 두 멤버 모두 큐에서 빠짐
- 같은 친구와 즉시 재큐 가능 — 단 연승/연패 큐 페널티 없음 (단순화)
- 노쇼/도주: 기존 1:1 정책 동일 적용 (양 팀원 모두 페널티)

## DB 스키마

### `sports_profiles` 확장
```sql
ALTER TABLE sports_profiles
  ADD COLUMN team_mmr           int NOT NULL DEFAULT 1000,
  ADD COLUMN team_rating        float NOT NULL DEFAULT 1500,   -- Glicko-2 rating
  ADD COLUMN team_rd            float NOT NULL DEFAULT 350,    -- rating deviation
  ADD COLUMN team_vol           float NOT NULL DEFAULT 0.06,
  ADD COLUMN team_wins          int NOT NULL DEFAULT 0,
  ADD COLUMN team_losses        int NOT NULL DEFAULT 0,
  ADD COLUMN team_games         int NOT NULL DEFAULT 0;
```

### `team_match_requests` 테이블 신규
```sql
CREATE TABLE team_match_requests (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_leader_id       uuid NOT NULL REFERENCES users(id),
  team_partner_id      uuid NOT NULL REFERENCES users(id),
  sport_type           varchar(16) NOT NULL,
  pin_id               uuid REFERENCES pins(id),
  desired_date         date,
  desired_time_slot    varchar(16),
  match_radius_km      int DEFAULT 10,
  status               varchar(16) NOT NULL DEFAULT 'WAITING',
                       -- WAITING / MATCHED / CANCELLED / EXPIRED
  avg_team_mmr         int NOT NULL,  -- 매칭 시 사용
  mmr_diff_internal    int NOT NULL,  -- |leader.mmr - partner.mmr|
  created_at           timestamptz DEFAULT now(),
  updated_at           timestamptz DEFAULT now()
);

CREATE INDEX idx_team_req_status_sport ON team_match_requests(status, sport_type);
```

### `team_matches` 테이블 신규
```sql
CREATE TABLE team_matches (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_a_request_id        uuid NOT NULL REFERENCES team_match_requests(id),
  team_b_request_id        uuid NOT NULL REFERENCES team_match_requests(id),
  team_a_leader_id         uuid NOT NULL REFERENCES users(id),
  team_a_partner_id        uuid NOT NULL REFERENCES users(id),
  team_b_leader_id         uuid NOT NULL REFERENCES users(id),
  team_b_partner_id        uuid NOT NULL REFERENCES users(id),
  sport_type               varchar(16) NOT NULL,
  pin_id                   uuid,
  scheduled_date           date,
  desired_time_slot        varchar(16),
  status                   varchar(16) NOT NULL DEFAULT 'PENDING_ACCEPT',
                           -- PENDING_ACCEPT / CHAT / CONFIRMED / COMPLETED / CANCELLED / DISPUTED
  chat_room_id             uuid,
  game_id                  uuid REFERENCES games(id),
  winner_team              varchar(1),  -- 'A' / 'B' / NULL(무승부/취소)
  created_at               timestamptz DEFAULT now()
);
```

### `team_score_histories` (점수 변동 이력)
```sql
CREATE TABLE team_score_histories (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id),
  team_match_id         uuid NOT NULL REFERENCES team_matches(id),
  sport_type            varchar(16),
  team_mmr_before       int,
  team_mmr_after        int,
  team_mmr_delta        int,
  team_rating_before    float,
  team_rating_after     float,
  result                varchar(8),  -- WIN / LOSS / DRAW / VOID
  created_at            timestamptz DEFAULT now()
);
```

## API 설계

```
# 팀 매칭 신청
POST   /v1/team-matches/requests
  body: { partnerId, sportType, pinId, desiredDate, desiredTimeSlot }
  → 파트너에게 푸시 → 파트너가 수락하면 status=WAITING로 큐 등록

POST   /v1/team-matches/requests/:id/partner-accept
POST   /v1/team-matches/requests/:id/partner-decline
DELETE /v1/team-matches/requests/:id                       # 큐 취소

# 매칭 성사 후 (기존 1:1과 유사)
GET    /v1/team-matches                                    # 내 팀 매치 목록
GET    /v1/team-matches/:id
POST   /v1/team-matches/:id/accept                         # 양 팀 4명 모두 수락 필요
POST   /v1/team-matches/:id/cancel
POST   /v1/team-matches/:id/confirm-met                    # 만남 인증 (4명 모두)
POST   /v1/team-matches/:id/result                         # 결과 입력 (양 팀에서 1명씩)

# 랭킹
GET    /v1/rankings/team?sportType=GOLF&pinId=...          # 팀 MMR 기준 개인 랭킹
```

## 매칭 워커

`team-matching-queue.worker.ts` 신규

```ts
// 큐에서 같은 조건 듀오 탐색
// 페어링 알고리즘:
//   1. status=WAITING, 같은 sport_type, 같은 pin or 반경, 같은 date+slot
//   2. avg_team_mmr 차이 최소화 (greedy)
//   3. 멤버 점수 분산 차이도 고려 — |teamA.diff - teamB.diff| ≤ 200
//   4. 멤버 4명 모두 서로 차단 관계 아닌지 확인
//   5. 매칭 성사 → team_matches insert + 4명 모두 푸시 + 채팅방 생성
```

## UI 흐름

```
홈 → "팀 랭크" 버튼 (1:1 랭크 옆)
 ├─ 친구 선택 (친구 목록 → 한 명 선택)
 │   └─ 친구의 팀 MMR 표시 → 차이 너무 크면 신청 버튼 비활성 + 안내
 ├─ 조건 입력 (종목/핀/날짜/시간)
 ├─ "팀 매칭 신청" → 친구에게 푸시
 └─ 친구 수락 후 → 큐 진입 화면 (WAITING)
     └─ 매칭 성사 → 4명 채팅방
```

## 엣지 케이스

| 케이스 | 처리 |
|--------|------|
| 파트너가 다른 1:1 큐 활성 상태 | 팀 매칭 신청 차단 (`이미 진행중인 매칭이 있습니다`) |
| 파트너가 다른 팀 큐 활성 상태 | 마찬가지 차단 |
| 파트너가 푸시 거절/무응답 | 30분 후 자동 만료 |
| 큐 대기 중 파트너가 탈퇴 | 자동 취소 (`CANCELLED`, reason=PARTNER_LEFT) |
| 매칭 성사 후 한 명이 거절 | 매칭 무효 → 양 팀 큐 복귀 옵션 (또는 그대로 종료) |
| 만남 인증 시 한 팀만 인증 완료 | 30분 대기 후 미인증 측 노쇼 처리 |
| 점수 차 임계값 변경 | 어드민 시스템 설정에서 조정 가능 (`system_settings.team_mmr_diff_threshold`) |

## 점수 변동 공식 (초안)

기존 1:1 Glicko-2를 그대로 차용하되, 듀오 내부에서는 다음 규칙:
- 팀 평균 MMR로 expected score 계산
- 승리 → 각 멤버에게 (개인 team_rating 대비 팀 평균과의 격차)에 비례한 추가 가중치
  - 팀 평균보다 낮은 멤버 → 상승폭 ↑ (예: +20)
  - 팀 평균보다 높은 멤버 → 상승폭 ↓ (예: +14)
- 패배 시 반대 (낮은 멤버 하락폭 작게, 높은 멤버 하락폭 크게)

수식은 1:1 Glicko-2와 호환되도록 별도 RDB 컬럼 set으로 보관.

## 어드민 추가 사항

- 시스템 설정에 팀 랭크 파라미터 추가
  - `teamMmrDiffThreshold` — 듀오 내부 점수차 한계 (기본 300)
  - `teamMatchRadiusKm` — 팀 매칭 기본 반경 (기본 10)
  - `teamMatchExpiryHours` — 큐 자동 만료 시간 (기본 4)
- 팀 매칭 목록/상세 조회 페이지
- 분쟁/신고 처리 (4명 단위)

## 마일스톤

1. DB 스키마 + 마이그레이션 + Glicko-2 팀 컬럼 시딩
2. 팀 매칭 큐 워커 (페어링 알고리즘) + 단위 테스트
3. API — 신청 → 수락 → 큐 → 매칭 성사 → 결과 입력 흐름
4. 앱 UI — 친구 선택 + 큐 진입 + 4인 채팅방
5. 점수 변동 공식 튜닝 (시즌 베타)
6. 어드민 설정 + 분쟁 처리
7. 팀 랭킹 화면 (전국/지역/핀)

## 비-목표 (Out of Scope)

- 3인 이상 팀 (기존 "팀 기능"이 별개로 존재)
- 토너먼트/대회 (별도 기획)
- 듀오 친밀도 시스템 (선택적 후속)
- 음성 채팅
