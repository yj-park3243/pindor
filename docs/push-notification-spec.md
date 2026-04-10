# 핀돌 (PINDOR) — 푸시 알림 & 인앱 알림 명세서

> 최종 업데이트: 2026-04-10

---

## 1. 알림 시스템 구조

```
비즈니스 로직 → notificationService.send(payload)
  → ① 사용자 알림 설정 확인 (Redis 캐시 5분 TTL)
  → ② notifications 테이블 INSERT (인앱 알림 데이터)
  → ③ Socket.io 실시간 전송 (포그라운드)
  → ④ BullMQ → Push Worker → FCM 발송 (백그라운드)
```

---

## 2. 알림 설정 카테고리

| 설정 필드 | 대상 알림 |
|----------|----------|
| `matchFound` | 매칭 발견 / 수락 / 거절 / 만료 / 타임아웃 |
| `gameResult` | 결과 입력 요청 / 결과 확정 / 입력 기한 |
| `scoreChange` | 점수 변동 / 티어 변경 |
| `communityReply` | 댓글 / 대댓글 |

---

## 3. 전체 알림 목록

### 3-1. 매칭 (Matching)

| # | Type | 대상 | 푸시 title | 푸시 body | DB 저장 | deepLink |
|---|------|------|-----------|----------|---------|----------|
| 1 | `MATCH_PENDING_ACCEPT` | 양측 | 매칭 상대를 찾았습니다! | 상대: {닉네임}/{성별}/{나이}세. 수락하시겠습니까? | O | `/match/{matchId}/accept` |
| 2 | `MATCH_WAITING_OPPONENT` | 수락한 쪽 | 수락 완료 | 수락 완료. 상대의 응답을 기다리고 있습니다. | O | `/match/{matchId}` |
| 3 | `MATCH_BOTH_ACCEPTED` | 양측 | 매칭이 확정되었습니다! | {상대 닉네임}님과의 매칭이 확정되었습니다. | O | `/match/{matchId}/chat` |
| 4 | `MATCH_REJECTED` | 거절한 쪽 | 매칭 거절 완료 | 매칭을 거절했습니다. -15점 패널티가 적용되었습니다. | O | `/matches` |
| 5 | `MATCH_REJECTED` | 거절당한 쪽 | 매칭이 취소되었습니다 | 상대방이 매칭을 거절했습니다. 다시 매칭을 시도해 보세요. | O | `/matches` |
| 6 | `MATCH_ACCEPT_TIMEOUT` | 미응답자 (패널티) | 매칭 수락 시간 만료 (패널티) | 수락 시간이 만료되어 매칭이 취소되었습니다. -15점 패널티가 적용되었습니다. | O | `/matches` |
| 7 | `MATCH_ACCEPT_TIMEOUT` | 양측 미응답 | 매칭 수락 시간 만료 | 수락 시간이 만료되어 매칭이 취소되었습니다. | O | `/matches` |
| 8 | `MATCH_ACCEPT_TIMEOUT` | 수락했는데 상대 미응답 | 매칭이 취소되었습니다 | 상대방이 시간 내에 응답하지 않아 매칭이 취소되었습니다. 다시 매칭을 시도할 수 있습니다. | O | `/matches` |
| 9 | `MATCH_EXPIRED` | 요청자 | 매칭 요청 만료 | 매칭 상대를 찾지 못했습니다. 다시 시도해 보세요. | O | `/matches` |

### 3-2. 노쇼 & 포기

| # | Type | 대상 | 푸시 title | 푸시 body | DB 저장 | deepLink |
|---|------|------|-----------|----------|---------|----------|
| 10 | `MATCH_NO_SHOW_PENALTY` | 확정 후 취소한 쪽 | 노쇼 패널티 적용 | 확정된 매칭을 취소하여 점수 -30점 패널티가 적용되었습니다. | O | `/match/{matchId}` |
| 11 | `MATCH_NO_SHOW_COMPENSATION` | 상대방 | 매칭 취소 보상 | 상대방이 매칭을 취소하여 점수 +15점 보상이 지급되었습니다. | O | `/match/{matchId}` |
| 12 | `MATCH_NO_SHOW_PENALTY` | 노쇼 신고당한 쪽 (2회 미만) | 노쇼 패널티 | 노쇼 신고로 7일간 매칭이 제한됩니다. | O | `/matches` |
| 13 | `MATCH_NO_SHOW_PENALTY` | 노쇼 신고당한 쪽 (2회 이상) | 노쇼 패널티 | 2회 노쇼로 계정이 정지되었습니다. | O | `/matches` |
| 14 | `MATCH_FORFEIT` | 포기한 쪽 | 매칭 포기 | 매칭을 포기했습니다. 패배 처리되었습니다. | O | `/match/{matchId}` |
| 15 | `MATCH_FORFEIT_WIN` | 상대방 | 상대방이 포기했습니다 | 상대방이 매칭을 포기하여 승리 처리되었습니다. | O | `/match/{matchId}` |

### 3-3. 경기 결과 (Game)

| # | Type | 대상 | 푸시 title | 푸시 body | DB 저장 | deepLink |
|---|------|------|-----------|----------|---------|----------|
| 16 | `GAME_RESULT_SUBMITTED` | 상대방 | 경기 결과 입력 요청 | 상대방이 경기 결과를 입력했습니다. 결과를 입력해 주세요. | O | `/match/{matchId}` |
| 17 | `RESULT_DEADLINE` | 미입력자 | 경기 결과 입력 마감 임박 | 경기 결과 입력 기한이 {N}시간 남았습니다. | X (푸시만) | `/match/{matchId}` |
| 18 | `RESULT_DEADLINE` | 미입력자 | 경기 결과 미입력 경고 | 결과 입력 기한이 지나 경기가 취소 처리되었습니다. | O | `/match/{matchId}` |

### 3-4. 점수 & 티어

| # | Type | 대상 | 푸시 title | 푸시 body | DB 저장 | deepLink |
|---|------|------|-----------|----------|---------|----------|
| 19 | `SCORE_UPDATED` | 양측 | 점수가 업데이트되었습니다 | {+/-}{변동점수}점 ({최종점수}점) | O | `/match/{matchId}/result` |
| 20 | `SCORE_UPDATED` | 양측 (친선) | [친선] 점수가 업데이트되었습니다 | {+/-}{변동점수}점 ({최종점수}점) | O | `/match/{matchId}/result` |
| 21 | `TIER_CHANGED` | 해당 유저 | 티어가 변경되었습니다! | {이전 티어} → {새 티어} | O | `/profile` |

### 3-5. 커뮤니티 (Community)

| # | Type | 대상 | 푸시 title | 푸시 body | DB 저장 | deepLink |
|---|------|------|-----------|----------|---------|----------|
| 22 | `COMMUNITY_REPLY` | 게시글 작성자 | 댓글이 달렸습니다 | {댓글 내용 앞 100자} | O | `/pin/{pinId}/post/{postId}` |
| 23 | `COMMUNITY_REPLY` | 부모 댓글 작성자 | 대댓글이 달렸습니다 | {대댓글 내용 앞 100자} | O | `/pin/{pinId}/post/{postId}` |

### 3-6. 어드민 (Admin)

| # | Type | 대상 | 푸시 title | 푸시 body | DB 저장 | deepLink |
|---|------|------|-----------|----------|---------|----------|
| 24 | `ADMIN` | 타겟 유저들 | {어드민 지정 제목} | {어드민 지정 내용} | O | `/notices` |

---

## 4. 구현 현황

| # | Type | 상태 | 비고 |
|---|------|------|------|
| 1 | `MATCH_PENDING_ACCEPT` | ✅ 구현됨 | matching.service.ts, match-accept-timeout.worker.ts |
| 2 | `MATCH_WAITING_OPPONENT` | ✅ 구현됨 | matching.service.ts |
| 3 | `MATCH_BOTH_ACCEPTED` | ✅ 구현됨 | matching.service.ts |
| 4-5 | `MATCH_REJECTED` | ✅ 구현됨 | matching.service.ts (거절자/피거절자 분리) |
| 6-8 | `MATCH_ACCEPT_TIMEOUT` | ✅ 구현됨 | match-accept-timeout.worker.ts (3가지 케이스) |
| 9 | `MATCH_EXPIRED` | ✅ 구현됨 | match-expiry.worker.ts |
| 10-11 | `MATCH_NO_SHOW_PENALTY/COMPENSATION` | ✅ 구현됨 | matching.service.ts |
| 12-13 | `MATCH_NO_SHOW_PENALTY` (신고) | ✅ 구현됨 | matching.service.ts |
| 14-15 | `MATCH_FORFEIT/FORFEIT_WIN` | ✅ 구현됨 | matching.service.ts |
| 16 | `GAME_RESULT_SUBMITTED` | ✅ 구현됨 | games.service.ts |
| 17-18 | `RESULT_DEADLINE` | ✅ 구현됨 | result-deadline.worker.ts |
| 19-20 | `SCORE_UPDATED` | ✅ 구현됨 | games.service.ts |
| 21 | `TIER_CHANGED` | ✅ 구현됨 | games.service.ts |
| 22 | `COMMUNITY_REPLY` (댓글) | ✅ 구현됨 | pins.service.ts |
| 23 | `COMMUNITY_REPLY` (대댓글) | ❌ 미구현 | 부모 댓글 작성자에게 알림 필요 |
| 24 | `ADMIN` | ✅ 구현됨 | admin-notifications.routes.ts |

---

## 5. 미구현 항목 — 대댓글 알림

### 현재 동작
- 게시글에 댓글 → 게시글 작성자에게만 알림

### 추가 필요
- 댓글에 대댓글 → **부모 댓글 작성자**에게 알림
- 조건: 대댓글 작성자 ≠ 부모 댓글 작성자 (자기 글에 대댓글 달면 알림 X)
- 조건: 부모 댓글 작성자 ≠ 게시글 작성자일 때만 별도 발송 (같은 사람이면 댓글 알림 1건으로 충분)

### 메시지
- **Type**: `COMMUNITY_REPLY`
- **Title**: `대댓글이 달렸습니다`
- **Body**: `{대댓글 내용 앞 100자}`
- **deepLink**: `/pin/{pinId}/post/{postId}`

---

## 6. FCM 채널 매핑 (Android)

| 알림 그룹 | channelId | 소리 |
|----------|-----------|------|
| 매칭 관련 (MATCH_*) | `match_alerts` | 기본 |
| 경기 결과 / 점수 / 티어 | `general` | 기본 |
| 커뮤니티 (COMMUNITY_*) | `general` | 기본 |
| 어드민 (ADMIN) | `general` | 기본 |

---

## 7. 방해금지 & 필터링

- **방해금지 시간**: `doNotDisturbStart` ~ `doNotDisturbEnd` → 범위 내 푸시 스킵 (인앱 알림은 저장)
- **채팅방 접속 중**: 해당 채팅방 메시지 푸시 스킵 (`user_active_room:{userId}` Redis 키)
- **알림 설정 OFF**: 해당 카테고리 전체 스킵 (DB 저장 + 푸시 모두 안 함)
