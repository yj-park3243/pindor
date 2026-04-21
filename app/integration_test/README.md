# E2E 매칭 테스트

iOS 시뮬레이터 2대를 병렬로 띄워 **매칭 → 수락 → 결과 입력 → 점수 반영** 플로우 전체를 검증하는 자동화 테스트.

## 실행

```bash
cd app
bash run_matching_test.sh
```

소요 시간: **약 1분 40초** (최초 실행은 iOS 빌드 캐시 워밍업에 3~5분 추가)

## 전제 조건

- iOS 시뮬레이터 2대 Booted 상태로 미리 실행되어 있어야 함
  - 이름 `match` (User A), `kids` (User B) — 시뮬레이터 이름 기준으로 UDID 조회
- `jq`, `curl`, `python3`, `xcrun` 설치 (모두 macOS + Xcode 기본 포함)
- 운영 API 서버(`https://api.pins.kr`) 살아있어야 함
- EC2 SSH 키(`~/WebProject2/match/spots-key.pem`)로 RDS 접근 가능해야 함 (테스트 유저 `is_verified=true` 업데이트용)

## 동작 단계

### 1. Orchestrator (쉘 스크립트)

`run_matching_test.sh`가 아래 순서로 진행:

```
[1/6] 유저 등록          POST /auth/email/register × 2 → TOKEN_A, TOKEN_B, ID_A, ID_B
[2/6] 본인인증 우회      SSH + psql로 UPDATE users SET is_verified=true, gender='MALE', birth_date='1990-01-01'
[3/6] 닉네임 설정        PATCH /users/me × 2
[4/6] 스포츠 프로필      POST /sports-profiles (GOLF, gHandicap=30) × 2
[5/6] 위치 설정          POST /users/me/location (서울 중심, 반경 50km) × 2
[6/6] 병렬 drive 실행
   ├─ 스크린샷 HTTP 서버 기동 (127.0.0.1:9998, xcrun simctl io screenshot 실행)
   ├─ flutter drive -d match (User A, 백그라운드)
   ├─ 30초 sleep (xcodebuild lock 회피)
   └─ flutter drive -d kids (User B, 백그라운드)

[Cleanup]                SSH + psql로 테스트 유저와 관련 데이터 전부 DELETE
```

### 2. Flutter 앱 플로우 (User A / User B)

각 시뮬레이터에서 `matching_e2e_test.dart`가 실행되며 아래 단계 수행:

```
┌─ User A ────────────────┐  ┌─ User B ────────────────┐
│ 1. SecureStorage 토큰 주입│  │ 1. SecureStorage 토큰 주입│
│ 2. app.main() 실행       │  │ 2. app.main() 실행       │
│ 3. 홈 도달 대기          │  │ 3. 홈 도달 대기          │
│    📸 01_home           │  │    📸 01_home           │
│ 4. 매칭 요청 생성        │  │ 4. 매칭 요청 생성        │
│    (같은 pinId로)       │  │    (같은 pinId로)       │
│ 5. 매칭 성사 폴링        │← 서버 자동 페어링 →│ 5. 매칭 성사 폴링        │
│    📸 02_matched        │  │    📸 02_matched        │
│ 6. API: 수락             │  │ 6. API: 수락             │
│ 7. CHAT 상태 대기        │  │ 7. CHAT 상태 대기        │
│    📸 03_chat           │  │    📸 03_chat           │
│ 8. Game 생성 대기        │  │ 8. Game 생성 대기        │
│    📸 04_game_created   │  │    📸 04_game_created   │
│ 9. 결과 제출 (A 승)     │  │ 9. 결과 제출 (B 패)     │
│    myCode 역산으로      │  │    myCode 역산으로      │
│    상대 verificationCode│  │    상대 verificationCode│
│10. VERIFIED 대기        │  │10. VERIFIED 대기        │
│    📸 05_result_confirmed│  │    📸 05_verified       │
│11. 내 점수 확인          │  │11. 내 점수 확인          │
│    📸 06_score_final    │  │    📸 06_score_final    │
└─────────────────────────┘  └─────────────────────────┘
```

## 핵심 설계 결정

### 토큰 주입으로 로그인 우회
- KCP 본인인증은 운영에서만 가능 → 테스트는 우회 불가피
- 쉘에서 API 등록 후 SSH로 DB `is_verified=true` UPDATE
- `--dart-define=TEST_ACCESS_TOKEN=...`로 Flutter에 토큰 전달
- Flutter가 `SecureStorage`에 토큰 저장 → 앱 시작 시 자동 로그인

### API 기반 시나리오 (UI 조작 최소화)
- 매칭 수락/결과입력 등을 **UI 탭 대신 API 호출**로 진행
- 이유: 매칭 수락 화면의 "수락/거절" 버튼 tap이 fragile했음 (예: 거절 확인 다이얼로그가 덮여서 오탭)
- 서버 상태 전환 검증이 목적이므로 API 기반이 빠르고 안정적

### verificationCode 역산
- 매칭 성사 시 서버가 requester/opponent 인증코드 각각 4자리 발급
- `submitResult` 시 **상대방의 코드**를 입력해야 검증 통과
- 테스트에서 A/B 누가 requester인지 매칭 타이밍 따라 다름 (나중 요청자가 requester)
- 해결: `getMatchDetail` 응답의 `myVerificationCode`와 `requesterVerificationCode`/`opponentVerificationCode` 비교해서 "내 코드가 아닌 것"을 상대 코드로 사용:
  ```dart
  final counterpartCode = myCode == reqCode ? oppCode : reqCode;
  ```

### HTTP 기반 스크린샷 즉시 트리거
- Flutter `binding.takeScreenshot()`은 위젯 트리만 캡처 + onScreenshot 콜백이 테스트 종료 시 일괄 실행 → 모든 프레임이 같은 이미지
- 대안: orchestrator가 Python HTTP 서버 기동 → Flutter 앱이 `http.get('http://127.0.0.1:9998/<name>')` 호출 → 호스트가 `xcrun simctl io <UDID> screenshot` 즉시 실행
- 네이티브 뷰(네이버맵 포함) 전부 포함된 실제 화면 캡처

### 프리빌드 미사용 (dart-define 한계)
- `flutter build ios` 한 번 → 두 드라이브에서 바이너리 공유하면 빌드 시간 반감 가능
- 하지만 `String.fromEnvironment('TEST_ACCESS_TOKEN')`는 컴파일 타임 상수라 빌드 시점에 박혀야 → 두 드라이브가 서로 다른 토큰 쓸 수 없음
- 현재는 각 드라이브가 빌드 → 30초 sleep으로 xcodebuild lock 회피 → 캐시 덕에 2번째 빌드는 빠름

## 현재 한계 & 개선 포인트

### 화면 스크린샷이 거의 정적
- API 기반 flow라 앱 UI는 홈 화면에 머물러 있음
- 소켓 이벤트로 매칭 수락 화면 자동 전환이 기대되지만 실제로는 이동 안 함
- iOS 알림 권한 팝업도 닫지 않아 모든 스크린샷에 포함됨
- 실제로 **01_home과 02~06은 거의 동일 이미지** (홈 + 팝업)

**실제 단계별 UI 캡처가 필요하면**:
- 알림 팝업 자동 닫기 추가 (`find.text('허용').tap()`)
- 매칭 탭으로 수동 이동 (`find.text('매칭').tap()`)
- 매칭 아이템 탭해서 상세 진입
- 결과 입력 시트 열기 (UI 탭 fragility 주의)

### ranking_entries FK 제약
- 이전 테스트 유저의 `sports_profiles`가 `ranking_entries`로 참조되어 있으면 delete 실패
- cleanup에 `DELETE FROM ranking_entries WHERE sports_profile_id IN (...)` 추가 필요 (현재 미구현)

### 프리빌드 공유 최적화 미적용
- 토큰을 런타임에 HTTP로 받아오면 `--use-application-binary` 사용 가능 → 빌드 1번으로 두 드라이브 모두 커버 (추가 30~40초 단축 가능)

## 디렉토리 구조

```
app/
├── run_matching_test.sh                   # Orchestrator
├── integration_test/
│   ├── matching_e2e_test.dart             # 테스트 진입점 (토큰 주입 + 역할 분기)
│   ├── flows/
│   │   ├── user_a_flow_ui.dart            # User A 시나리오 (매칭 → 결과 A 승)
│   │   └── user_b_flow_ui.dart            # User B 시나리오 (매칭 → 결과 B 패)
│   └── helpers/
│       ├── api_helper.dart                # Dio 래퍼 (register/accept/result/...)
│       └── test_config.dart               # 상수 (API URL, 스포츠 타입, 점수 등)
├── test_driver/
│   └── integration_test.dart              # integrationDriver() 단순 실행
└── test_screenshots/YYYYMMDD_HHMMSS/      # 실행별 결과 (PNG 12장 + log 2개)
```

## 환경 변수 / dart-define

| 이름 | 설명 |
|------|------|
| `TEST_USER_ROLE` | "A" 또는 "B" |
| `TEST_API_BASE_URL` | 기본 `https://api.pins.kr/v1` |
| `TEST_ACCESS_TOKEN` | orchestrator가 API 등록 후 받은 JWT |
| `TEST_REFRESH_TOKEN` | 동일 |
| `TEST_USER_ID` | 유저 UUID |
| `UDID_A` / `UDID_B` | 시뮬레이터 UDID (orchestrator → test_driver 환경변수) |
| `SCREENSHOT_DIR` | 스크린샷 저장 절대 경로 |

## 서버 쪽 버그 픽스 (테스트 작업 중 발견)

1. **`matching.service.ts:515`** — `calculateAge(opts.requesterBirthDate)`에서 string을 Date로 변환 안 함
   - DB `date` 컬럼이 TypeORM에서 string으로 반환 → `.getFullYear()` 호출 실패
   - 수정: `new Date(opts.requesterBirthDate)` 래핑
   - 운영 유저에게도 영향 있던 실 버그 (birthDate 설정된 유저 매칭 요청마다 500)
