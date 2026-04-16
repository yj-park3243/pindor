# PINDOR 코드 품질 개선 TODO

> 작성일: 2026-04-16
> 총 44건 (CRITICAL 9 / HIGH 13 / MEDIUM 14 / LOW 8)
> 상태: `[ ]` 미착수 / `[~]` 진행중 / `[x]` 완료

---

## Phase 1 — 보안 + 크래시 방지 (즉시)

### CRITICAL

- [ ] **#1 SHA256 비밀번호 해싱 → bcrypt 교체**
  - 파일: `server/src/modules/auth/auth.service.ts` (L544-546)
  - 현재: 솔트 없는 `createHash('sha256')` 사용
  - 수정: `bcrypt.hash(password, 12)` + `bcrypt.compare()` 사용
  - 영향: 기존 이메일 유저 비밀번호 마이그레이션 필요

- [ ] **#2 패스워드 비교 타이밍 공격 취약**
  - 파일: `server/src/modules/auth/auth.service.ts` (L519)
  - 현재: `===` 직접 비교
  - 수정: `crypto.timingSafeEqual(Buffer.from(stored), Buffer.from(computed))`

- [ ] **#3 KCP 인증키 소스코드 하드코딩**
  - 파일: `server/src/modules/auth/kcp.service.ts` (L11-15)
  - 현재: `const KCP_SITE_CD = 'J26040912350'` 직접 노출
  - 수정: `env.KCP_SITE_CD`, `env.KCP_CERT_KEY`로 환경변수 이동

- [ ] **#4 KCP key 재사용 경쟁 조건**
  - 파일: `server/src/modules/auth/kcp.service.ts` (L79-89)
  - 현재: `redis.get()` → 처리 → `redis.setex()` 비원자적
  - 수정: `redis.set(key, '1', 'EX', 86400, 'NX')` 원자적 처리

- [ ] **#5 소켓 룸 미정리 (메모리 누수)**
  - 파일: `app/lib/screens/matching/match_list_screen.dart` (L60-81)
  - 현재: `joinMatch()` 호출 후 dispose에서 `leaveMatch()` 안 함
  - 수정: dispose에서 `_joinedMatchRooms` 순회하며 `leaveMatch()` 호출

- [ ] **#6 StreamSubscription 누적**
  - 파일: `app/lib/providers/matching_provider.dart` (L196-215)
  - 현재: provider 재생성 시 `_connectionSub`, `_matchStatusSub` 잔류 가능
  - 수정: `ref.onDispose()`에서 모든 subscription 명시적 cancel

- [ ] **#7 forceRefresh 경쟁 조건**
  - 파일: `app/lib/providers/matching_provider.dart` (L43-70)
  - 현재: `Future.microtask`로 빌드 중 다른 provider state 변경
  - 수정: Notifier 메서드로 중앙화하거나 별도 flag provider 패턴 변경

- [ ] **#8 토큰 갱신 경쟁 조건**
  - 파일: `app/lib/core/network/api_client.dart` (L144-247)
  - 현재: `_refreshCompleter` null 타이밍 문제 → 401 무한루프 가능
  - 수정: enum 상태 머신 (`notRefreshing`, `refreshing`, `refreshed`) 사용

- [ ] **#9 서버 동기화 실패 무시**
  - 파일: `app/lib/providers/chat_provider.dart` (L179-182)
  - 현재: `catchError`로 에러 삼킴 → 유저가 동기화 실패 인지 못함
  - 수정: state에 `isSyncError` 플래그 추가 + 수동 재시도 지원

---

## Phase 2 — 성능 + 안정성 (1주)

### HIGH

- [ ] **#10 N+1 쿼리: ranking_entry 건당 조회**
  - 파일: `server/src/modules/matching/matching.service.ts` (L1618-1635)
  - 현재: 매칭 상세 응답에서 ranking_entry를 async 콜백 내 개별 조회
  - 수정: `findBy({ sportsProfileId: In(profileIds) })` 배치 조회

- [ ] **#11 프로필 미존재 시 무시 (silent fail)**
  - 파일: `server/src/modules/matching/matching.service.ts` (L594-607)
  - 현재: `if (!requesterProfile) return;` 에러 없이 무시
  - 수정: `throw AppError.notFound(ErrorCode.SPORTS_PROFILE_NOT_FOUND)`

- [ ] **#12 중복 함수: calculateAge**
  - 파일: `matching.service.ts` (L36-44) + `match-accept-timeout.worker.ts` (L31-39)
  - 수정: `shared/utils/age.ts`로 추출

- [ ] **#13 중복 코드: 토큰 저장 로직**
  - 파일: `auth.service.ts` (L714-717) + `kcp.service.ts` (L133, 201, 233)
  - 현재: 동일한 `redis.setex(refresh_token:...)` 4회 반복
  - 수정: `shared/utils/token.ts`에 `storeRefreshToken()` 추출

- [ ] **#14 트랜잭션 내 경쟁 조건 (매칭 큐)**
  - 파일: `server/src/workers/matching-queue.worker.ts` (L324-340)
  - 현재: WAITING 상태 체크 시 `SELECT FOR UPDATE` 미사용
  - 수정: 비관적 잠금 추가

- [ ] **#15 바텀시트 UI 중복**
  - 파일: 10+ 화면에서 동일한 Container/핸들/버튼 패턴 반복
  - 수정: `ConfirmationBottomSheet`, `ActionBottomSheet` 공통 위젯 추출

- [ ] **#16 main_tab_screen 230줄 소켓 리스너**
  - 파일: `app/lib/screens/main_tab_screen.dart`
  - 현재: 10+ `listenManual`, 15+ `invalidate` 인라인
  - 수정: `SocketEventHandlerProvider` 별도 provider로 분리

- [ ] **#17 forceRefresh 5곳에서 수정**
  - 파일: `match_list_screen.dart`, `main_tab_screen.dart` 등
  - 현재: `matchListForceRefreshProvider` 소유권 불명확
  - 수정: Notifier 메서드 `triggerForceRefresh()` 중앙화

- [ ] **#18 채팅방 목록 30분 TTL 과도**
  - 파일: `app/lib/providers/chat_provider.dart` (L16-48)
  - 현재: 30분간 캐시 유지 → 삭제된 방/읽지않음 표시 부정확
  - 수정: 5~10분으로 축소, 소켓 이벤트 수신 시 invalidate

- [ ] **#19 폴링 타이머 누적**
  - 파일: `app/lib/providers/matching_provider.dart` (L332-377)
  - 현재: `startPolling()` 다중 호출 시 타이머 중복 생성 가능
  - 수정: `if (_pollingTimer?.isActive ?? false) return;` 가드 추가

- [ ] **#20 소켓 싱글톤 상태 잔류**
  - 파일: `app/lib/core/network/socket_service.dart` (L10-15)
  - 현재: 로그아웃→재로그인 시 이전 room ID 잔류 가능
  - 수정: `disconnect()`에서 모든 Set/Map 명시적 초기화 확인

- [ ] **#21 acceptances nullable 문제**
  - 파일: `app/lib/models/match.dart` (L116-131)
  - 현재: 서버가 null 반환 시 모든 사용처에서 null 체크 필요
  - 수정: 서버에서 항상 빈 배열 반환, 모델 기본값 `const []`

- [ ] **#22 인증번호 덮어쓰기**
  - 파일: `app/lib/providers/chat_provider.dart` (L245-254)
  - 현재: 두 인증번호 코드가 빠르게 도착하면 첫 번째 유실
  - 수정: 타임스탬프 비교 또는 최신 코드만 유지하는 로직

---

## Phase 3 — 리팩토링 (2주)

### MEDIUM

- [ ] **#23 KCP 에러 타입 미구분**
  - 파일: `server/src/modules/auth/kcp.service.ts` (L273-288)
  - 현재: 네트워크 에러/타임아웃 동일 처리
  - 수정: `AbortError` → 504, 기타 → 502 분리

- [ ] **#24 수동 날짜 포맷팅**
  - 파일: `server/src/modules/matching/matching.service.ts` (L177-181)
  - 현재: 수동 `padStart` 날짜 포맷
  - 수정: `getKSTDateString()` 유틸 사용

- [ ] **#25 limit 파라미터 NaN 검증 부족**
  - 파일: `server/src/modules/matching/matching.service.ts` (L1215, 1253)
  - 현재: `Number(query.limit)` NaN 시 기본값 20 사용되지만 타입 불명확
  - 수정: `parseInt` + `isNaN` 명시적 검증

- [ ] **#26 동적 import 순환 의존**
  - 파일: `matching.service.ts` → `pins.service.ts` 동적 import
  - 수정: 생성자 주입으로 변경

- [ ] **#27 const 미사용 위젯**
  - 파일: 여러 화면의 내부 위젯
  - 현재: 불변 위젯에 `const` 미적용 → 불필요한 재생성
  - 수정: const 생성자 + const 인스턴스 사용

- [ ] **#28 메시지 읽음 처리 전체 리스트 복사**
  - 파일: `app/lib/providers/chat_provider.dart` (L288-300)
  - 현재: 1개 읽음 처리에 전체 메시지 리스트 O(n) 복사
  - 수정: indexed Map 또는 배치 업데이트

- [ ] **#29 폴링 60초 cap 무한 반복**
  - 파일: `app/lib/providers/matching_provider.dart` (L370-376)
  - 현재: 서버 다운 시 60초마다 무한 요청
  - 수정: max attempt 후 중단, 유저 액션에서만 재시작

- [ ] **#30 Repository try-catch 반복**
  - 파일: `matching_repository.dart`, `chat_repository.dart`, `user_repository.dart`
  - 수정: `BaseRepository._handleError()` 추출

- [ ] **#31 build()에 복잡한 필터 로직**
  - 파일: `app/lib/screens/matching/match_list_screen.dart` (L163-173)
  - 수정: Notifier 메서드 또는 별도 함수로 추출

- [ ] **#32 소켓 재연결 시 room 중복 join**
  - 파일: `app/lib/core/network/socket_service.dart` (L114-129)
  - 수정: `isAlreadyJoined` 체크 추가

- [ ] **#33 desiredDate 대신 createdAt 할당**
  - 파일: `server/src/workers/matching-queue.worker.ts` (L362)
  - 현재: `desiredDate: pairA.createdAt` → 잘못된 필드 할당
  - 수정: 매칭 요청의 `desiredDate` 사용

- [ ] **#34 ScoreChangeType 잘못된 enum**
  - 파일: `server/src/workers/match-accept-timeout.worker.ts` (L495)
  - 현재: 보상에 `NO_SHOW_PENALTY` 타입 사용
  - 수정: `NO_SHOW_COMPENSATION` 사용

- [ ] **#35 admin.service todayStart UTC 기준**
  - 파일: `server/src/modules/admin/admin.service.ts` (L23-24)
  - 수정: `getKSTMidnight()` 사용

- [ ] **#36 Promise.all 에러 미처리**
  - 파일: `server/src/modules/matching/matching.service.ts` (L748-756)
  - 현재: 이벤트 발행 실패 시 전체 매칭 수락 실패 가능
  - 수정: `Promise.allSettled()` 사용

---

## Phase 4 — 코드 품질 (지속)

### LOW

- [ ] **#37 매직 넘버 추출**
  - 30분 TTL, 10초 폴링, 색상값 `0xFF0A0A0A`, 아바타 크기 56 등
  - 수정: `constants.dart` / `constants.ts` 파일 생성

- [ ] **#38 프로덕션 로깅 체계 부재**
  - 현재: `debugPrint()` / `console.log()` 만 사용
  - 수정: Sentry/DataDog 등 로깅 서비스 연동

- [ ] **#39 Message 모델 빈 문자열 허용**
  - 파일: `app/lib/models/message.dart`
  - 수정: factory에서 `assert(senderId.isNotEmpty)` 추가

- [ ] **#40 워커 메트릭 미수집**
  - 매칭 생성/실패, 수락 타임아웃, ELO 계산 에러 등 추적 없음
  - 수정: Prometheus/OpenTelemetry 카운터 추가

- [ ] **#41 미사용 변수 할당**
  - 파일: `server/src/modules/games/games.service.ts` (L373)
  - `isCasual` 조기 할당
  - 수정: 사용 시점으로 이동

- [ ] **#42 에러 코드 enum 일부 미정의**
  - `AUTH_DUPLICATE_EMAIL`, `AUTH_APPLE_FAILED` 등 일부 미등록
  - 수정: 모든 사용처 에러 코드 enum 등록 확인

- [ ] **#43 모델 필드 검증 부재**
  - fromJson에서 타입 캐스팅만, 값 유효성 미검증
  - 수정: 필수 필드 assertion 추가

- [ ] **#44 테스트 커버리지 부족**
  - 현재: e2e 테스트 일부만 존재
  - 수정: 핵심 비즈니스 로직 (ELO, 매칭 큐, CI 중복) 단위 테스트 추가

---

## 진행 상황

| Phase | 상태 | 완료 | 전체 |
|-------|------|------|------|
| Phase 1 (보안+크래시) | 미시작 | 0 | 9 |
| Phase 2 (성능+안정성) | 미시작 | 0 | 13 |
| Phase 3 (리팩토링) | 미시작 | 0 | 14 |
| Phase 4 (코드 품질) | 미시작 | 0 | 8 |
| **합계** | | **0** | **44** |
