# Test Coverage Gap (2026-05-16)

기획서(`docs/PRD.md`, `docs/design-*.md`, `docs/*-plan.md`) 17개 카테고리를
기존 자동화 테스트 자산 4그룹(앱 integration_test + 서버 E2E + admin E2E + 서버 단위)과
대조해 도출한 미커버 시나리오와 발견된 정책 갭.

## 1. 본 PR로 새로 추가된 시나리오

| ID | 검증 | 자산 | 결과 |
|----|------|------|------|
| UC | 매칭 종료 시 채팅 unread 배지 즉시 0 | `scenario_unread_clear_test.dart` + `run_scenario_unread_clear.sh` | ✅ |
| AT | MATCH_ACCEPT_TIMEOUT 자동 처리 + 점수 패널티/보상 (15s 셋업) | `scenario_accept_timeout_test.dart` + `run_scenario_accept_timeout.sh` | ✅ |
| MR | JOIN_ROOM 자동 markRead → unreadCount 즉시 갱신 | `scenario_messages_read_test.dart` + `run_scenario_messages_read.sh` | ✅ |
| RC | 거절 5회 누적 시 15분 쿨다운 enforce | `run_scenario_reject_cooldown.sh` (shell-only) | ✅ |
| CI | IMAGE 타입 메시지 흐름 + markRead | `run_scenario_chat_image.sh` (shell-only) | ✅ |

부수 효과: staging DB 핀(`몬테로이`) + test1/test2 본인인증/스포츠프로필 시드.
다른 staging 시나리오들도 재실행 가능해짐.

## 2. 본 PR에서 발견된 server-side 정책 갭

### 2-A. `matchRequestBanUntil` enforce 누락
- 위치: `server/src/modules/matching/matching.service.ts`
- 증상: 노쇼 PENDING 신고 시 신고 대상자의 `matchRequestBanUntil`이 24h로 저장되지만,
  매칭 요청 진입점(`createMatchRequest`)에서 이 값을 검증하지 않아 ban이 실제로 enforce 안 됨.
- 영향: 기획서 `noshow-admin-plan.md §4-3, §6.3`의 "신고 즉시 24h 임시 매칭 신청 차단" 정책이 작동하지 않음.
- 검증: `matchBanUntil`은 line 165~181에서 enforce되지만 `matchRequestBanUntil`은 검색 결과 enforce 코드 0건.
- 권장: `matchBanUntil` enforce 블록 바로 옆에 동일 패턴으로 `matchRequestBanUntil` 검증 추가 + 별도 시나리오로 회귀 차단.

### 2-B. DRAW_AUTO 상태 미구현
- 위치: `server/src/modules/games/games.service.ts:378~382`
- 증상: 기획서 `PRD.md §2.4`는 "양측 승리 주장 시 자동 무승부 (DRAW_AUTO) + 72h 이내 이의신청"인데,
  실제 코드는 양측 WIN/LOSS 일치 외 모든 케이스를 **DISPUTED**로 처리(어드민 검토 대기).
- 영향: DRAW_AUTO 상태 자체가 없음. 72h 이의신청 윈도우/ELO 무승부 자동 반영 흐름도 부재.
- 현재 테스트: `scenario_2_dispute_test.dart`가 실제 코드(DISPUTED)를 검증 중. 기획-구현 정렬 결정 필요.

## 3. 남은 누락 시나리오 (우선순위별)

### 🚨 High — 운영 핵심
| # | 시나리오 | 추가 방식 | 비고 |
|---|---------|----------|------|
| 5 | 노쇼 INSUFFICIENT 흐름 (자료 요청 → 7일 자동 REJECTED → ban 해제) | admin API + shell | ADMIN_PASSWORD 필요. `runNoshowCleanup` 워커 직접 호출 또는 created_at 조작 |
| 6 | PENDING 동안 임시 ban (2-A 갭 — server 수정 선행 필요) | 1줄 enforce 추가 후 시나리오 | server 코드 수정이 prerequisite |

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

## 4. 카테고리별 커버리지 매트릭스

| 카테고리 | 커버율 | 비고 |
|---|---|---|
| 인증/회원가입 | 🟡 | 02-users CRUD만. KCP/병합/OAuth/비번재설정 미커버 |
| 매칭 알고리즘 | 🟢 | 시나리오 10-19 + matching-algorithm.test.ts |
| 매칭 라이프사이클 | 🟢 | **AT/UC** 추가로 보강. DRAW_AUTO만 갭 |
| 채팅 | 🟢 | **MR/CI/UC** 추가로 보강. 위치 메시지/제안 카드 미커버 |
| 게임 결과 | 🟡 | 정상/이의 흐름만. 활동 보너스/허위 누적/OCR 미커버 |
| 노쇼/이의 | 🟡 | 기본 + admin S1만. **INSUFFICIENT/임시 ban/false_noshow_count 미커버** |
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

## 5. 권장 다음 액션 (우선순위)

1. **2-A `matchRequestBanUntil` enforce 추가** — 1줄 수정 + scenario_noshow_pending_ban.sh 추가 (1시간 작업, 운영 영향 큼)
2. **시나리오 5 INSUFFICIENT** — admin API shell-only (30분 작업, ADMIN_PASSWORD 필요)
3. **server 단위 테스트 3종** (활동 보너스 / 티어 / 캠페인) — 격리된 환경에서 작성 가능 (각 1~2시간)
4. **2-B DRAW_AUTO 상태 구현 여부 결정** — 기획-구현 정렬 결정 필요. 구현하면 PRD 정합성↑, DISPUTED 흐름과의 차이 정립 필요

## 6. 본 PR에 포함된 server 변경

- `ACCEPT_TIMEOUT_MS` 환경변수 분리 (matching.service.ts + match-accept-timeout.worker.ts) — 기본 10분, staging .env 에 15초 셋업. prod 영향 없음.
- staging DB 시드: 핀(`몬테로이`) + 본인인증 + sports_profile (`is_placement=false, games_played=10`) — 시나리오 sh 셋업 단계에서 자동 실행.
