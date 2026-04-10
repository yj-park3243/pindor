# 핀돌 앱 로컬 DB 캐싱 설계

> 작성일: 2026-04-04 / 업데이트: 2026-04-09

---

## 1. 개요

Flutter 앱에 drift(SQLite) 기반 로컬 캐시를 도입하여 다음을 달성한다.

- **앱 재시작 후 데이터 즉시 표시** — 로컬 캐시로 화면 즉시 렌더링
- **불필요한 API 호출 제거** — TTL 기반 Stale-While-Revalidate 패턴
- **오프라인 부분 지원** — 네트워크 없이도 캐시된 데이터로 읽기 가능
- **오프라인 쓰기 큐** — 네트워크 복귀 시 순서대로 전송

---

## 2. 기술 스택

drift(구 moor) — Flutter/Dart용 타입 안전 SQLite 래퍼

```yaml
dependencies:
  drift: ^2.x
  drift_flutter: ^0.x

dev_dependencies:
  drift_dev: ^2.x
  build_runner: ^2.x
```

**DB 파일명**: `spots_local_db` (앱 내부 저장소)

---

## 3. 아키텍처

```
UI (ConsumerWidget)
    ↓ watch / read
Provider (Riverpod)  — TTL 검사, SWR 오케스트레이션
    ↓ call
Repository
    ├── Local DB (drift)   — 즉시 응답, Stream, TTL 관리
    └── Remote API (Dio)   — 백그라운드 갱신, ETag 304 체크
```

핵심 파일 위치:

```
app/lib/data/local/
  database.dart              # AppDatabase 정의
  database.g.dart            # 코드 생성 파일
  database_provider.dart     # Riverpod Provider
  cache_ttl_helper.dart      # TTL 유틸리티
  tables/
    cache_meta_table.dart
    pins_table.dart
    users_table.dart
    chat_rooms_table.dart
    messages_table.dart
    matches_table.dart
    offline_queue_table.dart  # 기획 대비 추가됨
  daos/
    pins_dao.dart
    chat_dao.dart
    users_dao.dart
    matches_dao.dart
```

---

## 4. DB 스키마 (실제 구현)

### CacheMeta — 각 데이터 타입의 마지막 fetch 시각 / ETag

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `cacheKey` | TEXT PK | `'pins_all'`, `'chat_rooms'`, `'user_me'`, `'pin_posts_<pinId>'` |
| `lastFetchedAt` | DATETIME | 마지막 fetch 시각 |
| `etag` | TEXT? | 서버 ETag (304 최적화) |
| `cursor` | TEXT? | 페이지네이션 커서 |

### Pins

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | TEXT PK | 핀 ID |
| `name` | TEXT | 핀 이름 |
| `slug` | TEXT? | URL 슬러그 |
| `centerLatitude` | REAL | 위도 |
| `centerLongitude` | REAL | 경도 |
| `level` | TEXT | `DONG \| GU \| CITY \| PROVINCE` |
| `parentPinId` | TEXT? | 상위 핀 ID |
| `isActive` | BOOL | 활성 여부 |
| `userCount` | INT | 활성 유저 수 |
| `activeMatchRequests` | INT? | 활성 매칭 요청 수 |
| `createdAt` | DATETIME | 생성 시각 |
| `cachedAt` | DATETIME | 캐시 시각 |

> 기획 대비 변경: `id`가 INT → TEXT, `sport` 필드 없음(핀이 종목 무관), `slug`/`level`/`parentPinId`/`activeMatchRequests` 추가

### Users

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | TEXT PK | 유저 ID |
| `email` | TEXT? | 이메일 |
| `nickname` | TEXT | 닉네임 |
| `profileImageUrl` | TEXT? | 프로필 이미지 URL |
| `phone` | TEXT? | 전화번호 |
| `status` | TEXT | `ACTIVE` 기본값 |
| `gender` | TEXT? | 성별 |
| `birthDate` | DATETIME? | 생년월일 |
| `createdAt` | DATETIME | 생성 시각 |
| `lastLoginAt` | DATETIME? | 마지막 로그인 |
| `sportsProfilesJson` | TEXT | 스포츠 프로필 목록 JSON (기본값 `[]`) |
| `locationJson` | TEXT? | 위치 정보 JSON |
| `cachedAt` | DATETIME | 캐시 시각 |

> 기획 대비 변경: `id`가 INT → TEXT, `tier`/`sport`/`rating` 필드 없음 → `sportsProfilesJson`에 통합, `sportsProfilesJson`/`locationJson` 추가

### ChatRooms

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | TEXT PK | 채팅방 ID |
| `matchId` | TEXT | 연결된 매칭 ID |
| `opponentJson` | TEXT | 상대방 정보 JSON |
| `lastMessageJson` | TEXT? | 마지막 메시지 JSON |
| `unreadCount` | INT | 읽지 않은 메시지 수 |
| `isActive` | BOOL | 활성 여부 |
| `createdAt` | DATETIME | 생성 시각 |
| `cachedAt` | DATETIME | 캐시 시각 |

> 기획 대비 변경: `id`가 INT → TEXT, `name`/`type`/`pinId`/`lastMessageId` 없음, `matchId`/`opponentJson`/`isActive` 추가

### Messages

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | TEXT PK | 메시지 ID |
| `chatRoomId` | TEXT | 채팅방 ID |
| `senderId` | TEXT | 발신자 ID |
| `senderNickname` | TEXT | 발신자 닉네임 |
| `senderProfileImageUrl` | TEXT? | 발신자 프로필 이미지 |
| `messageType` | TEXT | `TEXT` 기본값 |
| `content` | TEXT | 메시지 내용 |
| `imageUrl` | TEXT? | 이미지 URL |
| `isRead` | BOOL | 읽음 여부 |
| `createdAt` | DATETIME | 생성 시각 |

인덱스: `(chatRoomId, createdAt DESC)` — 메시지 스크롤 쿼리 최적화

> 기획 대비 변경: `id`가 INT → TEXT, `roomId` → `chatRoomId`, `senderNickname`/`senderProfileImageUrl`/`imageUrl`/`isRead` 추가, `status`/`isLocal` 필드 없음

### Matches

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | TEXT PK | 매칭 ID |
| `status` | TEXT | `PENDING \| ACCEPTED \| REJECTED \| CANCELLED \| COMPLETED` |
| `sportType` | TEXT | 종목 |
| `pinId` | TEXT? | 핀 ID |
| `requesterId` | TEXT | 요청자 ID |
| `responderId` | TEXT? | 응답자 ID |
| `detailJson` | TEXT? | 상세 정보 JSON (requester/responder 프로필 등) |
| `scheduledAt` | DATETIME? | 예정 시각 |
| `createdAt` | DATETIME | 생성 시각 |
| `cachedAt` | DATETIME | 캐시 시각 |

### OfflineQueue (기획 대비 추가)

오프라인 상태에서의 쓰기 작업을 큐잉하여 네트워크 복귀 시 순서대로 전송.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INT PK autoincrement | |
| `action` | TEXT | `SEND_MESSAGE \| CREATE_POST \| CREATE_COMMENT` |
| `payloadJson` | TEXT | 작업 파라미터 JSON |
| `status` | TEXT | `PENDING \| PROCESSING \| FAILED` |
| `retryCount` | INT | 재시도 횟수 |
| `lastError` | TEXT? | 마지막 에러 메시지 |
| `createdAt` | DATETIME | |
| `updatedAt` | DATETIME | |

---

## 5. TTL 정책

`CacheTtlHelper`에서 관리.

| 데이터 | TTL | 비고 |
|--------|-----|------|
| 핀 전체 목록 | 24시간 | foreground 복귀 시 만료 확인 |
| 내 프로필 | 365일 (사실상 영구) | 프로필 수정 API 성공 시 수동 갱신 |
| 타 유저 프로필 | 6시간 | |
| 채팅방 목록 | 30분 | 소켓 이벤트로 실시간 갱신 병행 |
| 매칭 목록 | 5분 | |

---

## 6. SWR 패턴

1. Repository에서 로컬 DB 데이터를 즉시 반환 (로딩 없음)
2. 백그라운드에서 TTL 만료 여부 확인
3. 만료 시 서버 API 호출 (ETag 304 활용)
4. 응답 수신 시 로컬 DB upsert → Stream이 자동으로 UI 갱신

---

## 7. 로그아웃 시 캐시 초기화

`AppDatabase.clearAll()` — 전체 테이블 데이터 삭제 (트랜잭션)
