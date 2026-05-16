# Test Coverage Gap (2026-05-16)

기획서(`docs/PRD.md`, `docs/design-*.md`, `docs/*-plan.md`) 17개 카테고리를
기존 자동화 테스트 자산 4그룹(앱 integration_test + 서버 E2E + admin E2E + 서버 단위)과
대조해 도출한 미커버 시나리오와 발견된 정책 갭.

## 1. 추가된 시나리오 (누적)

| ID | 검증 | 자산 | 결과 |
|----|------|------|------|
| UC | 매칭 종료 시 채팅 unread 배지 즉시 0 | `scenario_unread_clear_test.dart` + `run_scenario_unread_clear.sh` | ✅ |
| AT | MATCH_ACCEPT_TIMEOUT 자동 처리 + 점수 패널티/보상 (15s 셋업) | `scenario_accept_timeout_test.dart` + `run_scenario_accept_timeout.sh` | ✅ |
| MR | JOIN_ROOM 자동 markRead → unreadCount 즉시 갱신 | `scenario_messages_read_test.dart` + `run_scenario_messages_read.sh` | ✅ |
| RC | 거절 5회 누적 시 15분 쿨다운 enforce | `run_scenario_reject_cooldown.sh` (shell-only) | ✅ |
| CI | IMAGE 타입 메시지 흐름 + markRead | `run_scenario_chat_image.sh` (shell-only) | ✅ |
| NB | 노쇼 PENDING 신고 시 24h 임시 매칭 차단 enforce | `run_scenario_noshow_pending_ban.sh` (shell-only) | ✅ (2-A 회귀 차단) |
| DA | 양측 WIN 충돌 → DRAW_AUTO + ELO 무승부 반영 | `run_scenario_draw_auto.sh` (shell-only) | ✅ (2-B 회귀 차단) |

부수 효과: staging DB 핀(`몬테로이`) + test1/test2 본인인증/스포츠프로필 시드.
`run_scenario_2.sh`/`run_scenario_3.sh` 도 ID 동적 추출 + 시드 보강으로 staging 호환.

## 2. server-side 정책 갭 — **본 PR에서 모두 수정 완료**

### 2-A. `matchRequestBanUntil` enforce 누락 → **수정 완료** ✅
- 위치: `server/src/modules/matching/matching.service.ts:165~196`
- 원증상: 노쇼 PENDING 신고 시 `matchRequestBanUntil`이 24h로 저장되지만 매칭 요청 진입점에서 검증 안 되어 ban이 enforce 안 됨.
- **수정**: `matchBanUntil` enforce 블록 옆에 동일 패턴으로 `matchRequestBanUntil` 검증 추가. error details 에 `reason: 'NOSHOW_REPORT_PENDING'` 포함.
- 회귀 차단: `run_scenario_noshow_pending_ban.sh` (시나리오 NB).

### 2-B. DRAW_AUTO 상태 미구현 → **수정 완료** ✅
- 위치: `server/src/modules/games/games.service.ts:resolveClaimedResults`
- 원증상: 양측 WIN/LOSS 일치 외 모든 케이스를 **DISPUTED**로 처리 (점수 변동 없음).
- **수정**:
  - `GameResultStatus.DRAW_AUTO` enum 값 추가 (entities/enums.ts) + staging DB `ALTER TYPE ... ADD VALUE`.
  - `resolveClaimedResults` 의 `!isAgreement` 분기를 `DISPUTED` → `DRAW_AUTO` + `applyEloChanges(winnerProfileId=null)` 호출로 변경.
  - 폴백: `applyEloChanges` 실패 시 기존 `DISPUTED` 동작 유지.
  - 메시지 변경: "자동 무승부로 처리되었습니다. 72시간 이내 이의 제기를…" 안내 추가.
- 회귀 차단: `run_scenario_draw_auto.sh` (시나리오 DA) + `scenario_2_dispute_test.dart` 가 DRAW_AUTO 흐름 검증으로 정렬.

## 3. 본 PR에서 새로 발견된 client-side UI 갭

### 3-A. DRAW_AUTO 상태 미인식 — 매치 카드/상세에서 자기 claim 기반 W/L 표시
- 위치: 매치 카드(`match_list_screen.dart`) + 매치 상세(`match_detail_screen.dart`)
- 증상: `game.resultStatus='DRAW_AUTO'`, `winnerProfileId=NULL`, `draws+=1` 이 서버에 정상 반영되지만,
  클라이언트는 결과 칩/통계를 자기 claim 기반으로 표시:
  - A 측: "1승 0패 0무" + "승리" 칩 + 최근 폼 W + 100% 승률
  - B 측: "0승 1패 0무" + "패배" 칩 + 최근 폼 L + 0% 승률
  - 기대: 양쪽 모두 "0승 0패 1무" + "무승부" 칩 + D + 50%
- 영향: 사용자가 잘못된 결과로 인식. 이의제기 결정에 혼란.
- 근거 스크린샷: `app/test_screenshots/scenario2_20260516_134339/userA_12_match_detail_after_result.png`,
  `userB_12_match_detail_after_result.png`, `userA_14_resolved_state.png`, `userB_14_resolved_state.png`.
- 권장: `game.winnerProfileId === null && game.resultStatus === 'DRAW_AUTO'` 케이스를 "무승부"로 표시.
  72h 이내 이의제기 버튼 + 카운트다운 UI 추가.
- 별도 PR 권장 (UI/UX 변경 범위).

### 3-B. 시나리오 sh `_settle` 시간 부족 — 마이/프로필 캡처에 로딩 스피너만 잡힘
- 위치: `scenario_2_dispute_test.dart` / `scenario_3_normal_test.dart` 의 phase 15 (`_forceGo('/profile')` 직후).
- 증상: `_settle(seconds:3)` 이 부족해 ProfileScreen 의 비동기 fetch 완료 전 캡처.
- 영향: 시각적 회귀 검증 약화. 기능 자체에는 영향 없음.
- 권장: 프로필 캐릭터 로드 완료를 위한 `_waitFor` 헬퍼 사용 또는 settle 5s 이상.

## 4. 남은 누락 시나리오 (우선순위별)

### 🚨 High — 운영 핵심
| # | 시나리오 | 추가 방식 | 비고 |
|---|---------|----------|------|
| 5 | 노쇼 INSUFFICIENT 흐름 (자료 요청 → 7일 자동 REJECTED → ban 해제) | admin API + shell | ADMIN_PASSWORD 필요. `runNoshowCleanup` 워커 직접 호출 또는 created_at 조작 |
| 5b | DRAW_AUTO 이의제기 72h 윈도우 + 어드민 결과 정정 흐름 | admin Playwright | 본 PR에서 서버 DRAW_AUTO 만 구현 — 이의제기 시간 제한은 미구현 |

### ⚠️ Medium — 단위 테스트 적합 (server/tests/)
| # | 시나리오 | 위치 |
|---|---------|------|
| 8 | 활동 보너스 (연승, 일간 첫승, 주간 목표) | server/tests/activity-bonus.test.ts |
| 9 | 퍼센타일 티어 산정 + 강등 보호 -50 + K계수 단계 변화 | server/tests/tier-percentile.test.ts |
| 10 | 푸시 캠페인 (INACTIVE_2D, NEW_USER_NUDGE, RANK_DROP, 우선순위, 쿨다운) | server/tests/push-campaign.test.ts |

### ⚠️ Medium — 정책 회귀 위험 (E2E 적합)
- 같은 날짜 중복 매칭 차단 (오늘/내일 최대 2, 같은날 1)
- `desiredDate` 없는 요청 + 활성 매칭 동시 존재 차단
- CONFIRMED + 결과 미입력 시 신규 매칭 차단
- 매너 cost 보정 4종 (GOOD-GOOD −50 / BAD-GOOD +200 / NORMAL-BAD +50 / BAD-BAD −100)
- REJECTED 기각 시 USER 매너 자동 무효(voided_at) + manner_total 차감
- 핀 활성화 인원 미달 → 상위 레벨 자동 병합
- 게시글 sportType 필터링 + 게시글/댓글 신고
- 채팅방 활성 시 푸시 skip (Redis `user_active_room`)
- 방해금지 시간대 푸시 차단
- 27가지 푸시 deep link 라우팅
- chatMessage 카테고리 off 시 채팅 푸시 skip

### 📋 Low — 미구현/v1.x
- KCP 본인인증 흐름 (현재 staging `REQUIRE_VERIFIED_ENABLED=true` 우회로 SQL 시드)
- ci 기반 계정 자동 병합
- 카카오/Apple OAuth, 비밀번호 재설정
- OCR 스코어카드 (v1.3)
- 골프 핸디캡 스트로크 보정
- 오프라인 큐(SEND_MESSAGE/CREATE_POST) flush
- 게시판 입장 조건 (매칭 1회) — 설계됨, 미구현
- 댓글/대댓글 2depth
- 친구/팀 ranked (기획 todo 단계)
- 부하 테스트 (p95 < 300ms, 5000 동시)

## 5. 카테고리별 커버리지 매트릭스

| 카테고리 | 커버율 | 비고 |
|---|---|---|
| 인증/회원가입 | 🟡 | 02-users CRUD만. KCP/병합/OAuth/비번재설정 미커버 |
| 매칭 알고리즘 | 🟢 | 시나리오 10-19 + matching-algorithm.test.ts |
| 매칭 라이프사이클 | 🟢 | **AT/UC** 추가로 보강. DRAW_AUTO 서버 구현 완료 |
| 채팅 | 🟢 | **MR/CI/UC** 추가로 보강. 위치 메시지/제안 카드 미커버 |
| 게임 결과 | 🟢 | 정상/이의 + **DRAW_AUTO** 흐름. 활동 보너스/허위 누적/OCR 미커버 |
| 노쇼/이의 | 🟢 | 기본 + admin S1 + **PENDING 24h ban enforce(NB)**. INSUFFICIENT/false_noshow_count 미커버 |
| 매너 | 🟡 | 기본 + NOSHOW_AUTO만. cost 보정/voided_at 미커버 |
| 티어 | 🔴 | 퍼센타일/강등 보호/K계수 단계 모두 미커버 |
| 핀 시스템 | 🟡 | CRUD만. 활성화 인원/계층/sportType 분리 미커버 |
| 랭킹 | 🟡 | 스냅샷만. RankingRefreshWorker/3게임 진입 미커버 |
| 푸시 알림 | 🟡 | 기본만. 27 타입/방해금지/Deep link 전수 미커버 |
| 푸시 캠페인 | 🔴 | **전부 미커버** |
| 어드민 | 🟡 | S1/S2만. INSUFFICIENT/일괄 기각/K계수 변경 미커버 |
| 로컬 캐시/오프라인 | 🔴 | 오프라인 큐 전혀 미커버 |
| 인프라/관측성 | 🔴 | 부하/SLO 미커버 |
| 팀/친구 | ⚪ | 기획 todo 단계, 09-teams API 기본만 |

## 6. 권장 다음 액션 (우선순위)

1. **3-A DRAW_AUTO 클라이언트 UI 정렬** — 매치 카드/상세에서 `winnerProfileId === null && resultStatus === 'DRAW_AUTO'` 케이스를 "무승부"로 표시 + 72h 이의제기 카운트다운 UI. 별도 PR.
2. **시나리오 5 INSUFFICIENT** — admin API shell-only (30분 작업, ADMIN_PASSWORD 필요)
3. **server 단위 테스트 3종** (활동 보너스 / 티어 / 캠페인) — 격리된 환경에서 작성 가능 (각 1~2시간)
4. **시나리오 sh `_settle` 시간 보강** — 마이/프로필 캡처에 `_waitFor` 도입 (시각 회귀 검증 강화)

## 7. 본 PR에 포함된 server 변경

- `ACCEPT_TIMEOUT_MS` 환경변수 분리 (matching.service.ts + match-accept-timeout.worker.ts) — 기본 10분, staging .env 에 15초 셋업. prod 영향 없음.
- `matchRequestBanUntil` enforce 추가 (matching.service.ts:165~196) — 노쇼 PENDING 24h 임시 매칭 차단 정책 enforce.
- `GameResultStatus.DRAW_AUTO` enum 추가 (entities/enums.ts) + staging DB `ALTER TYPE GameResultStatus ADD VALUE 'DRAW_AUTO'` 적용.
- 양측 결과 불일치 시 자동 무승부 + ELO 반영 (games.service.ts:resolveClaimedResults) — PRD §2.4 정렬.
- staging DB 시드: 핀(`몬테로이`) + 본인인증 + sports_profile (`is_placement=false, games_played=10`) — 시나리오 sh 셋업 단계에서 자동 실행.
