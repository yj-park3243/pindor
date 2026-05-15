# 앱 에러 로그 트리아지 (2026-05-12)

운영 RDS `spots.app_error_logs` 테이블에 쌓인 앱 에러 21건을 분류하고, 코드 수정이 필요한 항목·근거·구체 변경 위치를 정리한 문서.

## 환경
- API: `https://api.pins.kr/v1`
- 운영 RDS: `spots-db.cuhooenm6qww.ap-northeast-2.rds.amazonaws.com` / DB: `spots`
- 데이터 소스: `app_error_logs` 테이블 (Flutter `ErrorReporter`가 적재)
- 분석 범위: 2026-05-10 00:53 ~ 2026-05-12 06:25 (UTC) / 총 21건
- 메타: 21건 전부 `user_id = NULL`, `device_info` 의 `platform`·`appVersion` 모두 비어 있음

## 요약

| 카테고리 | 건수 | 액션 |
|---|---|---|
| 🔴 실제 런타임 버그 | 3 | **코드 수정 필요 (3건)** |
| 🟡 광고 SDK MissingPluginException (개발 중 일회성) | 8 | 무시 — 정식 빌드 후 미발생 확인 |
| 🟢 E2E/Integration 테스트 실패 (`screen_name=running a test`) | 10 | 테스트 코드 셀렉터·타임아웃 정비 (별건) |
| 🔵 메타 수집 누락 | 21 (전부) | `ErrorReporter` 보강 |

---

## 🔴 수정 대상 (코드 변경)

### F-001 · AppToast OverlayEntry 중복 remove로 NoSuchMethodError

| 항목 | 내용 |
|---|---|
| 발견 로그 | `77877976-1e1c-…` (2026-05-12 06:25:58, **가장 최근**) |
| 영향 | 토스트가 빠르게 연속 호출될 때 silent crash. 사용자에겐 토스트 사라짐만 보일 수 있으나 Zone 캐치에서 잡힌 진짜 예외 |
| 심각도 | **High** — 가장 자주 쓰이는 공통 위젯에서 발생 |

#### 증상
```
Null check operator used on a null value
#0  OverlayEntry.remove (overlay.dart:228)
#1  AppToast._show.<anonymous closure>.<anonymous closure> (app_toast.dart:51)
#2  _ToastOverlayState._dismiss (app_toast.dart:179)
#3  _ToastOverlayState._showAndHide (app_toast.dart:172)
```

#### 원인 (race condition)
`app/lib/widgets/common/app_toast.dart:43-58`

```dart
_currentEntry?.remove();   // ① 이전 토스트 강제 제거 (overlay에서 detach)
_currentEntry = null;

late OverlayEntry entry;
entry = OverlayEntry(
  builder: (_) => _ToastOverlay(
    duration: duration,
    onDismissed: () {
      entry.remove();      // ② 타이머 만료 시 자기 remove
      if (_currentEntry == entry) _currentEntry = null;
    },
    ...
  ),
);
```

시나리오:
1. 토스트 A 표시 → `_ToastOverlay`의 `_showAndHide` 타이머 시작
2. 타이머가 만료되기 직전 토스트 B가 들어옴
3. ①에서 A의 entry가 detach됨 (`_overlay = null`)
4. B 삽입 직후 A의 `_showAndHide`가 끝나 `_dismiss → onDismissed → entry.remove()` 호출
5. 이미 detach된 entry라 `OverlayEntry.remove()` 내부에서 `_overlay!.something` → null check 폭발

#### 수정 방안 (1줄)
`app/lib/widgets/common/app_toast.dart:51` 의 `entry.remove()` 호출을 `OverlayEntry.mounted` 가드로 감싼다.

```dart
onDismissed: () {
  if (entry.mounted) entry.remove();
  if (_currentEntry == entry) _currentEntry = null;
},
```

`OverlayEntry.mounted` — 현재 Overlay에 attach되어 있는지 반환하는 Flutter 공식 API. 외부에서 먼저 remove 됐다면 false.

#### 검증
- 토스트 1회 표시 → 정상 사라짐 (회귀 없음)
- 토스트 표시 후 1~2초 내 새 토스트 트리거 → 첫 토스트 즉시 사라지고 두 번째만 표시, 예외 없음
- `flutter analyze` 클린

---

### F-002 · _RankNumber rank 음수 입력 시 RangeError

| 항목 | 내용 |
|---|---|
| 발견 로그 | `6ff2c994-…` (2026-05-10 00:53:34) |
| 영향 | 랭킹 리스트 타일 렌더링 중 예외 → 해당 타일 빨간 화면 또는 부모 위젯 빌드 깨짐 |
| 심각도 | **Medium** — 1회 관측, 재현 경로 불명. 가드만 추가 |

#### 증상
```
RangeError (length): Invalid value: Not in inclusive range 0..2: -1
#0  List.[] (growable_array.dart)
#1  _RankNumber.build (ranking_list_tile.dart:127:24)
```

#### 원인
`app/lib/widgets/ranking/ranking_list_tile.dart:117-127`

```dart
if (rank >= 1 && rank <= 3) {
  final colors = [Color(0xFFFFD700), Color(0xFFC0C0C0), Color(0xFFCD7F32)];
  ...
  color: colors[rank - 1],   // ← rank 가 0 이하인데 분기 안에 들어온 케이스
}
```

가드 `rank >= 1 && rank <= 3` 안에서 -1이 발생했다는 건 (a) 호출자가 비정상 rank를 넘김 + 분기 평가 순서 문제 (b) 핫리로드 도중 stale 위젯 빌드 등. 일회성이지만 0 이하 방어 가드는 필수.

#### 수정 방안
`ranking_list_tile.dart:127` 인덱스 접근을 안전하게 clamp.

```dart
color: colors[(rank - 1).clamp(0, colors.length - 1)],
```

또는 가드 조건을 분기 진입 시점에 한 번 더 명확히 (예: `if (rank >= 1 && rank <= 3) { final idx = rank - 1; ... colors[idx] ... }`).

#### 검증
- 랭킹 화면 진입 → 1~3위 메달 색상 정상 (금/은/동 유지)
- 4위 이상 항목 → 기존 분기 그대로
- 단위 테스트(가능하면): rank=0, rank=-1, rank=4 → 예외 없이 렌더

---

### F-003 · ErrorReporter device_info / userId 누락

| 항목 | 내용 |
|---|---|
| 발견 근거 | 21건 전부 `device_info.platform / appVersion = NULL`, `user_id = NULL` |
| 영향 | 에러 분석 시 플랫폼·버전·유저 식별 불가 → 우선순위 판단 어려움 |
| 심각도 | **Low (운영)** / **High (관측성)** |

#### 현재 코드
`app/lib/core/error/error_reporter.dart` 에서 reportError 시 `device_info`/`userId`를 채우지 않거나, 채우는 경로가 인증 전 시점에 실행됨.

#### 수정 방안
1. `ErrorReporter.initialize()` 시점에 `package_info_plus` + `Platform.operatingSystem` 으로 `platform`, `appVersion`, `osVersion` 캐시
2. `reportError()` 호출 시 캐시된 메타 + 현재 로그인 유저 id (auth provider에서 sync 조회) 첨부
3. 서버 `error-log.routes.ts`가 이미 받는 필드인지 확인 후 매칭

> 별건이지만 다음 분석을 위해 같이 처리 권장.

---

## 🟡 무시 (광고 SDK 초기화 일회성) — 8건

| 시각 (UTC) | 메시지 |
|---|---|
| 2026-05-12 02:01~02:02 | `MissingPluginException(No implementation found for method MobileAds#initialize ...)` (4건) |
| 2026-05-12 02:01~02:02 | `MissingPluginException(No implementation found for method _init ...)` (4건) |

- `google_mobile_ads` 추가 직후 풀 리스타트 없이 핫리로드만 한 상태에서 `MobileAds.instance.initialize()` 호출 시 발생하는 전형
- 정식 빌드 이후 재발 시점에 다시 분석. 현재로선 액션 없음

---

## 🟢 E2E/Integration 테스트 실패 — 10건 (별건)

| 메시지 | 건수 |
|---|---|
| `Found 0 widgets with text "홈"` | 4 |
| `Found 0 widgets with text "오늘 대결 나가고 싶다!"` | 2 |
| `TimeoutException: 폴링 조건이 600초 내에 충족되지 않았습니다` | 2 |
| `TimeoutException: 폴링 조건이 180초 내에 충족되지 않았습니다` | 1 |
| `pumpAndSettle timed out` | 1 |

- 모두 `screen_name = "running a test"` — patrol/integration_test 환경
- 운영 사용자 영향 없음. 별도 PR에서 셀렉터·대기 로직 정비
- 본 트리아지 범위에서 제외

---

## 🔵 RenderFlex overflow 42px (미해결, 추적용)

| 항목 | 내용 |
|---|---|
| 발견 로그 | `e81b3391-…` (2026-05-11 03:41) |
| screen_name | `during layout` (어느 화면인지 불명) |
| stack | 없음 |

`ErrorReporter`가 화면 식별 메타를 첨부하지 못한 상태. F-003 보강 이후 재발 시 즉시 위치 추적 가능. 지금은 액션 보류.

---

## 작업 순서 / 검증 체크리스트

```
1. F-001  AppToast.mounted 가드 추가 (app_toast.dart:51)
   → 검증: 연속 토스트 트리거 후 예외 없음, flutter analyze 클린
2. F-002  _RankNumber clamp 가드 (ranking_list_tile.dart:127)
   → 검증: 랭킹 화면 1~3위 색상 회귀 없음
3. F-003  ErrorReporter 메타(platform/appVersion/userId) 채움
   → 검증: 신규 에러 로그에 device_info.platform/appVersion 채워짐 확인
4. (별건) E2E 테스트 셀렉터 점검 — 본 작업 범위 제외
```

수정 PR 머지 후 1~2일 관찰 → `app_error_logs`에서 같은 메시지 재발 없는지 SELECT로 확인.

## 메모
- 본 트리아지는 운영 사용자 환경의 패턴이라기보다 **개발/테스트 환경 노이즈가 상당 부분**임 (광고 SDK 8건, 테스트 10건). 진짜 운영 버그는 F-001/F-002 두 건.
- `app_error_logs`에 평소에도 거의 안 쌓인다는 점은 ErrorReporter가 잘 동작하고 있다기보다, **메타 누락 + 비인증 상태에서 호출되는 경로가 많음**을 시사. F-003 처리로 다음 트리아지 품질이 크게 올라갈 것.

---

## 적용 결과 (2026-05-12 작업)

| ID | 파일:라인 | 변경 | analyze |
|---|---|---|---|
| F-001 | `app/lib/widgets/common/app_toast.dart:52` | `if (entry.mounted) entry.remove();` | ✅ clean |
| F-002 | `app/lib/widgets/ranking/ranking_list_tile.dart:128` | `colors[(rank - 1).clamp(0, colors.length - 1)]` | ✅ clean (기존 deprecated 경고만) |
| F-003 | `app/lib/core/error/error_reporter.dart` | `package_info_plus`로 `appVersion`/`buildNumber` 캐시, deviceInfo에 첨부 (기존 `os`/`osVersion`/`isDebug`는 이미 채워지고 있었음을 DB 직접 SELECT로 확인) | ✅ clean |

### 리뷰 노트
- **F-001**: `app_toast.dart:43`의 `_currentEntry?.remove()`도 이론적으로 동일 race 가능. 다만 정상 경로에서 `_currentEntry`는 `onDismissed`에서 null로 정리되므로 not-null이면 mounted=true가 사실상 보장. 실측 발생 없음. **별건 후속으로만 기록**.
- **F-002**: clamp가 들어가도 정상 경로(rank 1~3)에서 동작은 동일. 비정상 입력(rank=0/-1 등)이 분기에 진입하면 1위 색(금)으로 폴백 — crash보다 안전.
- **F-003**: `PackageInfo.fromPlatform()` 캐시 완료 전 발생한 에러는 `appVersion`/`buildNumber`가 빠짐. 초기화 직후 짧은 윈도우라 허용.

### 별건 후속 (본 트리아지 범위 밖)
- `app/lib/core/version/version_check_service.dart:127`, `app/lib/widgets/common/in_app_notification.dart:209` 의 `OverlayEntry` 사용처에도 동일 race 패턴 잠재. 필요 시 같은 가드 적용.
- E2E 테스트 셀렉터 정비 (10건).
- `app_error_logs` 향후 1~2주 모니터링 — F-001/F-002 동일 메시지 재발 없는지, F-003 처리 후 `device_info.appVersion` 채워지는지 확인.
