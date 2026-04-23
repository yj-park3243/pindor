# Spots (PINDOR) — 푸시 알림 & 인앱 알림 명세서

> 최종 업데이트: 2026-04-22 (소켓 연결 라이프사이클 섹션 추가)

---

## 1. 시스템 구조

```
비즈니스 로직 → notificationService.send(payload)
  1) 사용자 알림 설정(category)이 OFF면 전체 중단 (DB 저장/푸시 모두 X)
  2) DB insert (notifications 테이블) — 인앱 알림 데이터 (opt-out 가능)
  3) Socket.io 실시간 전송 — 앱 포그라운드 채널
  4) BullMQ `push` 큐 → push.worker → FCM sendEachForMulticast
```

서버 구현 파일:
- `server/src/modules/notifications/notification.service.ts` — 엔트리 포인트
- `server/src/workers/push.worker.ts` — FCM 발송 + 방해금지 + 채팅방 활성 스킵
- `server/src/config/firebase.ts` — Firebase Admin 초기화 (`FIREBASE_SERVICE_ACCOUNT` 환경변수 — JSON 문자열 또는 파일 경로)

앱 구현 파일:
- `app/lib/core/push/push_notification_service.dart` — FCM 토큰 발급/등록/재등록/해제
- `app/lib/core/network/api_client.dart` — 401 토큰 갱신 실패 시 `onForceLogout` 콜백
- `app/lib/providers/auth_provider.dart` — 로그인/로그아웃/회원탈퇴 시 토큰 라이프사이클
- DB `device_tokens` 테이블에 iOS/Android 토큰 저장 (`is_active=true`)

---

## 2. FCM 토큰 라이프사이클

### 2-1. 토큰 등록 플로우

```
앱 시작 → PushNotificationService.initialize()
  1) 권한 요청 (iOS: requestPermission / Android 13+: Permission.notification)
  2) iOS: APNS 토큰 준비 대기 (최대 5회, 1초 간격)
  3) FirebaseMessaging.getToken() → FCM 토큰 획득
  4) 로컬 저장된 토큰과 비교 → 동일하면 스킵
  5) POST /devices/push-token { token, platform } → 서버 등록
  6) SecureStorage에 토큰 저장
  7) onTokenRefresh 리스너 등록 → 토큰 갱신 시 자동 재등록
```

### 2-2. 로그인 성공 시 재등록 (reregisterToken)

```
로그인 성공 (카카오/구글/애플) → 토큰 저장 → 소켓 연결 (§3 참고)
  → PushNotificationService.reregisterToken()
    1) FirebaseMessaging.getToken() → 현재 FCM 토큰 획득
    2) POST /devices/push-token { token, platform } (savedToken 체크 스킵 — 강제 등록)
    3) SecureStorage에 토큰 저장
```

자동 로그인 시에도 동일하게 `reregisterToken()` 호출 (`_checkAutoLogin` 내부).
이는 로그아웃 후 다른 계정으로 로그인했을 때 이전 토큰이 새 계정에 연결되도록 보장한다.

### 2-3. 로그아웃 시 토큰 해제 (unregisterToken)

```
AuthNotifier.logout()
  1) POST /auth/logout
  2) PushNotificationService.unregisterToken()
     a) SecureStorage에서 기존 FCM 토큰 읽기
     b) DELETE /devices/push-token { token } → 서버에서 토큰 해제
     c) SecureStorage 로컬 토큰 초기화 (빈 문자열 저장)
  3) 딥링크 콜백 해제 (onDeepLink = null)
  4) 소켓 연결 해제
  5) SecureStorage 토큰 삭제
  6) 로컬 DB 전체 정리 + SharedPreferences 정리
```

로컬 토큰을 빈 문자열로 초기화하므로, 다음 로그인 시 `reregisterToken()`이 반드시 서버에 새로 등록한다.
회원 탈퇴(`deleteAccount`)에서도 동일한 `unregisterToken()` 호출.

### 2-4. 401 토큰 만료 시 강제 로그아웃 (onForceLogout)

```
API 요청 → 401 응답 → _AuthInterceptor.onError()
  1) refreshToken으로 갱신 시도 (POST /auth/refresh)
  2) 갱신 성공 → 새 accessToken 저장 + 소켓 재연결 + 원래 요청 재시도
  3) 갱신 실패 → SecureStorage 토큰 삭제 → onForceLogout 콜백 호출
     → ApiClient.onForceLogout (main.dart에서 설정)
       → AuthNotifier.logout() → 로그인 화면으로 이동
```

`onForceLogout`은 `_AuthInterceptor` 내부에서 다음 두 경우에 호출:
- refreshToken이 null인 경우
- `/auth/refresh` 요청 자체가 실패한 경우

동시에 여러 요청이 401을 받을 때 중복 갱신 방지: `_isRefreshing` 플래그 + `_refreshCompleter`로 대기 후 일괄 재시도.

---

## 3. 소켓 연결 라이프사이클

### 3-1. 기본 원칙

소켓(Socket.io) 연결은 **항상 유지하지 않는다.** 활성 매칭/요청이 있을 때만 연결하고, 없으면 해제한다.
이는 불필요한 서버 리소스 소비와 배터리 사용을 줄이기 위한 설계다.

핵심 함수: `syncSocketConnection()` (`app/lib/providers/matching_provider.dart`)

```dart
// 활성 매칭/요청이 있으면 소켓 연결, 없으면 끊기
Future<void> syncSocketConnection(ref) async {
  // 1) 현재 매칭 목록에서 활성 상태 확인 (PENDING_ACCEPT / CHAT / CONFIRMED)
  // 2) 매칭 요청 목록에서 WAITING 상태 확인
  // → 하나라도 있으면 connect, 모두 없으면 disconnect
}
```

활성 상태 판정 기준:
| 상태 | 소켓 필요 여부 | 이유 |
|------|-------------|------|
| `WAITING` (매칭 요청) | O | `MATCH_FOUND` 이벤트 수신 필요 |
| `PENDING_ACCEPT` | O | 수락/거절/타임아웃 이벤트 수신 필요 |
| `CHAT` | O | 채팅 메시지 실시간 수신 |
| `CONFIRMED` | O | 경기 결과 입력 등 이벤트 수신 |
| `COMPLETED` / `CANCELLED` / 없음 | X | 실시간 이벤트 불필요 |

### 3-2. 소켓 연결 시점

```
[앱 시작 — 자동 로그인]
  _checkAutoLogin() (auth_provider.dart)
    → 소켓 즉시 연결하지 않음
    → FCM 토큰 재등록만 수행
    → 이후 홈 화면에서 매칭 데이터 로드 → syncSocketConnection()

[로그인 성공 — 카카오/구글/애플]
  loginWithKakao/Google/Apple() (auth_provider.dart)
    → _socket.connect(accessToken)  ← 로그인 직후에는 즉시 연결
    → 이후 syncSocketConnection()이 필요 시 해제

[매칭 요청 생성]
  create_match_screen.dart / quick_match_screen.dart
    → 매칭 요청 API 호출 성공
    → syncSocketConnection(ref)  ← WAITING 상태이므로 소켓 연결됨
    → MATCH_FOUND 이벤트 수신 대기

[바텀 탭 전환]
  MainTabScreen._onTabTap() (main_tab_screen.dart)
    → syncSocketConnection(ref)  ← 탭 전환마다 활성 상태 재평가

[포그라운드 복귀]
  _AppLifecycleObserver.didChangeAppLifecycleState() (main.dart)
    → AppLifecycleState.resumed 시 syncSocketConnection(ref)
```

### 3-3. 소켓 해제 시점

```
[매칭 완료/취소 후]
  소켓 이벤트로 매칭 상태 변경 감지
    → matchList/matchRequest 갱신
    → 다음 syncSocketConnection() 호출 시 활성 매칭 없음 감지 → disconnect

[로그아웃]
  AuthNotifier.logout() (auth_provider.dart)
    → _socket.disconnect()  ← 무조건 해제

[회원 탈퇴]
  AuthNotifier.deleteAccount() (auth_provider.dart)
    → _socket.disconnect()  ← 무조건 해제

[401 토큰 갱신 실패]
  _AuthInterceptor.onError() (api_client.dart)
    → onForceLogout → AuthNotifier.logout() → disconnect
```

### 3-4. 자동 로그인 vs 수동 로그인 비교

| | 자동 로그인 (_checkAutoLogin) | 수동 로그인 (loginWith*) |
|--|---|---|
| 소켓 즉시 연결 | X | O |
| syncSocketConnection 호출 | 홈 화면 로드 후 / 탭 전환 / 포그라운드 복귀 시 | 이후 동일 |
| 이유 | 활성 매칭 없는 유저가 대부분 — 불필요한 연결 방지 | 로그인 직후 온보딩/프로필 설정 중 소켓 이벤트 필요할 수 있음 |

---

## 4. 알림 설정 카테고리 (notification_settings 테이블)

| 필드 | 대상 알림 타입 (TYPE_TO_SETTING 매핑) |
|------|------|
| `matchFound` | MATCH_FOUND / MATCH_PENDING_ACCEPT / MATCH_ACCEPTED / MATCH_BOTH_ACCEPTED / MATCH_REJECTED / MATCH_EXPIRED / MATCH_ACCEPT_TIMEOUT / MATCH_ACCEPT_REMINDER / MATCH_WAITING_OPPONENT / MATCH_CANCELLED / MATCH_COMPLETED / MATCH_NO_SHOW_PENALTY / MATCH_NO_SHOW_COMPENSATION / MATCH_FORFEIT / MATCH_FORFEIT_WIN |
| `matchRequest` | MATCH_REQUEST_RECEIVED |
| `chatMessage` | CHAT_MESSAGE / CHAT_IMAGE / CHAT_LOCATION |
| `gameResult` | GAME_RESULT_SUBMITTED / GAME_RESULT_CONFIRMED / RESULT_DEADLINE |
| `scoreChange` | SCORE_UPDATED / TIER_CHANGED |
| `communityReply` | COMMUNITY_REPLY |

카테고리가 `false`면 **인앱 알림 DB 저장도 스킵**됨 (send 함수 맨 앞에서 early return).

---

## 5. 알림 목록

### 5-1. 매칭
| # | Type | 대상 | title | body | DB | deepLink |
|---|------|------|-------|------|----|----------|
| 1 | `MATCH_PENDING_ACCEPT` | 양측 | 매칭 상대를 찾았습니다! | 상대: {닉네임}. 수락하시겠습니까? | O | `/match/{matchId}/accept` |
| 2 | `MATCH_WAITING_OPPONENT` | 수락한 쪽 | 수락 완료 | 상대의 응답을 기다리고 있습니다. | O | `/match/{matchId}` |
| 3 | `MATCH_BOTH_ACCEPTED` | 양측 | 매칭이 확정되었습니다! | {상대 닉네임}님과의 매칭이 확정되었습니다. | O | `/match/{matchId}/chat` |
| 4 | `MATCH_REJECTED` (거절자) | 본인 | 매칭 거절 완료 | -15점 패널티가 적용되었습니다. | O | `/matches` |
| 5 | `MATCH_REJECTED` (피거절자) | 상대 | 매칭이 취소되었습니다 | 상대방이 매칭을 거절했습니다. | O | `/matches` |
| 6 | `MATCH_ACCEPT_TIMEOUT` (미응답자) | 본인 | 매칭 수락 시간 만료 | -15점 패널티. | O | `/matches` |
| 7 | `MATCH_ACCEPT_TIMEOUT` (양측) | 양측 | 매칭 수락 시간 만료 | 매칭이 취소되었습니다. | O | `/matches` |
| 8 | `MATCH_ACCEPT_TIMEOUT` (수락자) | 본인 | 매칭이 취소되었습니다 | 상대방이 응답하지 않아 취소되었습니다. | O | `/matches` |
| 9 | `MATCH_EXPIRED` | 요청자 | 매칭 요청 만료 | 상대를 찾지 못했습니다. | O | `/matches` |
| 10 | `MATCH_ACCEPT_REMINDER` | 미수락자 | 매칭 수락 {N}분 남음 | 지금 수락하지 않으면 매칭이 취소됩니다. | O | `/matches/{matchId}/accept` |

### 5-2. 노쇼 & 포기
| # | Type | 대상 | title | body | DB |
|---|------|------|-------|------|----|
| 11 | `MATCH_NO_SHOW_PENALTY` (확정 후 취소) | 취소자 | 노쇼 패널티 적용 | 점수 -30점 패널티. | O |
| 12 | `MATCH_NO_SHOW_COMPENSATION` | 상대 | 매칭 취소 보상 | +15점 보상. | O |
| 13 | `MATCH_NO_SHOW_PENALTY` (노쇼 신고) | 신고당한 쪽 | 노쇼 패널티 | 노쇼 신고로 7일간 매칭이 제한됩니다. | O |
| 14 | 계정 정지는 운영자 수동 처리 — 노쇼 횟수만 집계, 자동 영구 정지 없음 (`admin/users/:id/status` 에서 SUSPENDED 변경 시 별도 알림) | | | | |
| 15 | `MATCH_FORFEIT` | 포기자 | 매칭 포기 | 패배 처리되었습니다. | O |
| 16 | `MATCH_FORFEIT_WIN` | 상대 | 상대방이 포기했습니다 | 승리 처리되었습니다. | O |

### 5-3. 경기 결과
| # | Type | 대상 | title | body | DB |
|---|------|------|-------|------|----|
| 17 | `GAME_RESULT_SUBMITTED` | 상대 | 경기 결과 입력 요청 | 상대방이 결과를 입력했습니다. | O |
| 18 | `RESULT_DEADLINE` | 미입력자 | 경기 결과 입력 마감 임박 | 기한 {N}시간 남음. | X |
| 19 | `RESULT_DEADLINE` | 미입력자 | 결과 미입력 | 경기가 취소 처리되었습니다. | O |

### 5-4. 점수 & 티어
| # | Type | 대상 | title | body |
|---|------|------|-------|------|
| 20 | `SCORE_UPDATED` (랭크) | 양측 | 경기 결과: +/-{변동점수}점 획득!/점 | 현재 점수: {최종점수}점 |
| 21 | (친선 경기는 점수 푸시 발송 안 함) | — | — | — |
| 22 | `TIER_CHANGED` | 본인 | 축하합니다! 티어가 승급되었습니다! / 티어가 변경되었습니다 | {이전 티어} → {새 티어} |

### 5-5. 채팅
| # | Type | 대상 | title | body | DB |
|---|------|------|-------|------|----|
| 23 | `CHAT_MESSAGE` | 상대 | {보낸 사람 닉네임}님이 메시지를 보냈습니다 | {메시지 앞 100자} | O |
| 24 | `CHAT_IMAGE` | 상대 | {보낸 사람 닉네임}님이 사진을 보냈습니다 | (없음) | O |
| 25 | `CHAT_LOCATION` | 상대 | {보낸 사람 닉네임}님이 위치를 공유했습니다 | (없음) | O |

### 5-6. 커뮤니티
| # | Type | 대상 | title | body | DB |
|---|------|------|-------|------|----|
| 26 | `COMMUNITY_REPLY` (댓글) | 게시글 작성자 | 댓글이 달렸습니다 | {댓글 앞 100자} | O |
| 27 | `COMMUNITY_REPLY` (대댓글) | 부모 댓글 작성자 | 대댓글이 달렸습니다 | {대댓글 앞 100자} | O |

### 5-7. 어드민
| # | Type | 대상 | title | body |
|---|------|------|-------|------|
| 28 | `ADMIN` | 선택된 유저들 | {어드민 지정} | {어드민 지정} |

---

## 6. 포그라운드 메시지 처리 (앱)

```dart
// push_notification_service.dart
FirebaseMessaging.onMessage.listen((message) {
  // MATCH_PENDING_ACCEPT → 소켓 상태 무관 즉시 딥링크 처리 (소켓 유실 대비)
  // 기타 알림 → 소켓 끊긴 경우에만 로컬 알림 표시 (소켓 연결 시 Socket.io가 처리)
});
```

---

## 7. 푸시가 안 오는 경우 (트러블슈팅)

### 7-1. DB 저장도 안 되는 경우
- **알림 설정 OFF** — `notification_settings` 테이블의 해당 카테고리 컬럼이 `false`
  ```sql
  SELECT match_found, chat_message, game_result, score_change
  FROM notification_settings WHERE user_id = '...';
  ```
  → `true`로 UPDATE

### 7-2. DB에는 쌓이는데 푸시만 안 오는 경우
1. **FCM 토큰 미등록** — `device_tokens` 테이블에 row가 없거나 `is_active=false`
   ```sql
   SELECT user_id, platform, is_active FROM device_tokens WHERE user_id = '...';
   ```
   - 시뮬레이터(iOS Simulator)는 APNS 지원 없어 **토큰 자체가 발급 안 됨** → 실기기 확인
   - 앱 로그: `[Push] FCM 토큰 등록 완료` 또는 `[Push] FCM 토큰 재등록 완료` 메시지 있는지
   - 수동 재등록 트리거: 앱 재시작 → `push_notification_service.dart:initialize()` 자동 호출
   - 로그인 시 `reregisterToken()`이 savedToken 체크 없이 강제 등록하므로, 로그인 직후라면 토큰은 등록된 상태여야 함

2. **방해금지 시간** — `doNotDisturbStart`/`End` 범위 내에서는 푸시만 스킵 (DB는 저장)
   ```sql
   SELECT do_not_disturb_start, do_not_disturb_end FROM notification_settings WHERE user_id = '...';
   ```
   - 로그: `[PushWorker] Skipped (DND): {userId}`

3. **채팅방 활성 스킵** — 채팅 메시지(`CHAT_MESSAGE`/`CHAT_IMAGE`)는 사용자가 해당 채팅방을 **포그라운드로 열고 있으면** 푸시 스킵 (의도된 동작)
   - 조건: Redis `user_active_room:{userId}` 키 값이 해당 `roomId`와 일치
   - 로그: `[PushWorker] Skipped (active room): {userId}`
   - 앱에서 채팅방 벗어나면 키 삭제됨 → 다음 메시지부터 푸시 재개

4. **iOS 사용자 인증 안 됨** — 푸시 권한 거부한 경우
   - iOS 설정 → PINDOR → 알림 허용 확인
   - 앱 재실행 시 `FirebaseMessaging.instance.getAPNSToken()`가 null 반환 → 서버 등록 안 됨

5. **FCM 토큰 만료** — 실패 응답에서 `messaging/registration-token-not-registered`가 오면 worker가 자동으로 `is_active=false`로 마킹
   ```sql
   SELECT COUNT(*) FROM device_tokens WHERE user_id = '...' AND is_active = true;
   -- 0이면 앱 재실행으로 재등록 필요
   ```

6. **Firebase 자체 비활성** — `FIREBASE_SERVICE_ACCOUNT` 환경변수 미설정이면 전체 스킵
   - 로그: `[PushWorker] Firebase disabled — skipping push for {userId}`
   - 환경변수 확인: EC2 서버의 `.env` 파일에서 `FIREBASE_SERVICE_ACCOUNT` 값 존재 여부 확인

7. **로그아웃 후 토큰 잔존** — 이전 버전에서는 `unregisterToken()` 시 로컬 토큰을 초기화하지 않아 다음 로그인 시 `_registerToken()`이 "동일 토큰" 판정으로 스킵될 수 있었음. 현재 버전에서는 `unregisterToken()` 시 로컬 토큰을 빈 문자열로 초기화 + `reregisterToken()`은 savedToken 체크를 스킵하므로 이 문제 해결됨.

### 7-3. 진단 순서
```bash
# 1. 서버 worker 로그 확인
ssh -i ~/WebProject2/match/spots-key.pem ec2-user@43.203.165.114 \
  "tail -100 /home/ec2-user/spots-server/logs/worker-out.log | grep PushWorker"

# 2. DB에 알림이 저장됐는지
psql "$DATABASE_URL" -c "SELECT created_at, type, title FROM notifications \
  WHERE user_id='...' ORDER BY created_at DESC LIMIT 5;"

# 3. 토큰 활성 여부
psql "$DATABASE_URL" -c "SELECT platform, is_active, updated_at FROM device_tokens WHERE user_id='...';"
```

---

## 8. FCM 채널 매핑 (Android)

| 알림 그룹 | channelId |
|----------|-----------|
| 채팅 (`CHAT_*`) | `chat_messages` |
| 매칭 (`MATCH_*`) | `match_alerts` |
| 기타 | `general` |

iOS는 `thread-id`로 그룹핑:
- 채팅: `chat_{roomId}`
- 매칭: `match_{matchId}`
- 그 외: type 값

---

## 9. deepLink 포맷 (앱 내 라우팅)

| deepLink | 의미 |
|----------|------|
| `/match/{matchId}/accept` | 매칭 수락 화면 |
| `/match/{matchId}` | 매칭 상세 |
| `/match/{matchId}/chat` | 채팅방 |
| `/match/{matchId}/result` | 결과 입력 |
| `/matches` | 매칭 목록 |
| `/matches/{matchId}/accept` | 매칭 수락 리마인더 (accept-timeout worker) |
| `/profile` | 내 프로필 |
| `/pin/{pinId}/post/{postId}` | 커뮤니티 게시글 |
| `/notices` | 공지사항 |

---

## 10. 발송 주체별 위치 (소스 레퍼런스)

| 발송 시점 | 파일 | 대략 라인 |
|----------|------|----------|
| 매칭 성사 (PENDING_ACCEPT) | `matching.service.ts` | `createMatch` 이후 |
| 매칭 수락 시 대기 알림 | `matching.service.ts` | `acceptMatch` |
| 양측 수락 → CHAT | `matching.service.ts` | `acceptMatch` 트랜잭션 후 |
| 매칭 거절 | `matching.service.ts` | `rejectMatch` |
| 매칭 수락 리마인더 | `workers/match-accept-timeout.worker.ts` | `handleAcceptReminder` |
| 매칭 타임아웃 | `workers/match-accept-timeout.worker.ts` | |
| 매칭 요청 만료 | `workers/match-expiry.worker.ts` | |
| 결과 입력 → 상대 알림 | `games.service.ts` | `submitResult` |
| 결과 확정 → 점수 | `games.service.ts` | `confirmResult` |
| 결과 기한 알림 | `workers/result-deadline.worker.ts` | |
| 채팅 메시지 | `modules/chat/chat.gateway.ts` | 메시지 수신 시 |
| 커뮤니티 댓글 | `modules/pins/pins.service.ts` | `createComment` |
| 어드민 수동 발송 | `admin-notifications.routes.ts` | POST `/admin/notifications` |

---

## 11. 알려진 제약

- **시뮬레이터 푸시 불가** — iOS Simulator는 APNS 연결 안 됨 → FCM 토큰 발급 실패 → 서버에 등록 안 됨. 실기기 필수.
- **앱 완전 종료 상태에서의 iOS 푸시** — top-level 함수 `_firebaseMessagingBackgroundHandler`에 `@pragma('vm:entry-point')` + `FirebaseMessaging.onBackgroundMessage(...)` 등록됨 (`app/lib/main.dart`). 이 조건이 빠지면 release 빌드에서 tree-shaking으로 함수가 제거돼 종료 상태 iOS 푸시가 도착하지 않는다.
- **채팅 메시지의 active room 스킵** — 상대가 채팅방 열고 있으면 푸시 대신 Socket.io만 사용. 이건 **정상 동작**.
- **어드민 푸시는 푸시만** — `adminBroadcast` 라우트는 `saveToDb: false`로 호출하는 경우 있음 (체크 필요).
- **토큰 등록 재시도** — `_registerToken()`은 최대 3회 exponential backoff (1s → 2s → 4s) 재시도. `reregisterToken()`은 재시도 없이 1회 시도.
- **FCM 토큰 갱신** — `onTokenRefresh` 리스너가 자동으로 `_registerToken()`을 호출하므로, 앱 실행 중 토큰이 바뀌어도 자동 반영됨.
