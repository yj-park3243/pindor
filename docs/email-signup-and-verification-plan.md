# 이메일 회원가입 + 첫 로그인 본인인증 + 계정 병합 기획서

> 작성일: 2026-04-27
> 최종 수정: 2026-04-27 (사용자 결정사항 반영)
> 상태: **결정 완료, 구현 대기**
> 목적: 소셜 로그인 외 이메일 회원가입 옵션을 추가하고, 모든 신규 가입자에게 첫 로그인 시 KCP 본인인증을 강제. 본인인증 결과(이름+전화+생년월일)로 기존 계정 자동 병합.

---

## 1. 현황 분석

### ✅ 이미 구현된 인프라
- **서버**:
  - 이메일 회원가입/로그인 API: `auth.service.ts#signupWithEmail`, `auth.service.ts#emailLogin`
  - 라우트: `POST /v1/auth/email/signup`, `POST /v1/auth/email/login` (auth.routes.ts)
  - 검증 스키마: `auth.schema.ts#emailLoginSchema`
  - SocialAccount enum에 `EMAIL` 값
  - KCP 본인인증 모듈: `modules/auth/kcp.routes.ts`
  - users 테이블 KCP 컬럼: `phone_number`, `ci`, `di`, `real_name`, `carrier`, `is_verified`, `verified_at`
  - `ErrorCode.VERIFICATION_REQUIRED` 정의

- **앱**:
  - 본인인증 화면: `screens/auth/phone_verification_screen.dart` (KCP 웹뷰 기반)
  - 인증 후 `isVerified: true` 갱신 처리 로직
  - login_screen에서 `isNewUser && !isVerified` 분기 → `phoneVerification` 라우트로 이동

### ❌ 미구현
- **앱**: 이메일 회원가입 화면 + 이메일 로그인 화면 + 로그인 화면의 "이메일로 가입/로그인" 버튼
- **앱/서버**: 첫 로그인 시 본인인증 강제 흐름 — 소셜 로그인 신규 유저에게도 동일 적용 + 미인증 유저의 매칭/채팅 등 핵심 기능 차단 정책

---

## 2. 목표 & 비목표

### 목표
1. 로그인 화면에 **"이메일로 가입"** + **"이메일로 로그인"** 진입점 노출
2. 모든 가입 경로(이메일/카카오/구글/Apple)에서 **첫 로그인 직후 본인인증 강제**
3. 본인인증 미완료 유저는 **앱의 매칭·채팅·팀 기능 접근 차단**, 본인인증 화면으로 redirect
4. 비밀번호 찾기/재설정 (선택, 이번 범위)

### 비목표
- 소셜 로그인 추가 (이미 카카오/Apple/Google 있음)
- 이메일 인증 메일 발송 (회원가입 시 이메일 검증) — 본인인증으로 대체
- 비밀번호 찾기는 Phase 2로 미룸 (이메일 발송 인프라 필요)

---

## 3. 가입/로그인 흐름

### 3-1. 이메일 가입 (신규)
```
[로그인 화면]
  ├─ 카카오 로그인 (기존)
  ├─ Apple 로그인 (기존)
  ├─ Google 로그인 (기존)
  ├─ ── 또는 ──
  ├─ ▶ 이메일로 로그인
  └─ ▶ 이메일로 가입
        ↓
   [이메일 가입 화면]
     - 이메일
     - 비밀번호 (8자 이상, 영문+숫자)
     - 비밀번호 확인
     - 이용약관/개인정보 동의 체크
     - [가입하기] 버튼
        ↓
   POST /v1/auth/email/signup
     → JWT accessToken + refreshToken 발급
     → users 레코드 생성 (isVerified=false, isNewUser=true)
        ↓
   [본인인증 화면] (KCP 웹뷰) — 강제
        ↓
   [프로필 설정 화면]
        ↓
   [종목/핀 설정] → [홈]
```

### 3-2. 이메일 로그인 (신규)
```
[로그인 화면] → ▶ 이메일로 로그인
   ↓
[이메일 로그인 화면]
  - 이메일
  - 비밀번호
  - [로그인]
  - 비밀번호를 잊으셨나요? (비활성/Phase 2)
   ↓
POST /v1/auth/email/login
  → 200 OK + JWT
  → isVerified=false인 경우에도 토큰은 발급, 클라이언트가 본인인증 화면으로 redirect
```

### 3-3. 첫 로그인 본인인증 (모든 가입 경로 통합)
```
로그인 성공 (소셜/이메일 모두) → JWT 받음
  ↓
GET /v1/users/me
  ↓
응답에 isVerified=false 또는 verifiedAt=null 이면
  ↓
앱이 자동으로 [phoneVerification] 라우트로 redirect
  ↓
KCP 본인인증 진행 (기존 화면 그대로)
  ↓
서버 KCP 콜백 → users.is_verified=true, ci/di/phone_number/real_name 저장
  ↓
홈 화면 진입 가능
```

---

## 4. 데이터 모델

### 변경 없음
이미 모든 컬럼이 준비됨:
- `users.email`, `users.password_hash` (이메일 가입용 — `social_accounts.providerId=email, password_hash` 확인 필요)
- `users.is_verified`, `users.verified_at`, `users.ci`, `users.di`, `users.phone_number`, `users.real_name`, `users.carrier`

> ⚠ 서버 코드 확인: 이메일 가입 시 비밀번호 해시 저장 위치가 `social_accounts.providerId`(이메일) + 별도 password 컬럼인지, `users.password_hash`인지 확정 필요.

---

## 5. 서버 변경 (최소)

### 변경 거의 없음 — 기존 API 그대로 사용
1. **`emailSignup` 응답에 강제 본인인증 플래그 추가** (선택):
   - 응답 body에 `requiresVerification: true` 추가
2. **인증 미들웨어**:
   - 매칭·채팅·게임 라우트에 `requireVerified` 미들웨어 추가
   - 미인증 유저 호출 시 403 + `VERIFICATION_REQUIRED` 에러 반환
3. **이메일 중복 체크 강화** (기존 코드 확인 필요):
   - 같은 이메일이 카카오/Apple로도 가입된 경우 안내 메시지 표준화

---

## 6. 앱 변경 (대부분의 작업)

### 6-1. 신규 화면
| 파일 | 역할 |
|---|---|
| `screens/auth/email_signup_screen.dart` | 이메일/비밀번호/약관 동의 + 가입 버튼 |
| `screens/auth/email_login_screen.dart` | 이메일/비밀번호 + 로그인 버튼 |

### 6-2. 라우트 추가
```dart
class AppRoutes {
  static const String emailSignup = '/auth/email/signup';
  static const String emailLogin   = '/auth/email/login';
}
```

### 6-3. 로그인 화면 수정 (`login_screen.dart`)
- 소셜 버튼들 아래 구분선 + 2개 버튼:
  - "이메일로 로그인" → `/auth/email/login`
  - "이메일 가입하기" → `/auth/email/signup`

### 6-4. 본인인증 강제 — 라우터 redirect 강화 (`config/router.dart`)
- 기존: `isNewUser && !isVerified` → `phoneVerification`
- 신규: **`isVerified == false`이면 무조건 `phoneVerification`** (신규/기존 무관)
- 단, 본인인증 화면 자체와 로그인 화면, 스플래시는 예외

```dart
if (isAuthenticated && !isVerified) {
  // 본인인증 미완료 → 본인인증만 가능
  if (location != AppRoutes.phoneVerification &&
      location != AppRoutes.splash) {
    return AppRoutes.phoneVerification;
  }
}
```

### 6-5. 이메일 가입/로그인 repository
`repositories/auth_repository.dart`에 두 메서드 추가:
```dart
Future<void> signupWithEmail({required String email, required String password});
Future<void> loginWithEmail({required String email, required String password});
```

### 6-6. AuthProvider state
- 이메일 로그인 성공 시 동일하게 토큰 저장 + 사용자 정보 fetch
- `isVerified`가 false면 phoneVerification으로 redirect

---

## 7. UI/UX 디테일

### 이메일 가입 화면
- 이메일: 정규식 검증 + 중복 체크 (서버 응답)
- 비밀번호: **최소 8자, 영문+숫자 포함** (서버/앱 양쪽 검증)
- 비밀번호 확인: 일치 검증
- 이용약관 + 개인정보처리방침 체크 필수
- 약관 보기 링크 → 노션/사이트로 외부 이동
- 가입 성공 → "본인인증을 진행해주세요" 토스트 + 본인인증 화면

### 이메일 로그인 화면
- 이메일/비밀번호 input
- 비밀번호 표시/숨김 토글 아이콘
- 로그인 실패 시 에러 메시지 표준화:
  - 비밀번호 틀림: "이메일 또는 비밀번호가 올바르지 않습니다."
  - 미가입 이메일: "가입되지 않은 이메일입니다."
- "비밀번호를 잊으셨나요?" 링크 비활성 + tooltip "추후 지원 예정"

### 본인인증 화면 (기존)
- 변경 없음. 단 router redirect로 강제 진입되므로 **뒤로가기 불가** 처리
- WillPopScope 또는 PopScope로 뒤로가기 시 "본인인증을 완료해야 이용 가능합니다" 토스트

---

## 8. 본인인증 미완료 시 차단되는 기능

| 기능 | 차단 여부 |
|---|---|
| 매칭 신청/수락 | ❌ 차단 |
| 채팅 송수신 | ❌ 차단 |
| 팀 가입/생성 | ❌ 차단 |
| 게임 결과 입력 | ❌ 차단 |
| 핀 게시판 글 작성 | ❌ 차단 |
| 신고/문의 | ✅ 가능 |
| 프로필 조회 (본인) | ✅ 가능 |
| 핀/랭킹 조회 | ✅ 가능 (읽기 전용) |
| 알림 조회 | ✅ 가능 |

→ 매칭/채팅/게임 라우트에 `requireVerified` 미들웨어 추가.

---

## 9. 마이그레이션

### 기존 가입 유저 (이미 가입한 카카오/Apple/Google 유저)
- `is_verified=false` 상태 → 다음 로그인 시 강제 본인인증 화면
- **공지 푸시** 1회: "보다 안전한 서비스를 위해 본인인증이 필요합니다"
- 미인증 기간 동안엔 매칭/채팅 등 차단 (위 표 기준)

### 데이터
- 추가 마이그레이션 불필요 (KCP 컬럼 이미 있음)

---

## 10. 단계별 출시

| 단계 | 내용 | 기간 |
|---|---|---|
| **Phase 1** | 이메일 가입/로그인 화면 + 라우트 + 로그인 화면 진입점 | 0.5일 |
| **Phase 2** | 라우터 redirect 강화 (`!isVerified` 무조건 인증 화면) | 0.5일 |
| **Phase 3** | 서버 미들웨어로 매칭/채팅 등 미인증 차단 | 0.5일 |
| **Phase 4** | 기존 미인증 유저 공지 푸시 | 0.5일 |
| **Phase 5 (선택)** | 비밀번호 찾기/재설정 (이메일 발송) | 1일 |

---

## 11. 채택된 결정사항 (구현 확정)

### 가입/로그인
- [x] **비밀번호 정책**: 8자 이상 + 영문+숫자 (특수문자 필수 X)
- [x] **이메일 인증 메일 발송 X** — 본인인증으로 대체 (이메일 검증 별도 절차 없음)
- [x] **같은 이메일은 다중 provider 허용**, 단 본인인증 시 ci 기준으로 **자동 계정 병합** (섹션 13 참조)
- [x] **비밀번호 찾기 이번 출시 포함** — **Firebase Auth로 위임** (별도 인프라 없이 무료 메일 발송. 섹션 14 참조)

### 본인인증
- [x] 모든 가입자(소셜+이메일)에 본인인증 강제
- [x] 기존 미인증 유저도 다음 로그인 시 강제
- [x] **만 14세 미만 가입 가능** (KCP 본인인증만 통과하면 OK, 연령 제한 X)
- [x] **로그인 안 하면 모든 페이지 접근 불가** (스플래시 → 로그인만 노출, 미인증 유저는 본인인증 화면만)
- [x] 본인인증 완료 후 모든 기능 사용 가능

### 운영
- [x] **모든 앱 설치자에게 공지 푸시** (FCM 토큰 보유 전체 유저)
- [ ] 약관/개인정보 처리방침 URL — 추후 등록 (코드는 placeholder URL로 일단 빌드)

---

## 12. (이전 섹션 — 변경 없음)
> 위 결정사항 반영으로 일부 정책 강화됨. 섹션 8(차단 기능 범위)는 "로그인 안 하면 모든 페이지 차단"으로 더 강력해짐.

---

## 13. ⭐ 계정 병합 (Account Merge)

### 핵심 원칙
**같은 사람 = 같은 ci(KCP 발급 본인 식별 키)**.
KCP 본인인증 결과로 받는 `ci` (Connecting Information, 88자 hash)가 진짜 사람을 가리키는 unique key.
이름/전화/생년월일 단일 필드는 변경되거나 동일인이 있을 수 있어 ci로 판별이 표준.

> 사용자 요구는 "이름 + 전화번호 + 생년월일"이지만, KCP가 이미 ci를 발급하므로 ci가 동일 == 동일인 보장됨. 실제 비교는 **ci 단일 키**로 진행 (이름/전화/생년월일은 표시용 데이터로 저장).

### 시나리오 매트릭스

| 케이스 | 동작 |
|---|---|
| **A. 신규 ci** (이전 인증 이력 없음) | 정상 진행 — users.ci 저장, isVerified=true |
| **B. 같은 ci로 다른 계정 존재** (예: 카카오로 가입했던 유저가 이메일로 새로 가입 후 본인인증) | **자동 병합**: 새 social_account를 기존 user에 연결 + 새 user 레코드 삭제. JWT는 기존 user로 재발급 |
| **C. 같은 ci + 같은 provider 다른 providerId** (예: 카카오 계정 두 개로 가입) | provider+providerId가 둘 다 같은 경우만 동일. 다르면 새 social_account를 기존 user에 연결 |
| **D. 동일 user에 같은 ci로 재인증 시도** (재로그인) | 정상 — 단순 인증 갱신 |

### 병합 흐름

```
[KCP 인증 콜백 도착]
    ↓
[users.ci로 기존 user 조회]
    ↓
   ┌──────────────────────────────────────────────────────┐
   │ ci 동일한 다른 user 존재?                             │
   ├──────────────────────────────────────────────────────┤
   │ NO  → 현재 user에 ci/di/phone/name 저장, isVerified=true │
   │ YES → 병합 처리                                        │
   └──────────────────────────────────────────────────────┘
                    ↓
            [병합 처리]
            ─────────────────────────────────
            1. 기존 user (originalUser) 식별 — 더 오래된 createdAt 우선
            2. 신규 user (currentUser, 방금 가입)의 social_accounts → originalUser.id로 이전
            3. 신규 user의 sports_profiles, notifications, device_tokens 등 데이터 이전
               (단, 신규 user에 의미있는 데이터가 거의 없으므로 단순 이전 또는 무시)
            4. 신규 user 레코드 SOFT DELETE (status='MERGED', merged_into_user_id 컬럼)
            5. JWT 재발급 — sub=originalUser.id
            6. 클라이언트 응답:
               { merged: true, accessToken, refreshToken,
                 message: "기존 계정으로 로그인되었습니다." }
            7. 클라이언트 측: 토큰 교체 + 토스트 안내 + 홈 진입
```

### 데이터 모델 변경

```sql
-- users에 병합 추적 컬럼 추가
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS merged_into_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS merged_at TIMESTAMPTZ;

-- ci unique 제약 (이미 partial unique index 있음 — 검증)
-- 기존: CREATE UNIQUE INDEX uidx_users_ci ON users (ci) WHERE ci IS NOT NULL;
-- → 병합 후 ci는 무조건 1명만 가져야 하므로 유지
```

### 구현 위치

#### 서버
1. **`auth.service.ts#mergeOrFinalizeVerification(currentUserId, kcpResult)`** 신규
   - `kcpResult.ci`로 다른 user 검색
   - 발견 시 병합 트랜잭션 실행
   - 미발견 시 단순 ci 저장
2. **kcp.routes.ts 콜백 핸들러**: 인증 완료 시 위 메서드 호출, 응답에 `merged` 플래그 포함
3. **데이터 이전 SQL** (트랜잭션 내):
   ```sql
   -- social_accounts 이전 (UNIQUE provider+providerId 충돌 시 신규 것 삭제)
   UPDATE social_accounts SET user_id = $originalUserId WHERE user_id = $currentUserId
     AND NOT EXISTS (
       SELECT 1 FROM social_accounts s2 WHERE s2.user_id = $originalUserId
         AND s2.provider = social_accounts.provider
     );
   DELETE FROM social_accounts WHERE user_id = $currentUserId;

   -- device_tokens 이전 (FCM 푸시용)
   UPDATE device_tokens SET user_id = $originalUserId WHERE user_id = $currentUserId
     AND NOT EXISTS (
       SELECT 1 FROM device_tokens d2 WHERE d2.user_id = $originalUserId AND d2.token = device_tokens.token
     );
   DELETE FROM device_tokens WHERE user_id = $currentUserId;

   -- sports_profiles, notifications 등 — 신규 user는 가입 직후라 거의 비어있음, 그대로 CASCADE DELETE 처리
   -- (정확히는 신규 user의 sports_profiles만 삭제 — 기존 user 데이터 유지)

   -- 신규 user를 병합 표시 + 핵심 식별자 nullable 처리 (재가입 가능하도록 email 비움)
   UPDATE users SET
     status = 'MERGED',
     merged_into_user_id = $originalUserId,
     merged_at = NOW(),
     email = NULL,            -- 다른 user가 같은 이메일로 가입 가능
     ci = NULL                -- ci unique 제약 유지
   WHERE id = $currentUserId;
   ```

#### 앱
1. KCP 인증 완료 후 응답에서 `merged: true` 받으면:
   - 토스트: "기존 계정으로 로그인되었습니다 ✓"
   - 새 토큰으로 즉시 교체
   - 홈 진입

### 엣지 케이스

| 케이스 | 처리 |
|---|---|
| 같은 ci에 user가 이미 둘 이상 (DB 무결성 깨진 경우) | 가장 오래된 user를 originalUser로, 나머지 모두 병합 (관리자 알림) |
| 신규 user에 매칭/게임 이력이 있을 가능성 | 가입~본인인증 사이엔 모든 기능 차단되므로 이력 0건 보장. 안전 처리: 트랜잭션 내 sports_profiles/match_requests 등 검사 후 발견 시 병합 거부 + 관리자 알림 |
| social_accounts UNIQUE 충돌 (예: 기존 user가 카카오 + 신규 user도 카카오 — provider 같지만 providerId 다름) | provider 같은 social_account가 originalUser에 이미 있으면 신규 것 그냥 삭제 (한 user당 provider 1개 정책) |
| 병합 후 신규 user의 토큰 무효화 | refresh_tokens 테이블에서 신규 user의 모든 토큰 삭제 |

---

## 14. 이메일 인증 — Firebase Auth 풀 도입 (✅ 채택)

### 결정
이메일 회원가입/로그인/비밀번호 찾기를 **Firebase Authentication**으로 위임.
이미 `firebase_core`, `firebase_messaging`, `firebase-admin`이 도입돼 있어 추가 인프라 거의 없음.

### 도입 이유
- 비밀번호 해싱/저장/검증 = Firebase가 처리 (OWASP 표준)
- **비밀번호 재설정 메일 발송 = Firebase가 처리** (별도 이메일 인프라 필요 없음)
- 비밀번호 재설정 페이지 = Firebase 호스팅 자동 제공 (커스텀 도메인 가능)
- 앱은 `firebase_auth` 패키지만 추가 (다른 Firebase는 이미 사용 중)

### 흐름

#### 가입
```
[이메일 가입 화면] 이메일 + 비밀번호 입력
    ↓
[앱] FirebaseAuth.createUserWithEmailAndPassword()
    ↓ Firebase ID 토큰 발급
[앱] POST /v1/auth/firebase/signup { idToken }
    ↓
[서버] Firebase Admin SDK로 idToken 검증 → email/uid 추출
    ↓
[서버] users 레코드 생성 (firebase_uid 컬럼 저장, isVerified=false)
    ↓
[서버] 우리 JWT (accessToken/refreshToken) 발급
    ↓
[앱] 본인인증 화면 redirect
```

#### 로그인
```
[이메일 로그인 화면] 이메일 + 비밀번호 입력
    ↓
[앱] FirebaseAuth.signInWithEmailAndPassword()
    ↓ Firebase ID 토큰 발급
[앱] POST /v1/auth/firebase/login { idToken }
    ↓
[서버] Firebase Admin SDK로 idToken 검증 → uid로 users 조회
    ↓
[서버] 우리 JWT 발급
```

#### 비밀번호 찾기
```
[로그인 화면] 비밀번호를 잊으셨나요?
    ↓
[이메일 입력 화면]
    ↓
[앱] FirebaseAuth.sendPasswordResetEmail(email)
    ↓
[Firebase] 자동으로 비밀번호 재설정 메일 발송
    ↓
[사용자가 메일 링크 클릭]
    ↓
[Firebase 호스팅 페이지 또는 커스텀 페이지]
  - 새 비밀번호 입력 → Firebase가 직접 처리
    ↓
[비밀번호 변경 완료]
[앱 다시 로그인하면 새 비밀번호로 로그인]
```

→ **서버에 비밀번호 재설정 API 만들 필요 없음**.
→ **이메일 발송 인프라 0**.
→ **토큰 테이블 0**.

### 데이터 모델

```sql
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS firebase_uid VARCHAR(128) UNIQUE;
CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON users(firebase_uid) WHERE firebase_uid IS NOT NULL;
```

> users.password_hash는 더 이상 사용 안 함 (Firebase가 비밀번호 보유). 기존 컬럼은 nullable로 유지하다 추후 폐기.

### 서버 변경

신규 라우트:
- `POST /v1/auth/firebase/signup` (body: { idToken, agreedTerms }) → users 생성 + 우리 JWT 발급
- `POST /v1/auth/firebase/login` (body: { idToken }) → uid로 users 조회 → 우리 JWT 발급

기존 `POST /v1/auth/email/{signup,login}` 라우트는 **삭제 또는 deprecated 처리** (Firebase 기반으로 대체).

### 앱 변경

```yaml
# pubspec.yaml
dependencies:
  firebase_auth: ^5.x.x  # 신규
```

```dart
// 가입
final cred = await FirebaseAuth.instance
    .createUserWithEmailAndPassword(email: e, password: p);
final idToken = await cred.user!.getIdToken();
await api.post('/auth/firebase/signup', body: {'idToken': idToken});

// 비밀번호 찾기
await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
```

### Firebase Console 설정 (1회)
1. Authentication → Sign-in method → Email/Password 활성화
2. Templates → Password reset → 한국어 템플릿 + 발신자 이름 "핀돌" 설정
3. Authorized domains에 `app.pins.kr` 추가
4. (선택) 비밀번호 재설정 후 redirect URL: `https://app.pins.kr/auth/login`

### 비용
- Firebase Auth: **월 50,000 MAU 무료**
- 비밀번호 재설정 메일: **무제한 무료**
- ID 토큰 검증: **무료**

### 트레이드오프
| 장점 | 단점 |
|---|---|
| 인프라 0, 코드 적음 | Firebase 의존성 |
| 보안 검증 완료 (OWASP) | Firebase Auth 다운 시 이메일 가입/로그인 불가 (소셜은 영향 X) |
| 비밀번호 재설정 페이지 무료 | 비밀번호 정책 일부는 Firebase 콘솔에서만 설정 가능 |
| 이메일 발송 무료 | (없음) |

---

## 15. 참고

### 관련 파일
- 서버 인증: `server/src/modules/auth/auth.service.ts`, `auth.routes.ts`, `auth.schema.ts`
- 서버 KCP: `server/src/modules/auth/kcp.routes.ts`
- 앱 라우터: `app/lib/config/router.dart`
- 앱 로그인 화면: `app/lib/screens/auth/login_screen.dart`
- 앱 본인인증 화면: `app/lib/screens/auth/phone_verification_screen.dart`
- 앱 인증 상태: `app/lib/providers/auth_provider.dart`
