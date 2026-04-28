# 노쇼 처리 개편 + 매너 점수 연동 기획서

> 작성일: 2026-04-27
> 최종 수정: 2026-04-27
> 상태: **✅ 구현 완료 + 운영 배포 완료 + E2E 테스트 PASS (8/8)**
> 목적: 노쇼 신고 즉시 자동 패널티 → **관리자 검토 후 확정** 흐름으로 전환. 노쇼 확정 결과를 매너 점수에 연동해 평판 시스템 일원화.

## 변경 이력
- 2026-04-27 v1.0 초안 작성
- 2026-04-27 v1.1 매너 기획서와 통합 구현
- 2026-04-27 v1.2 코드 리뷰 2건 수정:
  - `manner_ratings` UNIQUE 제약에 `source` 추가 (USER + NOSHOW_AUTO 동시 저장 가능)
  - `rejectNoshowReport` 알림 type 라벨링 수정 (`NOSHOW_REPORT_RECEIVED` → `NOSHOW_REPORT_REJECTED`)
- 2026-04-27 E2E 통합 테스트 8/8 PASS, 운영 배포 완료

---

## 1. 배경 & 현황

### 현재 흐름 (자동 즉시 처리)
1. 유저 A가 매칭 화면에서 "노쇼 신고" 버튼 → 사진 첨부 후 제출
2. 서버 `reportNoshow` (`matching.service.ts:2281~`):
   - 상대 `noShowCount += 1`
   - 상대 `match_ban_until = +7일` (즉시 매칭 차단 + 매칭중인 것들 전부 취소 + 상대방에게 푸시 알림 필요+ 알림)
   - 상대 `displayScore -30` / 신고자 `displayScore +15` 즉시 반영
   - `Report` 테이블에 사진 포함 레코드 INSERT (이미 있는 경우)
   - 매칭 상태 `COMPLETED` 처리
3. 어드민 `NoshowReportPage`는 **사후 조회만** 가능 (이미 패널티 적용됨)

### 문제점
- **검토 없이 즉시 패널티** → 보복성/허위 신고 시 무고한 유저 즉시 7일 매칭 차단
- 신고자에게 +15점 보상도 즉시 → 악용 인센티브 (담합 가능)
- 관리자 페이지는 "확인용"이지 "결정 권한 없음"
- 매너 점수 시스템과 별도로 운영되어 평판 데이터 분산

### 기존 어드민 페이지
`admin/src/pages/matches/NoshowReportPage.tsx` 존재하나 신고 목록 조회/상태 표시만 있고 승인/기각 액션 없음.

---

## 2. 목표 & 비목표

### 목표
1. 노쇼 신고 → **PENDING(대기)** 상태로 들어감. 패널티 즉시 적용 X
2. 관리자가 어드민에서 신고 검토 후 **승인/기각/유보** 결정
3. 승인 시에만 패널티 적용 + 매너 점수에도 반영
4. 기각 시 무효 처리 (악의적 신고일 경우 신고자 페널티 옵션)
5. 매너 점수 시스템과 연동 — 노쇼 확정 = 매너 1점 평가와 동등 효과

### 비목표
- 신고 자체를 막지 않음 (모든 신고는 일단 접수)
- 자동 분석/AI 판정 도입 X (수동 검토 우선, 향후 추가 가능)
- 관리자 부재 시 자동 처리 X (체계 명확화 우선)

---

## 3. 새 처리 흐름

```
유저 A 노쇼 신고 (사진 첨부)
        ↓
  NoShowReport.status = PENDING
        ↓
  매칭 상태: 'COMPLETED' (그대로 — 매칭 종결은 즉시)
  상대방: 가벼운 임시 제한 (선택, 아래 4-3)
        ↓
  관리자 알림 (Slack / 어드민 대시보드 카운트)
        ↓
   [관리자 검토 — 보통 24h 이내]
        ↓
  ┌─ APPROVED ────┐  ┌─ REJECTED ──┐  ┌─ INSUFFICIENT ─┐
  │ 패널티 적용     │  │ 무효 처리    │  │ 추가 자료 요청   │
  │ + 매너 평가 누적 │  │ (선택: 신고자 │  │ (대기 유지)     │
  │ + 신고자 보상   │  │  페널티)     │  │                │
  └────────────────┘  └──────────────┘  └────────────────┘
```

---

## 4. 데이터 모델

### 4-1. 신규 테이블: `noshow_reports`
기존 `reports` 테이블에 통합할 수도 있으나, 노쇼는 후속 액션이 많아 별도 분리 권장.

```sql
CREATE TABLE noshow_reports (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id           UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  reporter_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_profile_id UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
  status             VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    -- 'PENDING' | 'APPROVED' | 'REJECTED' | 'INSUFFICIENT'
  evidence_urls      TEXT[] NOT NULL DEFAULT '{}',
  reporter_message   TEXT,
  admin_id           UUID REFERENCES admin_accounts(id),
  admin_decision_at  TIMESTAMPTZ,
  admin_memo         TEXT,
  -- 결과 적용 스냅샷 (감사 로그)
  applied_score_change INT,
  applied_ban_hours    INT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_noshow_status_created ON noshow_reports(status, created_at DESC);
CREATE INDEX idx_noshow_reported_user ON noshow_reports(reported_user_id, status);
```

### 4-2. `sports_profiles`에 컬럼 추가 (선택)
누적 노쇼 확정 건수 추적:
```sql
ALTER TABLE sports_profiles
  ADD COLUMN IF NOT EXISTS noshow_confirmed_count INT NOT NULL DEFAULT 0;
```
> 기존 `no_show_count`는 신고만 있어도 카운트되므로 폐지 또는 의미 변경.
> 새 컬럼은 **확정된** 노쇼만 카운트.

### 4-3. 임시 제한 (선택)
신고 접수 시 즉시 가벼운 제한 적용 여부 결정:
- **안 2**: PENDING 동안 매칭 신청만 차단 (24h) — 보복은 막되 무고일 경우 풀어주기.

---

## 5. 매너 점수 연동

노쇼 신고 = 그 매칭에서 **매너 1점 강제 부여**로 통합 처리. 별도 매너 평가 UI를 노쇼 보고서와 분리하지 않음.

### 노쇼 확정(APPROVED) 시 매너 점수 처리
1. 노쇼 유저의 `sports_profiles`:
   ```
   manner_total += 1   -- 1점 평가
   manner_count += 1
   ```
2. 신고자가 같은 매칭에 일반 매너 평가를 이미 입력했다면 **덮어쓰기** (1점으로 강제 하향)
3. → 매너 평균 자동 하락 → [매너 매칭 기획서](./manner-score-matching-plan.md)와 연동되어 매칭 cost 페널티

### 노쇼 기각(REJECTED) 시
- 신고자가 입력했던 매너 점수가 1점이었다면 무효 처리 (선택) **해줘 이거
- 기본은 매너 점수 변경 안 함

### 효과
- 매너 시스템 단일 채널화 — 노쇼는 자동으로 매너 평판에 반영
- 노쇼 누적 = 매너 등급 하락 = 매칭 cost 페널티 (기획서 참조)
- 별도 "노쇼 카운터 + 매너 점수" 두 채널 → 매너 점수 단일 채널

---

## 6. 패널티 정책

### 6-1. APPROVED 시
| 대상 | 효과 |
|---|---|
| 노쇼 유저 | `noshow_confirmed_count += 1` |
| 노쇼 유저 | `match_ban_until` 자동 산정 (확정 누적 횟수 기반, 아래 6-2) |
| 노쇼 유저 | `displayScore -30`, `currentScore -30` (최소 100) |
| 노쇼 유저 | 매너 점수 1점 강제 평가 (5-1 참조) |
| 신고자 | `displayScore +15`, `currentScore +15` |
| 양측 | 알림 발송 (`MATCH_NO_SHOW_PENALTY` / `MATCH_NO_SHOW_COMPENSATION`) |

### 6-2. 누적 확정 횟수에 따른 자동 밴 기간
| 누적 확정 횟수 | 매칭 차단 기간 |
|----------|---|
| 1회       | 24시간 |
| 2회 이상    | **영구 정지** (관리자 별도 결정) |

> 기존 자동 7일 일괄 적용 → 누적 횟수 기반 단계화

### 6-3. REJECTED 시
| 옵션 | 내용 |
|---|---|
| 기본 | 무효 처리. 패널티 적용 안 함 |
| **악의적 신고 판단 시** | 관리자가 토글로 신고자 패널티 적용 가능 — `displayScore -10` + 7일 신고 자격 차단 |

### 6-4. INSUFFICIENT 시
- "증거 부족" — 추가 자료 요청 알림 발송
- 신고자에게 "사진/메시지 추가" 버튼 노출 (어드민이 PENDING으로 되돌릴 수 있음)
- 7일 경과 시 자동 REJECTED

---

## 7. 어드민 페이지 개편

### 기존 페이지: `admin/src/pages/matches/NoshowReportPage.tsx`
조회만 가능 → **결정 권한 부여**

### 추가 기능
1. **목록 필터**: PENDING/APPROVED/REJECTED/INSUFFICIENT
2. **PENDING 카운트 배지** — AdminLayout 사이드바 "노쇼 신고" 메뉴 옆
3. **상세 모달에 액션 버튼**:
   - ✅ **승인** (APPROVED) — 모달로 메모 입력 + 확인
   - ❌ **기각** (REJECTED) — 모달로 메모 입력 + (체크박스) "악의적 신고로 판단"
   - 📝 **자료 요청** (INSUFFICIENT) — 메모 + 신고자에게 알림
4. **컨텍스트 정보 노출**:
   - 매칭 상세 (시간/장소/종목)
   - 양측 채팅 마지막 메시지 5건 (이미 있음)
   - 신고된 유저의 누적 노쇼 확정 횟수
   - 신고자의 누적 신고 횟수 + 승인률 (보복성 신고 판단용)
   - 양측 매너 점수 평균
5. **일괄 처리** (선택): 체크박스로 여러 건 선택 후 일괄 기각

### 권한
- `AdminRole.MODERATOR` 이상만 승인/기각 가능
- 영구 정지(10회 이상)는 `AdminRole.SUPER_ADMIN` 별도 확인

---

## 8. 신고자 측 흐름 변경

### 현재 (신고 즉시 모든 패널티 적용)
유저는 "신고했더니 바로 -점수 + 7일 차단됐네" 라는 보복성 신고로 악용 가능

### 변경 후
1. 신고 시 토스트: `"노쇼 신고가 접수되었습니다. 관리자 검토 후 결과를 알려드릴게요."`
2. 어드민 결정 시 알림 발송:
   - APPROVED → `"노쇼 신고가 승인되었습니다. +15점 보상이 적용되었습니다."`
   - REJECTED → `"노쇼 신고가 기각되었습니다. 자세한 내용은 1:1 문의로 확인해주세요."`
   - INSUFFICIENT → `"증거 자료가 부족합니다. 추가 자료를 첨부해주세요."`

### 신고 제한
- 같은 매칭에 대해 신고 1회만 가능 (이미 그런 듯)
- 같은 유저가 같은 상대를 24h 내 다중 신고 불가

---

## 9. 마이그레이션 전략

### 기존 데이터
- `reports` 테이블에 reason='NOSHOW'로 적재된 기존 데이터 → `noshow_reports`로 백필
- 백필 시 모든 기존 데이터는 `status = 'APPROVED'`로 (이미 패널티 적용됐으므로)
- `sports_profiles.no_show_count` → `noshow_confirmed_count`로 복사

### 코드 변경
1. 기존 `reportNoshow` 메서드 변경:
   - **즉시 패널티 적용 부분 제거**
   - `noshow_reports` INSERT만 수행 (status = PENDING)
   - 매칭 상태 COMPLETED는 유지 (매칭 종결은 즉시)
2. 신규 메서드:
   - `approveNoshowReport(reportId, adminId, memo)`
   - `rejectNoshowReport(reportId, adminId, memo, reporterPenalty?)`
   - `requestMoreEvidence(reportId, adminId, memo)`
3. 어드민 라우트:
   - `POST /admin/noshow-reports/:id/approve`
   - `POST /admin/noshow-reports/:id/reject`
   - `POST /admin/noshow-reports/:id/insufficient`
   - `GET /admin/noshow-reports?status=PENDING&...`

---

## 10. 알림 (관리자 측)

신고 접수 시 관리자 부재로 인한 처리 지연 방지:
- 옵션 A: Slack 웹훅으로 신규 신고 알림
- 옵션 B: 어드민 대시보드 상단에 "처리 대기 N건" 배지
- 옵션 C: 24h 이상 PENDING 건은 어드민에게 매일 9시 메일 요약

> 권장: 옵션 B + C (Slack 의존 X, 자체 어드민 시스템 활용)

---

## 11. 효과 측정 (KPI)

| 지표 | 측정 방법 | 목표 |
|---|---|---|
| 신고 승인률 | APPROVED / 전체 처리 건수 | 60~80% (너무 높으면 검토가 느슨, 너무 낮으면 신고 남용) |
| 평균 처리 시간 | `admin_decision_at - created_at` 평균 | 24시간 이내 |
| PENDING 누적 | 매일 자정 카운트 | 50건 미만 |
| 보복성 신고 적발 | REJECTED + reporter_penalty 적용 비율 | 5% 미만 (있다는 것 자체가 효과 측정) |
| 노쇼 확정자 재범률 | 첫 확정 후 30일 내 재확정 비율 | 도입 전 대비 30% 감소 |

---

## 12. 리스크 & 대응

| 리스크 | 대응 |
|---|---|
| 관리자 부재 → PENDING 누적 | 24h+ 미처리 건 자동 알림 + 신고자 알림 ("검토 지연 중") |
| 검토 전까지 노쇼 유저가 다른 유저에게도 노쇼 | PENDING 동안 임시 제한 (옵션 4-3 안 3) |
| 어드민 임의 처리 (악용) | 모든 결정에 admin_id 기록 + admin_memo 필수 + 감사 로그 |
| 신고자 "왜 안 처리되냐" 불만 | 어드민 페이지 SLA 24h 명시 + 알림으로 진행 상황 공유 |
| 기존 즉시 처리에 익숙한 유저 반발 | 출시 공지 + "검토는 하루 내" 명확히 안내 |

---

## 13. 구현 범위

### 서버 (`server/`)
1. **마이그레이션** (`server.ts`):
   - `noshow_reports` 테이블 신설
   - `sports_profiles.noshow_confirmed_count` 컬럼 추가
   - 기존 데이터 백필 스크립트 (`scripts/migrate-noshow-reports.ts`)
2. **엔티티**: `noshow-report.entity.ts`, `notification-noshow-status.entity.ts`(선택)
3. **`matching.service.ts`**:
   - `reportNoshow` 변경 — INSERT만, 패널티 제거
   - 신규 메서드 3개 (approve/reject/insufficient)
4. **어드민 라우트** (`modules/admin/admin-matches.routes.ts` 또는 신설):
   - `GET /admin/noshow-reports`
   - `POST /admin/noshow-reports/:id/approve|reject|insufficient`
5. **알림 발송**: APPROVED/REJECTED/INSUFFICIENT 시 신고자 알림

### 어드민 (`admin/`)
1. `pages/matches/NoshowReportPage.tsx`:
   - 액션 버튼 3개 (승인/기각/자료 요청)
   - 액션 모달 + 메모 입력
   - 필터 (PENDING 기본)
2. `AdminLayout.tsx`: 사이드바 "노쇼 신고"에 PENDING 카운트 배지
3. (선택) 24h+ 미처리 건 상단 경고 배너

### 앱 (`app/`)
1. 노쇼 신고 후 토스트 메시지 변경: `"검토 후 알려드릴게요"`
2. 알림 처리: `MATCH_NOSHOW_REPORT_APPROVED`, `MATCH_NOSHOW_REPORT_REJECTED`, `MATCH_NOSHOW_REPORT_INSUFFICIENT` 타입 추가
3. (선택) 마이페이지 → 내 신고 내역 화면

---

## 14. 채택된 결정사항 (구현 완료)

### 처리 흐름
- [x] PENDING 동안 임시 제한: **매칭 신청만 차단 24h** (`match_request_ban_until` 컬럼)
- [x] INSUFFICIENT 자동 REJECTED 전환: **7일** (cleanup 워커가 매일 00:00 KST 처리)
- [x] 같은 유저 → 같은 상대 **24시간 내 1번만** 신고 가능

### 패널티
- [x] 누적 확정 횟수 기반 밴 기간: **1회 → 7일 / 2회 이상 → 영구 정지(SUSPENDED)**
- [x] 영구 정지는 **SUPER_ADMIN만 결정 가능** — MODERATOR가 시도 시 422 (`SUPER_ADMIN_REQUIRED`)
- [x] REJECTED 시 악의적 신고자 페널티: **`displayScore -10` + `noshow_report_ban_until +7일`**

### 매너 연동
- [x] APPROVED 시 매너 1점 강제 부여 — **추가 누적** 방식 (`manner_total += 1, manner_count += 1`)
- [x] 별도 `manner_ratings` 테이블 신설 — `source` 컬럼으로 `USER` / `NOSHOW_AUTO` 구분
- [x] REJECTED 시 신고자가 같은 매칭에 입력한 USER 매너 평가 **자동 무효 처리** (`voided_at` 세팅 + `sports_profiles` 차감)

### 어드민
- [x] PENDING 카운트 배지 (사이드바, 1분 폴링)
- [x] 일괄 기각 (체크박스 선택 후 모달)
- [x] 24h+ 미처리 시각 표시
- [ ] Slack 웹훅 — 향후 작업 (이번 출시 X)

### 마이그레이션
- [x] 기존 `reports.NOSHOW` 데이터 → `noshow_reports(status=APPROVED)` 백필 스크립트 (`scripts/migrate-noshow-reports.ts`)
- [x] `sports_profiles.no_show_count` → `noshow_confirmed_count` 복사 (보존, 신규 코드는 `noshow_confirmed_count` 사용)
- 운영 RDS 검증: 기존 NOSHOW reports 0건이라 백필 영향 없음

---

## 15. 구현 산출물

### 신규 파일
- `server/src/entities/noshow-report.entity.ts`
- `server/src/entities/manner-rating.entity.ts` (UNIQUE에 `source` 포함)
- `server/src/modules/admin/admin-noshow.routes.ts` (6개 엔드포인트)
- `server/src/workers/noshow-cleanup.worker.ts` (매일 KST 02:00 실행)
- `server/scripts/migrate-noshow-reports.ts` (멱등 백필)
- `server/tests/test-noshow-manner-e2e.ts` (E2E 통합 테스트)

### 수정 파일
- **server**:
  - `entities/sports-profile.entity.ts` — `noshow_confirmed_count`, `match_request_ban_until`
  - `entities/user.entity.ts` — `noshow_report_ban_until`
  - `entities/index.ts` — 신규 export
  - `shared/types/index.ts` — NotificationType 5개 추가
  - `modules/notifications/notification.service.ts` — TYPE_TO_SETTING 매핑
  - `modules/matching/matching.service.ts` — `reportNoshow` 재작성 + `approve/reject/insufficient` 신규
  - `modules/games/games.service.ts` — `manner_ratings` INSERT + 트랜잭션
  - `workers/matching-queue.worker.ts` — 매너 cost 보정 + `match_request_ban_until` 필터
  - `app.ts` — `adminNoshowRoutes` 등록
  - `server.ts` — 마이그레이션 5종 + cleanup 워커 등록
- **admin**:
  - `api/matches.api.ts` — NoshowReport 타입 개편 + 5개 mutation 추가
  - `hooks/useMatches.ts` — 5개 React Query hook 추가
  - `pages/matches/NoshowReportPage.tsx` — 액션 버튼 + 일괄 기각 + 컨텍스트 카드
  - `layouts/AdminLayout.tsx` — PENDING 카운트 배지 (1분 폴링)
- **app**:
  - `screens/matching/match_detail_screen.dart` — 토스트 메시지 변경
  - `screens/profile/notification_list_screen.dart` — 신규 5종 알림 아이콘/색상

### 신규 API
| 메서드 | 경로 | 권한 | 설명 |
|---|---|---|---|
| GET | `/admin/noshow-reports` | MODERATOR | 목록 (컨텍스트 정보 포함) |
| GET | `/admin/noshow-reports/pending-count` | MODERATOR | PENDING 카운트 배지용 |
| POST | `/admin/noshow-reports/:id/approve` | MODERATOR (2회+ APPROVED는 SUPER_ADMIN) | 승인 |
| POST | `/admin/noshow-reports/:id/reject` | MODERATOR | 기각 (`reporterPenalty` 옵션) |
| POST | `/admin/noshow-reports/:id/insufficient` | MODERATOR | 자료 요청 |
| POST | `/admin/noshow-reports/bulk-reject` | MODERATOR | 일괄 기각 |

### 마이그레이션 SQL (server.ts 부팅 시 idempotent)
```sql
CREATE TABLE IF NOT EXISTS noshow_reports (...);
CREATE TABLE IF NOT EXISTS manner_ratings (...);  -- UNIQUE (match_id, rater_id, rated_user_id, source)
ALTER TABLE sports_profiles
  ADD COLUMN IF NOT EXISTS noshow_confirmed_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS match_request_ban_until TIMESTAMPTZ;
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS noshow_report_ban_until TIMESTAMPTZ;
-- 인덱스 4종
```

### E2E 테스트 결과 (`server/tests/test-noshow-manner-e2e.ts`)
| # | 시나리오 | 결과 |
|---|---|---|
| S1 | 노쇼 신고 접수 (PENDING + 임시 차단 24h) | ✅ PASS |
| S2 | 24h 내 중복 신고 차단 | ✅ PASS |
| S3 | 어드민 승인 (1회, 7일 ban + 매너+1 + 신고자+15) | ✅ PASS |
| S4 | 어드민 기각 (USER 평가 voided + manner_total 차감) | ✅ PASS |
| S5 | 악의적 기각 (신고자 -10 + 신고자격 7일 차단) | ✅ PASS |
| S6 | 신고 자격 차단 유저의 신고 거부 | ✅ PASS |
| S7 | 자료 요청 (INSUFFICIENT) | ✅ PASS |
| S8 | 매너 등급 분류 + cost 매트릭스 | ✅ PASS |

회귀 테스트 실행:
```bash
ssh ec2-user@43.203.165.114 "cd ~/spots-server && npx tsx tests/test-noshow-manner-e2e.ts"
```

## 16. 연관 기획서

- [매너 점수 매칭 반영 기획서](./manner-score-matching-plan.md)
- [푸시 알림 활성화 캠페인 기획서](./push-campaign-plan.md)

> 노쇼 시스템과 매너 시스템은 독립 구현이지만 결과는 **매너 점수 단일 채널로 수렴**한다. 노쇼 확정 시 자동으로 매너 평균이 떨어지고, 매너 등급이 떨어지면 매칭 cost 페널티가 적용됨.
