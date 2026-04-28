# 푸시 알림 활성화 캠페인 기획서

> 작성일: 2026-04-27
> 최종 수정: 2026-04-27
> 상태: **✅ 구현 완료 + 운영 배포 완료**
> 목적: 휴면·저활동 유저를 매칭 활동으로 끌어들여 DAU·매칭 발생률을 끌어올린다.

## 변경 이력
- 2026-04-27 v1.0 초안 작성
- 2026-04-27 v1.1 구현 완료, 운영 배포 (rank-drop 회복 로직 1건 코드 리뷰에서 수정)

---

## 1. 배경 & 목적

- 가입 후 한 번도 매칭하지 않은 유저, 매칭하다가 끊긴 유저, 점수가 떨어져 의욕이 꺾인 유저가 누적되고 있음
- 적절한 푸시 알림으로 재참여를 유도하되, **알림 피로도(notification fatigue)** 로 인한 알림 차단·앱 삭제는 최소화

### 핵심 KPI
| 지표 | 목표 |
|---|---|
| 캠페인 알림 CTR | 15% 이상 |
| 알림 → 24h 내 매칭 신청 전환율 | 8% 이상 |
| 알림 설정 opt-out 비율 | 5% 미만 |

---

## 2. 알림 종류 (3종)

### A. 매칭 권유 — 활동 유저용 (`INACTIVE_2D`)

| 항목 | 내용 |
|---|---|
| 트리거 | 마지막 경기 또는 마지막 매칭 신청 후 **2일 경과** |
| 발송 주기 | 한 번 보낸 뒤 **3일 쿨다운** (휴면 지속 시 D+2, D+5, D+8…) |
| 발송 시각 | 매일 **저녁 18:00 KST** |
| 종료 조건 | 유저가 매칭 신청하면 자동 리셋 |

**메시지 예시**
- 1차: `"3일 전에 마지막 경기를 했어요. 오늘 한 판 어때요?"`
- 2차 이후: `"오랜만이에요 👋 새로 들어온 상대가 기다리고 있어요"`

**딥링크**: `/matches/create`

---

### B. 매칭 권유 — 미경험 유저용 (`NEW_USER_NUDGE`)

| 항목 | 내용 |
|---|---|
| 트리거 | 가입 완료 후 첫 매칭 신청을 **한 번도 안 한** 유저 |
| 발송 주기 | 가입 후 **3일째부터 3일마다** (D+3, D+6, D+9), **최대 3회** |
| 발송 시각 | 매일 **저녁 18:00 KST** |
| 종료 조건 | 유저가 첫 매칭 신청하면 즉시 종료 / 또는 3회 발송 완료 |

> ⚠ 9일 이후로는 발송 안 함. 그 시점이면 일반적으로 알림 채널이 차단되어 있어 효과가 미미함.

**메시지 예시**
- 1차 (D+3): `"아직 첫 매칭 전이에요. 근처 상대를 찾아보세요!"`
- 2차 (D+6): `"우리 동네 핀에 OO명이 활동 중이에요 🏌"`

**딥링크**: `/matches/create`

---

### C. 랭킹 하락 알림 (`RANK_DROP`)

| 항목 | 내용                                   |
|---|--------------------------------------|
| 트리거 | 24h 누적 변화가  **핀랭킹 5위 이상 하락**         |
| 발송 주기 | **종목 통합 3일에 1회** 쿨다운 (도배 방지)         |
| 발송 시각 | 트리거 발생 다음 날 **저녁 18:00** (즉시 X — 배치) |
| 종료 조건 | 점수가 회복(트리거 시점 이상)되면 쿨다운 무시하고 알림 종료   |

**메시지 예시**
- `"⚠ 골프 랭킹이 12위에서 18위로 떨어졌어요. 한 판으로 회복!"`
- `"점수가 1432→1398로 내려갔어요. 다시 올려볼까요? 🔥"`

**딥링크**: `/matches/create?sportType=GOLF`

---

## 3. 데이터 모델

### 3-1. 신규 테이블: `notification_campaign_logs`

유저별 캠페인 알림 발송 이력 — 쿨다운 계산 + 효과 측정용.

```sql
CREATE TABLE notification_campaign_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  campaign_type VARCHAR(40) NOT NULL,
    -- 'INACTIVE_2D' | 'NEW_USER_NUDGE' | 'RANK_DROP'
  context JSONB NOT NULL DEFAULT '{}',
    -- 예: {"sportType":"GOLF","scoreBefore":1432,"scoreAfter":1398}
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  push_clicked_at TIMESTAMPTZ,           -- 효과 측정
  resulting_match_request_id UUID        -- 알림 받고 24h 내 매칭 신청했는지
);

CREATE INDEX idx_ncl_user_type_sent
  ON notification_campaign_logs(user_id, campaign_type, sent_at DESC);
```

### 3-2. `notification_settings` 컬럼 추가

유저가 캠페인 알림만 따로 끌 수 있게:

```sql
ALTER TABLE notification_settings
  ADD COLUMN inactive_nudge BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN rank_drop_alert BOOLEAN NOT NULL DEFAULT TRUE;
```

### 3-3. 점수 스냅샷 (랭킹 하락 감지)

이미 `score_histories`에 점수 변화가 기록되어 있어 별도 스냅샷 테이블 불필요. `score_histories`에서 24h 윈도우 누적 변화를 합산해서 판단.

---

## 4. 구현 — 워커 (BullMQ Cron)

### 4-1. 신규 워커: `notification-campaign.worker.ts`

서버 시작 시 BullMQ에 cron job 3개 등록.

```typescript
// 매일 18:00 KST = UTC 09:00
const CRON_18KST = '0 9 * * *';

await campaignQueue.add('rank-drop',      {}, { repeat: { pattern: CRON_18KST } });
await campaignQueue.add('inactive-2d',    {}, { repeat: { pattern: CRON_18KST } });
await campaignQueue.add('new-user-nudge', {}, { repeat: { pattern: CRON_18KST } });
```

### 4-2. 각 잡 처리 로직 (의사코드)

#### A. inactive-2d
```sql
-- 마지막 활동(매칭 신청 또는 경기) 후 2일 이상 경과한 활성 유저
SELECT u.id
FROM users u
WHERE u.status = 'ACTIVE'
  AND COALESCE(
        (SELECT MAX(created_at) FROM match_requests WHERE requester_id = u.id),
        '1970-01-01'
      ) < NOW() - INTERVAL '2 days'
  -- 한 번이라도 매칭 신청한 적 있는 유저만 (가입 직후 유저는 캠페인 B에서 처리)
  AND EXISTS (SELECT 1 FROM match_requests WHERE requester_id = u.id)
  -- 3일 쿨다운
  AND NOT EXISTS (
    SELECT 1 FROM notification_campaign_logs
    WHERE user_id = u.id AND campaign_type = 'INACTIVE_2D'
      AND sent_at > NOW() - INTERVAL '3 days'
  )
  -- 알림 설정 ON
  AND (SELECT inactive_nudge FROM notification_settings WHERE user_id = u.id) = TRUE
```

#### B. new-user-nudge
```sql
SELECT u.id
FROM users u
WHERE u.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM match_requests WHERE requester_id = u.id)
  AND u.created_at < NOW() - INTERVAL '3 days'
  AND u.created_at > NOW() - INTERVAL '12 days'   -- 3,6,9일째만
  AND (
    SELECT COUNT(*) FROM notification_campaign_logs
    WHERE user_id = u.id AND campaign_type = 'NEW_USER_NUDGE'
  ) < 3
  AND NOT EXISTS (
    SELECT 1 FROM notification_campaign_logs
    WHERE user_id = u.id AND campaign_type = 'NEW_USER_NUDGE'
      AND sent_at > NOW() - INTERVAL '3 days'
  )
```

#### C. rank-drop
```sql
-- 24h 누적 점수 변화 -30 이상
SELECT sp.user_id, sp.sport_type, SUM(sh.score_change) AS delta
FROM score_histories sh
JOIN sports_profiles sp ON sp.id = sh.sports_profile_id
WHERE sh.created_at > NOW() - INTERVAL '24 hours'
GROUP BY sp.user_id, sp.sport_type
HAVING SUM(sh.score_change) <= -30
```

각 (user_id, sport_type)별 3일 쿨다운 체크 후 발송.

### 4-3. 알림 발송 — 기존 `NotificationService.send()` 재사용

```typescript
await notificationService.send({
  userId,
  type: 'CAMPAIGN_INACTIVE_2D',
  title: '오늘 한 판 어떠세요?',
  body: '마지막 경기 후 3일이 지났어요. 근처 상대를 찾아보세요!',
  data: { deepLink: '/matches/create' },
});

// 로그 기록
await campaignLogRepo.insert({ userId, campaignType: 'INACTIVE_2D' });
```

---

## 5. 알림 피로도 방지 — 글로벌 가드

한 유저가 여러 캠페인에 동시 해당될 수 있으므로 **하루 최대 1건의 캠페인 알림**만 발송.

### 우선순위
`RANK_DROP` > `INACTIVE_2D` > `NEW_USER_NUDGE`

### 워커 실행 순서
rank-drop → inactive-2d → new-user-nudge 순서로 실행. 각 워커가 발송 전에 오늘 발송 이력 확인:

```typescript
const sentToday = await query(`
  SELECT 1 FROM notification_campaign_logs
  WHERE user_id = $1 AND sent_at::date = CURRENT_DATE LIMIT 1
`);
if (sentToday) return; // skip
```

---

## 6. 기존 알림 설정 화면 변경

`/profile/settings/notifications` (`notification_settings_screen.dart`) 토글 2개 추가:

- "휴면 알림 받기" → `inactive_nudge`
- "랭킹 하락 알림 받기" → `rank_drop_alert`

> OS 푸시 권한이 꺼져 있으면 어차피 안 가지만, 앱 내 설정도 분리해서 정밀 제어 가능.

---

## 7. 효과 측정 (KPI)

`notification_campaign_logs.push_clicked_at` 와 `resulting_match_request_id` 컬럼으로 후속 행동 추적.

| 지표 | 측정 방법 | 목표 |
|---|---|---|
| **CTR** | `push_clicked_at IS NOT NULL` / 발송 수 | 15% 이상 |
| **CVR** | `resulting_match_request_id IS NOT NULL` / 발송 수 | 8% 이상 |
| **Opt-out** | `notification_settings.inactive_nudge = FALSE` 비율 | 5% 미만 |

어드민 대시보드에 캠페인 타입별 일별 발송/CTR/CVR 차트 추가.

---

## 8. 단계별 출시 (Phased)

| 단계 | 내용 | 예상 기간 |
|---|---|---|
| **Phase 1** | 테이블/스키마/설정 토글 + A(inactive-2d) 워커 | 1일 |
| **Phase 2** | B(new-user-nudge) 워커 추가 | 1일 |
| **Phase 3** | C(rank-drop) 워커 추가 | 1.5일 |
| **Phase 4** | 어드민 KPI 대시보드 + 메시지 A/B 테스트 | 2일 |

---

## 9. 리스크 & 대응

| 리스크 | 대응 |
|---|---|
| 푸시 차단 → 알림 무용 | 인앱 알림(`notifications` 테이블)도 함께 적재해서 알림 탭에서도 노출 |
| 저녁 6시 일괄 발송 → BullMQ 부하 | `chunk(100)` 배치 + 발송 사이 100ms sleep |
| 캠페인 타입 추가 시 코드 분기 증가 | `CampaignType` enum + 전략 패턴(`Map<type, handler>`) |
| 같은 유저에게 같은 메시지 반복 | `messageVariants[]` 5종 랜덤 + 직전 본문 중복 회피 |
| 알림 설정 OFF 후에도 발송되는 사고 | 워커 SQL `WHERE` 절에 설정 체크 필수 + 단위 테스트 |

---

## 10. 채택된 결정사항 (구현 완료)

- [x] 발송 시각: **매일 18:00 KST** (UTC 09:00, cron `0 9 * * *`)
- [x] 랭킹 하락 트리거: **핀랭킹 5위 이상 하락만** (점수 -30 트리거 제외)
- [x] **한 번에 전체 출시** (Phase 분할 X)
- [x] A/B 테스트 인프라 미도입 (메시지 5종 랜덤만)
- [x] 캠페인 알림 단일 `CAMPAIGN` 타입으로 통합 (서브 분기는 `notification_campaign_logs.campaign_type`만)
- [x] 미경험 유저: D+3/6/9 그대로 (D+1 추가 X)
- [x] 랭킹 회복 시 쿨다운 무시 (회복 이력 있으면 즉시 알림 가능)

## 10-1. 코드 리뷰 단계 발견 사항 (수정 완료)

- 🐛 **rank-drop 회복 로직 정반대 동작**: `rankAfter < rankAtSend` (현재 회복 중)을 `rankBefore < rankAtSend` (어제 회복 이력)으로 수정. SQL이 이미 "오늘 5위 이상 하락" 케이스만 통과시키므로, 도달 시점에 회복 이력만 보면 정확.
- 🧹 `processRankingSnapshot`의 unused `today` 변수 제거 (`ON CONFLICT DO NOTHING`이 idempotent 보장).

---

## 11. 구현 산출물

### 신규/수정 파일
- **신규**: `server/src/workers/notification-campaign.worker.ts` (BullMQ Queue + Worker + 4개 cron)
- **신규**: `server/src/entities/notification-campaign-log.entity.ts`
- **신규**: `server/src/entities/pin-ranking-snapshot.entity.ts`
- **수정**: `server/src/server.ts` (마이그레이션 5종 + 워커 등록)
- **수정**: `server/src/shared/types/index.ts` (NotificationType `CAMPAIGN` 추가)
- **수정**: `server/src/modules/notifications/notification.service.ts` (TYPE_TO_SETTING 매핑)
- **수정**: `server/src/modules/notifications/notification.routes.ts` (GET `/notifications/settings` 추가 + 새 토글 처리)
- **수정**: `server/src/entities/notification-settings.entity.ts` (`inactiveNudge`, `rankDropAlert` 컬럼)
- **수정**: `app/lib/models/notification.dart` (새 필드 매핑)
- **수정**: `app/lib/screens/profile/notification_settings_screen.dart` (토글 2개)

### 마이그레이션 (server.ts 부팅 시 idempotent ALTER/CREATE)
```sql
ALTER TABLE notification_settings
  ADD COLUMN IF NOT EXISTS inactive_nudge BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS rank_drop_alert BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS notification_campaign_logs (...);
CREATE TABLE IF NOT EXISTS pin_ranking_snapshots (...);
-- 인덱스 2개
```

### Cron 잡 스케줄
| 잡 이름 | 시각 | 역할 |
|---|---|---|
| `ranking-snapshot` | UTC 15:00 (KST 00:00) | `ranking_entries` → `pin_ranking_snapshots` 복사 |
| `rank-drop` | UTC 09:00 (KST 18:00) | 어제 스냅샷 vs 오늘 비교, 5위+ 하락 알림 |
| `inactive-2d` | UTC 09:00 (KST 18:00) | 마지막 매칭 2일 경과 유저 알림 |
| `new-user-nudge` | UTC 09:00 (KST 18:00) | 미경험 유저 D+3/6/9 알림 (최대 3회) |

### 테스트 환경 변수 (오버라이드)
- `CAMPAIGN_DAILY_CRON` (기본 `0 9 * * *`) — 캠페인 cron 시각
- `CAMPAIGN_SNAPSHOT_CRON` (기본 `0 15 * * *`) — 스냅샷 cron 시각

### 관련 파일 (참조)
- BullMQ 패턴: `server/src/workers/match-expiry.worker.ts`, `auto-resolve.worker.ts`
- 알림 목록 화면: `app/lib/screens/profile/notification_list_screen.dart`
