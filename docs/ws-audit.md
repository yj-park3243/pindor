# WebSocket 통신 감사 보고서

> 작성일: 2026-04-12
> 대상 서버: Node.js/Fastify + Socket.io (`server/src/server.ts`)
> 대상 클라이언트: Flutter (`app/lib/core/network/socket_service.dart`)

---

## 1. 아키텍처 개요

### 서버 구성

| 파일 | PM2 프로세스 | 역할 |
|------|------------|------|
| `server/src/server.ts` | `match-api` | HTTP API + Socket.io 통합 서버 (프로덕션 실행 대상) |
| `server/src/websocket.ts` | 미사용 | WS 전용 서버 (개발 참고용, PM2 ecosystem에 미포함) |

프로덕션 환경에서는 `server.ts`만 실행된다. `websocket.ts`는 분리 운영을 위한 참고 구현으로 실제 트래픽을 처리하지 않는다.

### Socket.io 연결 설정

```
URL: {API_HOST}/ws (path: /ws)
transports: ['websocket', 'polling']
pingTimeout: 30000ms
pingInterval: 15000ms
인증: handshake.auth.token (JWT Access Token)
```

클라이언트는 `socket_io_client` 패키지를 사용하며, 최대 재연결 횟수는 `AppConfig.socketMaxReconnectAttempts`로 설정된다.

### Redis Pub/Sub 채널

| 채널 | 발행자 | 구독자 | 용도 |
|------|--------|--------|------|
| `system_notification` | 워커, 서비스 계층 | `server.ts` | 알림 DB 저장 + Socket + FCM 발송 |
| `push_notification` | `chat.gateway.ts` | `server.ts` | FCM 푸시 전용 (DB 저장 없이 푸시만) |
| `match_lifecycle` | `matching.service.ts`, 워커 | `server.ts` | 매칭 상태 변경 → Socket.io 룸으로 릴레이 |
| `chat_room_message` | `game-auto-resolve.worker.ts` 등 | **`websocket.ts`만 구독** | 시스템 메시지를 채팅방으로 브로드캐스트 |

**주의**: `chat_room_message` 채널은 `websocket.ts`에만 구독되어 있고, 프로덕션에서 실행되는 `server.ts`에는 누락되어 있다. 자세한 내용은 C-2 항목 참조.

### Socket.io 룸 구조

| 룸 이름 | 자동/수동 입장 | 용도 |
|---------|--------------|------|
| `user:{userId}` | 자동 (연결 시) | 개인 알림 수신 |
| `room:{roomId}` | 수동 (`JOIN_ROOM`) | 채팅 메시지 송수신 |
| `matchrequest:{requestId}` | 수동 (`JOIN_MATCH_REQUEST`) | 매칭 성사(`MATCH_FOUND`) 실시간 수신 |
| `match:{matchId}` | 수동 (`JOIN_MATCH`) | 매칭 상태 변경(`MATCH_STATUS_CHANGED`) 실시간 수신 |

재연결 시 서버와 클라이언트 양쪽에서 룸 자동 복구 로직이 있다.
- 서버: `user_matchrequest_rooms:{userId}`, `user_match_rooms:{userId}` Redis Set으로 추적
- 클라이언트: `_activeMatchRequestRooms`, `_activeMatchRooms` Set으로 추적 후 `onReconnect`에서 재입장

---

## 2. 이벤트 맵 (서버 → 클라이언트)

### 2.1 `notification`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `notification` |
| 대상 룸 | `user:{userId}` |
| 발생 조건 | `NotificationService.send()` 호출 시 (DB 저장 + 소켓 + FCM 통합 발송) |
| 클라이언트 핸들러 | `socket_service.dart` → `_notificationController` → `socketNotificationProvider` |
| 소비 위치 | `main_tab_screen.dart`, `match_list_screen.dart` |

**페이로드:**
```json
{
  "type": "NotificationType",
  "title": "string",
  "body": "string",
  "data": {
    "matchId": "string (optional)",
    "roomId": "string (optional)",
    "deepLink": "string (optional)"
  },
  "createdAt": "ISO8601"
}
```

**처리되는 `type` 값 전체 목록:**

| type | 발생 상황 | data 필드 |
|------|----------|-----------|
| `MATCH_FOUND` | 즉시 매칭 성사 (미사용 — MATCH_FOUND는 match_lifecycle 채널로 처리) | `matchId` |
| `MATCH_REQUEST_RECEIVED` | 직접 매칭 요청 수신 | `requestId` |
| `MATCH_PENDING_ACCEPT` | 매칭 상대 발견, 수락 대기 시작 | `matchId`, `opponentNickname`, `opponentGender`, `opponentAge`, `deepLink` |
| `MATCH_ACCEPTED` | **서버에서 실제로 발송하지 않음** (M-4 참조) | — |
| `MATCH_BOTH_ACCEPTED` | 양측 모두 수락하여 매칭 확정 | `matchId`, `chatRoomId`, `deepLink: /match/{matchId}/chat` |
| `MATCH_WAITING_OPPONENT` | 내가 수락 완료, 상대방 수락 대기 중 | `matchId` |
| `MATCH_REJECTED` | 상대방이 매칭 거절 | `matchId` |
| `MATCH_CANCELLED` | 매칭 취소 | `matchId` |
| `MATCH_EXPIRED` | 매칭 요청 기간 만료 | `matchRequestId` |
| `MATCH_ACCEPT_TIMEOUT` | 수락 시간(10분) 초과로 매칭 취소 | `matchId` |
| `MATCH_COMPLETED` | 경기 결과 최종 확정 | `matchId` |
| `MATCH_NO_SHOW_PENALTY` | 노쇼 패널티 부과 | `matchId` |
| `MATCH_NO_SHOW_COMPENSATION` | 노쇼 보상 지급 | `matchId` |
| `MATCH_FORFEIT` | 몰수패 처리 | `matchId` |
| `MATCH_FORFEIT_WIN` | 몰수승 처리 | `matchId` |
| `CHAT_MESSAGE` | 텍스트 채팅 메시지 수신 | `roomId`, `senderId`, `deepLink` |
| `CHAT_IMAGE` | 이미지 채팅 메시지 수신 | `roomId`, `senderId`, `deepLink` |
| `CHAT_LOCATION` | 위치 공유 메시지 수신 (C-5 참조: NotificationType 미정의) | `roomId`, `senderId`, `deepLink` |
| `GAME_RESULT_SUBMITTED` | 상대방이 경기 결과 제출 | `gameId`, `matchId` |
| `GAME_RESULT_CONFIRMED` | 경기 결과 상호 확인 완료 | `gameId`, `matchId` |
| `SCORE_UPDATED` | 점수 변동 | — |
| `TIER_CHANGED` | 티어 변경 | — |
| `RESULT_DEADLINE` | 경기 결과 입력 기한 임박 | `gameId`, `matchId` |
| `COMMUNITY_REPLY` | 커뮤니티 댓글 | `postId` |

---

### 2.2 `MATCH_FOUND`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `MATCH_FOUND` |
| 대상 룸 | `matchrequest:{requestId}` |
| 발생 조건 | `match_lifecycle` Redis 채널에서 `event: 'MATCH_FOUND'` 수신 시 |
| 발행 위치 | `matching-queue.worker.ts` → Redis pub, `matching.service.ts` → Redis pub |
| 클라이언트 핸들러 | `socket_service.dart` → `_matchFoundController` → `socketMatchFoundProvider` |
| 소비 위치 | `main_tab_screen.dart` |

**페이로드:**
```json
{
  "matchId": "string",
  "status": "PENDING_ACCEPT"
}
```

---

### 2.3 `MATCH_STATUS_CHANGED`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `MATCH_STATUS_CHANGED` |
| 대상 룸 | `match:{matchId}` |
| 발생 조건 | `match_lifecycle` Redis 채널에서 `event: 'MATCH_STATUS_CHANGED'` 수신 시 |
| 발행 위치 | `matching.service.ts` (acceptMatch, rejectMatch, cancelMatch 등) |
| 클라이언트 핸들러 | `socket_service.dart` → `_matchStatusChangedController` → `socketMatchStatusChangedProvider` |
| 소비 위치 | `main_tab_screen.dart`, `match_list_screen.dart` |

**페이로드:**
```json
{
  "matchId": "string",
  "status": "PENDING_ACCEPT | CHAT | CONFIRMED | COMPLETED | CANCELLED",
  "chatRoomId": "string (CHAT 상태로 전환 시)",
  "subStatus": "string (optional)",
  "reason": "string (optional)",
  "gameId": "string (optional)"
}
```

---

### 2.4 `NEW_MESSAGE`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `NEW_MESSAGE` |
| 대상 룸 | `room:{roomId}` |
| 발생 조건 | `SEND_MESSAGE` 이벤트 처리 완료 시, 또는 `chat_room_message` Redis 채널 수신 시 |
| 발행 위치 | `chat.gateway.ts` (SEND_MESSAGE 핸들러), `websocket.ts` (chat_room_message 구독) |
| 클라이언트 핸들러 | `socket_service.dart` → `_messageController` → `socketMessageProvider` / `roomMessageProvider` |
| 소비 위치 | `chat_room_screen.dart` |

**페이로드:**
```json
{
  "id": "string",
  "roomId": "string",
  "sender": {
    "id": "string",
    "nickname": "string",
    "profileImageUrl": "string | null"
  },
  "content": "string",
  "messageType": "TEXT | IMAGE | LOCATION",
  "extraData": {
    "latitude": "number (LOCATION 타입 시)",
    "longitude": "number (LOCATION 타입 시)",
    "imageUrl": "string (IMAGE 타입 시, optional)"
  },
  "readAt": "ISO8601 | null",
  "createdAt": "ISO8601"
}
```

---

### 2.5 `USER_TYPING`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `USER_TYPING` |
| 대상 룸 | `room:{roomId}` (발신자 제외 broadcast) |
| 발생 조건 | 클라이언트가 `TYPING` 이벤트 전송 시 |
| 발행 위치 | `chat.gateway.ts` (`TYPING` 핸들러, `socket.to().emit()` 사용) |
| 클라이언트 핸들러 | `socket_service.dart` → `_typingController` → `socketTypingProvider` |

**페이로드:**
```json
{
  "userId": "string",
  "roomId": "string"
}
```

---

### 2.6 `MESSAGES_READ`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `MESSAGES_READ` |
| 대상 룸 | `room:{roomId}` (발신자 포함 전체, `io.to().emit()`) |
| 발생 조건 | `JOIN_ROOM` 입장 시 자동 읽음 처리 또는 `MARK_READ` 이벤트 수신 시 |
| 발행 위치 | `chat.gateway.ts` (`_markReadAndNotify` 헬퍼) |
| 클라이언트 핸들러 | `socket_service.dart` → `_messagesReadController` → `messagesReadProvider` |

**페이로드:**
```json
{
  "roomId": "string",
  "readByUserId": "string",
  "messageIds": ["string", "..."]
}
```

---

### 2.7 `ERROR`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `ERROR` |
| 대상 룸 | 발신 소켓만 (`socket.emit()`) |
| 발생 조건 | 핸들러 내 유효성 검증 실패 또는 권한 오류 시 |
| 발행 위치 | `chat.gateway.ts` 각 이벤트 핸들러 |
| 클라이언트 핸들러 | `socket_service.dart` → debugPrint만 (UI 노출 없음) |

**페이로드:**
```json
{
  "code": "ROOM_NOT_FOUND | ROOM_BLOCKED | FORBIDDEN | INVALID_DATA | MESSAGE_TOO_LONG | MATCH_NOT_FOUND | INTERNAL_ERROR",
  "message": "string"
}
```

**기타 서버→클라이언트 응답 이벤트 (확인용):**

| 이벤트명 | 발생 조건 |
|---------|---------|
| `ROOM_JOINED` | `JOIN_ROOM` 성공 후 |
| `ROOM_LEFT` | `LEAVE_ROOM` 처리 후 |
| `MATCH_REQUEST_ROOM_JOINED` | `JOIN_MATCH_REQUEST` 성공 후 |
| `MATCH_REQUEST_ROOM_LEFT` | `LEAVE_MATCH_REQUEST` 처리 후 |
| `MATCH_ROOM_JOINED` | `JOIN_MATCH` 성공 후 (참여자 여부 검증 포함) |
| `MATCH_ROOM_LEFT` | `LEAVE_MATCH` 처리 후 |

---

## 3. 이벤트 맵 (클라이언트 → 서버)

### 3.1 `JOIN_ROOM`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `JOIN_ROOM` |
| 발신 위치 | `socket_service.dart` `joinRoom()` |
| 호출 시점 | 채팅방 화면 진입 시 |
| 서버 처리 | 채팅방 존재/권한 검증 → `room:{roomId}` 룸 입장 → 자동 읽음 처리 → `MESSAGES_READ` 브로드캐스트 |

```json
{ "roomId": "string" }
```

---

### 3.2 `LEAVE_ROOM`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `LEAVE_ROOM` |
| 발신 위치 | `socket_service.dart` `leaveRoom()` |
| 호출 시점 | 채팅방 화면 이탈 시 |
| 서버 처리 | 룸 퇴장 + `user_active_room:{userId}` Redis 키 삭제 |

```json
{ "roomId": "string" }
```

---

### 3.3 `SEND_MESSAGE`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `SEND_MESSAGE` |
| 발신 위치 | `socket_service.dart` `sendMessage()` |
| 호출 시점 | 사용자가 메시지 전송 시 |
| 서버 처리 | 유효성 검증 → DB 저장 → `NEW_MESSAGE` 브로드캐스트 → 상대방에게 notification + FCM 발송 |
| 연결 미연결 시 | `SocketNotConnectedException` throw |

```json
{
  "roomId": "string",
  "content": "string (LOCATION 타입 시 빈 문자열 허용)",
  "messageType": "TEXT | IMAGE | LOCATION",
  "extraData": {
    "latitude": "number (LOCATION 시 필수)",
    "longitude": "number (LOCATION 시 필수)"
  }
}
```

유효성 검증:
- TEXT/IMAGE: `content` 필수
- LOCATION: `extraData.latitude`, `extraData.longitude` 필수
- TEXT: `content` 최대 500자

---

### 3.4 `MARK_READ`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `MARK_READ` |
| 발신 위치 | `socket_service.dart` `sendMarkRead()` |
| 호출 시점 | 메시지 읽음 처리 필요 시 |
| 서버 처리 | 미읽 메시지 일괄 읽음 처리 → `MESSAGES_READ` 브로드캐스트 |

```json
{ "roomId": "string" }
```

---

### 3.5 `TYPING`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `TYPING` |
| 발신 위치 | `socket_service.dart` `sendTyping()` |
| 호출 시점 | 사용자가 텍스트 입력 중 |
| 서버 처리 | `socket.to(room).emit('USER_TYPING', ...)` — 발신자 제외 브로드캐스트 |

```json
{ "roomId": "string" }
```

---

### 3.6 `JOIN_MATCH_REQUEST`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `JOIN_MATCH_REQUEST` |
| 발신 위치 | `socket_service.dart` `joinMatchRequest()` |
| 호출 시점 | 매칭 요청 생성 직후 (`MatchRequestNotifier.createRequest()`), 재연결 시 |
| 서버 처리 | `matchrequest:{requestId}` 룸 입장 + `user_matchrequest_rooms:{userId}` Redis Set 추적 |

```json
{ "requestId": "string" }
```

---

### 3.7 `LEAVE_MATCH_REQUEST`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `LEAVE_MATCH_REQUEST` |
| 발신 위치 | `socket_service.dart` `leaveMatchRequest()` |
| 호출 시점 | 매칭 요청 취소 시 (`MatchRequestNotifier.cancelRequest()`) |
| 서버 처리 | 룸 퇴장 + Redis Set에서 제거 |

```json
{ "requestId": "string" }
```

---

### 3.8 `JOIN_MATCH`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `JOIN_MATCH` |
| 발신 위치 | `socket_service.dart` `joinMatch()` |
| 호출 시점 | 활성 매칭 화면 진입 시 (`match_list_screen.dart` `_joinActiveMatchRooms()`) |
| 서버 처리 | 참여자 여부 DB 검증 → `match:{matchId}` 룸 입장 + Redis Set 추적 |

```json
{ "matchId": "string" }
```

---

### 3.9 `LEAVE_MATCH`

| 항목 | 내용 |
|------|------|
| 이벤트명 | `LEAVE_MATCH` |
| 발신 위치 | `socket_service.dart` `leaveMatch()` |
| 호출 시점 | `MATCH_STATUS_CHANGED`에서 COMPLETED/CANCELLED 감지 시 (`main_tab_screen.dart`) |
| 서버 처리 | 룸 퇴장 + Redis Set에서 제거 |

```json
{ "matchId": "string" }
```

---

## 4. 발견된 문제점

### CRITICAL — 기능 미작동

---

#### C-1. MatchAcceptNotifier가 MATCH_REJECTED를 처리하지 않음

**파일:** `app/lib/providers/matching_provider.dart:266-275`

```dart
// 현재 코드 (문제)
if (type == 'MATCH_BOTH_ACCEPTED' || type == 'MATCH_ACCEPTED') {
  ...
} else if (type == 'MATCH_CANCELLED' || type == 'MATCH_ACCEPT_TIMEOUT') {
  state = state.copyWith(acceptStatus: 'CANCELLED');
}
// MATCH_REJECTED 분기 없음
```

상대방이 매칭을 거절하면 서버는 `MATCH_REJECTED` 타입의 `notification`을 발송하지만, `MatchAcceptNotifier._listenSocket()`은 이 타입을 처리하지 않는다. 결과적으로 수락 화면이 자동으로 닫히지 않고, 폴링 fallback이 동작하기까지 최대 10초간 대기하게 된다.

**수정 방향:**
```dart
} else if (type == 'MATCH_CANCELLED' || type == 'MATCH_ACCEPT_TIMEOUT' || type == 'MATCH_REJECTED') {
  state = state.copyWith(acceptStatus: 'CANCELLED');
}
```

---

#### C-2. server.ts가 chat_room_message 채널을 구독하지 않음

**파일:** `server/src/server.ts:103`

```typescript
// 현재 코드 (문제)
await subClient.subscribe('system_notification', 'push_notification', 'match_lifecycle');
// 'chat_room_message' 누락

// websocket.ts (참고용, 프로덕션 미사용)
await subClient.subscribe('system_notification', 'push_notification', 'match_lifecycle', 'chat_room_message');
```

3분 자동 판정 등 서버 워커가 발행하는 시스템 메시지는 `chat_room_message` Redis 채널을 통해 채팅방으로 전달된다. `websocket.ts`에는 이 채널 구독과 핸들러가 구현되어 있지만, 실제 프로덕션에서 실행되는 `server.ts`에는 없다. 따라서 자동 판정 결과 메시지가 채팅방에 실시간으로 전달되지 않는다.

**수정 방향:** `server.ts`의 `subscribe` 호출에 `'chat_room_message'`를 추가하고, `subClient.on('message')` 핸들러에 아래 블록을 추가한다.

```typescript
await subClient.subscribe('system_notification', 'push_notification', 'match_lifecycle', 'chat_room_message');

// subClient.on('message') 내부 추가:
if (channel === 'chat_room_message') {
  const { roomId, message: msgData } = payload;
  if (roomId && msgData) {
    io.to(`room:${roomId}`).emit('NEW_MESSAGE', msgData);
  }
}
```

---

#### C-3. MATCH_FOUND 이벤트 유실 (두 번째 유저)

**관련 파일:** `app/lib/screens/matching/` (매칭 요청 생성 화면)

매칭 요청 생성 API를 호출했을 때 즉시 매칭이 성사되면, 서버는 `matchrequest:{requestId}` 룸으로 `MATCH_FOUND`를 발송한다. 그러나 두 번째 유저(매칭 상대)는 API 응답을 받은 뒤에야 `joinMatchRequest()`를 호출하기 때문에 이미 이벤트를 놓칠 수 있다.

**현재 상태:** 부분 완화됨. `MATCH_PENDING_ACCEPT` notification이 `user:{userId}` 룸으로 발송되므로, 유저가 온라인 상태이면 `notification` 이벤트 경로로 수락 화면으로 이동 가능하다. `match_list_screen.dart`에서 `PENDING_ACCEPT` 상태 감지 시 자동 리다이렉트 로직도 존재한다.

**근본 원인:** `MATCH_FOUND`와 `MATCH_PENDING_ACCEPT` notification이 동시에 발송되므로, notification 경로가 정상 동작하면 실질적 영향은 없다. 단, socket 연결 직전에 이벤트가 발생하는 race condition은 여전히 존재한다.

---

#### C-4. TYPE_TO_SETTING에 6개 타입 누락

**파일:** `server/src/modules/notifications/notification.service.ts:15-33`

`NotificationType`은 23개 값을 가지지만 `TYPE_TO_SETTING`에는 17개만 정의되어 있다.

**누락된 타입:**
```typescript
// 아래 6개가 TYPE_TO_SETTING에 없음
'MATCH_CANCELLED'
'MATCH_COMPLETED'
'MATCH_NO_SHOW_PENALTY'
'MATCH_NO_SHOW_COMPENSATION'
'MATCH_FORFEIT'
'MATCH_FORFEIT_WIN'
```

`Record<NotificationType, string>` 타입 선언으로 인해 TypeScript 컴파일 시 에러가 발생한다. 런타임에서는 `settingKey`가 `undefined`가 되어 알림 설정 필터를 통과하므로 알림 자체는 발송되나, 사용자가 알림을 끌 수 없는 상태가 된다.

**수정 방향:**
```typescript
const TYPE_TO_SETTING: Record<NotificationType, string> = {
  // ... 기존 항목들 ...
  MATCH_CANCELLED: 'matchFound',
  MATCH_COMPLETED: 'matchFound',
  MATCH_NO_SHOW_PENALTY: 'matchFound',
  MATCH_NO_SHOW_COMPENSATION: 'matchFound',
  MATCH_FORFEIT: 'matchFound',
  MATCH_FORFEIT_WIN: 'matchFound',
};
```

---

#### C-5. CHAT_LOCATION이 NotificationType에 미정의

**파일:** `server/src/modules/chat/chat.gateway.ts:288`

```typescript
// chat.gateway.ts:285-289
const notifType =
  data.messageType === 'IMAGE'
    ? 'CHAT_IMAGE'
    : data.messageType === 'LOCATION'
    ? 'CHAT_LOCATION'   // NotificationType union에 없는 값
    : 'CHAT_MESSAGE';
```

`CHAT_LOCATION` 문자열이 `NotificationType` union에 정의되어 있지 않아 TypeScript 타입 에러가 발생한다. `notification` 이벤트로는 발송되나 DB 저장 시 타입 컬럼 유효성 검증에서 실패할 수 있다.

**수정 방향:**
1. `server/src/shared/types/index.ts`의 `NotificationType`에 `'CHAT_LOCATION'` 추가
2. `notification.service.ts`의 `TYPE_TO_SETTING`에 매핑 추가: `CHAT_LOCATION: 'chatMessage'`

---

### MODERATE — 동작하지만 개선 필요

---

#### M-1. MatchAcceptNotifier가 MATCH_STATUS_CHANGED를 감지하지 못함

**파일:** `app/lib/providers/matching_provider.dart:258-288`

`MatchAcceptNotifier._listenSocket()`은 `SocketService.instance.onNotification`만 구독한다. `match:{matchId}` 룸 기반의 `MATCH_STATUS_CHANGED` 이벤트(`onMatchStatusChanged` 스트림)는 구독하지 않는다.

실제로는 서버가 `notification`과 `MATCH_STATUS_CHANGED`를 동시에 발행하므로 `notification` 경로만으로도 기능은 동작한다. 그러나 `MATCH_STATUS_CHANGED`를 추가로 구독하면 알림 설정을 꺼도 수락 화면이 즉시 갱신되는 이점이 있다.

---

#### M-2. MATCH_BOTH_ACCEPTED의 deepLink 경로 불일치

**파일:** `server/src/modules/matching/matching.service.ts:812,819`

```typescript
// 양측 수락 완료 알림 (line 812, 819)
deepLink: `/match/${matchId}/chat`     // 단수 match

// 나머지 알림들 (line 684, 697)
deepLink: `/matches/${savedMatch.id}/accept`  // 복수 matches
```

GoRouter 라우트 정의는 `/matches/...` 형태를 사용한다. `/match/` 경로로의 딥링크는 라우터가 인식하지 못해 홈으로 폴백된다.

**수정 방향:** `/match/${matchId}/chat` → `/matches/${matchId}/chat`으로 변경. GoRouter에 `/matches/:matchId/chat` 라우트가 정의되어 있는지도 확인 필요.

---

#### M-3. main_tab_screen과 match_list_screen의 중복 리스너

**파일:** `app/lib/screens/main_tab_screen.dart:120-135`, `app/lib/screens/matching/match_list_screen.dart:93-115`

두 화면 모두 `socketMatchStatusChangedProvider`와 `socketNotificationProvider`를 감시하여 `matchListProvider`와 `matchRequestProvider`를 무효화한다. `match_list_screen.dart`가 활성 상태일 때 두 개의 리스너가 동시에 동작하여 같은 provider를 두 번 invalidate한다.

기능상 문제는 없으나 불필요한 리렌더링이 발생한다. `match_list_screen.dart`의 `ref.listen` 중 `main_tab_screen.dart`와 중복되는 처리는 제거를 고려할 수 있다.

---

#### M-4. MATCH_ACCEPTED 타입이 서버에서 실제로 발송되지 않음

**파일:** `server/src/shared/types/index.ts`, `app/lib/providers/matching_provider.dart:266`

`NotificationType`에 `MATCH_ACCEPTED`가 정의되어 있고 클라이언트의 `MatchAcceptNotifier`도 이를 체크한다(`type == 'MATCH_ACCEPTED'`). 그러나 서버 코드 전체를 검색해도 `MATCH_ACCEPTED` 타입으로 알림을 발송하는 곳이 없다.

실제 발송 타입:
- 한쪽 수락 완료 → `MATCH_WAITING_OPPONENT`
- 양쪽 수락 완료 → `MATCH_BOTH_ACCEPTED`

`MATCH_ACCEPTED`를 체크하는 클라이언트 코드는 데드 코드가 된다.

---

### MINOR — 개선 권장

---

#### m-1. socket_service.dart 이벤트 핸들러에 데이터 검증 없음

**파일:** `app/lib/core/network/socket_service.dart:132-173`

```dart
// 현재 코드
..on('notification', (data) {
  final parsed = Map<String, dynamic>.from(data as Map);  // cast 실패 시 크래시
  _notificationController.add(parsed);
})
```

`data`가 `Map`이 아닌 경우(서버 버그, 프로토콜 오류 등) `as Map` 캐스트에서 런타임 크래시가 발생한다. `try-catch` 또는 타입 가드 추가를 권장한다.

---

#### m-2. MESSAGES_READ의 messageIds cast 안전성

**파일:** `app/lib/providers/chat_provider.dart` (MESSAGES_READ 소비 부분)

`data['messageIds']`를 `.cast<String>()`으로 처리하는 경우, 서버가 빈 배열이나 `null`을 보내면 예외가 발생할 수 있다. null-safe 처리 후 cast를 권장한다.

```dart
// 권장 패턴
final rawIds = data['messageIds'];
final messageIds = rawIds is List ? rawIds.cast<String>() : <String>[];
```

---

#### m-3. MATCH_ACCEPT_TIMEOUT 워커에서 match_lifecycle 이벤트 미발행 확인 필요

**파일:** `server/src/workers/match-accept-timeout.worker.ts`

타임아웃 처리 시 `MATCH_ACCEPT_TIMEOUT` notification은 발송하지만(`system_notification` 채널), `match_lifecycle` 채널에 `MATCH_STATUS_CHANGED` (status: CANCELLED) 이벤트를 별도로 발행하는 코드가 없다.

`match:{matchId}` 룸에 입장한 클라이언트는 `MATCH_STATUS_CHANGED` 이벤트가 와야 룸을 나가고 상태를 갱신하는데, 이 경로가 없으면 `notification` 경로에만 의존하게 된다. notification 설정을 끈 경우 또는 소켓 연결이 다른 룸에 조인되지 않은 경우에는 자동 갱신이 늦어질 수 있다.

---

## 5. 수정 현황

| 이슈 | 우선순위 | 상태 | 파일 |
|------|---------|------|------|
| C-1 MATCH_REJECTED 처리 누락 | CRITICAL | **수정 완료** | `app/lib/providers/matching_provider.dart` |
| C-2 chat_room_message 채널 미구독 | CRITICAL | **수정 완료** | `server/src/server.ts` |
| C-3 MATCH_FOUND 이벤트 유실 | CRITICAL | **부분 완화 완료** | `app/lib/screens/matching/create_match_screen.dart` |
| C-4 TYPE_TO_SETTING 6개 타입 누락 | CRITICAL | **수정 완료** | `server/src/modules/notifications/notification.service.ts` |
| C-5 CHAT_LOCATION NotificationType 미정의 | CRITICAL | **수정 완료** | `server/src/shared/types/index.ts`, `notification.service.ts` |
| M-1 MatchAcceptNotifier MATCH_STATUS_CHANGED 미구독 | MODERATE | 개선 예정 | `app/lib/providers/matching_provider.dart` |
| M-2 deepLink 경로 불일치 (`/match/` vs `/matches/`) | MODERATE | **수정 완료** | `server/src/modules/matching/matching.service.ts` |
| M-3 중복 소켓 리스너 | MODERATE | 개선 예정 | `main_tab_screen.dart`, `match_list_screen.dart` |
| M-4 MATCH_ACCEPTED 데드 코드 | MODERATE | 정리 예정 | `app/lib/providers/matching_provider.dart` |
| m-1 소켓 핸들러 데이터 검증 없음 | MINOR | 개선 예정 | `app/lib/core/network/socket_service.dart` |
| m-2 messageIds cast 안전성 | MINOR | 개선 예정 | `app/lib/providers/chat_provider.dart` |
| m-3 타임아웃 워커 MATCH_STATUS_CHANGED 미발행 | MINOR | **수정 완료** | `server/src/workers/match-accept-timeout.worker.ts` |
