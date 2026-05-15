# 친구 시스템 (Friend System)

> 상태: 기획 / 미개발
> 작성일: 2026-05-12

## 개요

자주 매칭하는 상대를 친구로 등록해 다음 매칭/팀 랭크/소셜 기능의 기반으로 삼는다. 추가로 팀 랭크의 "2인 그룹" 핵심 구성요소가 된다.

## 친구 등록 경로 (4가지)

| 경로 | 동작 | 비고 |
|------|------|------|
| **고유 코드** | 각 유저에게 8자리 영숫자 코드 발급 (예: `PNDR-A4K2`). 상대 코드 입력 → 친구 신청 | 가장 단순. 오프라인 만남 시 구두 전달 |
| **닉네임 검색** | 닉네임 일부로 검색 → 후보 리스트 → 친구 신청 | 동명이인 → 코드 같이 표기로 구분 |
| **QR 코드** | 내 프로필 QR 스캔 → 자동 친구 신청 | 오프라인 만남 핵심 동선 |
| **카카오 링크 공유** | "친구로 추가" 딥링크 → 앱 설치/실행 후 자동 신청 | 미설치 사용자 유입 효과 |

## 기능 명세

### 친구 상태
- `PENDING` — 신청 보냄 / 받음 (양쪽 다른 시점)
- `ACCEPTED` — 양쪽 수락 완료
- `BLOCKED` — 차단 (기존 차단 시스템과 연동)
- `DECLINED` — 거절 (요청 측에는 노출 안 함)

### 화면
1. **친구 목록** — 마이 탭 신규 진입점
   - 온라인/오프라인 상태 (선택)
   - 자주 만난 횟수, 최근 만남일
   - 길게 누름 → 차단/삭제
2. **친구 신청함** — 받은 신청 / 보낸 신청 탭
3. **내 코드 + QR** — 내 프로필에서 공유 가능 (카카오톡 / 메시지 / 복사)
4. **친구 추가 모달** — 코드 입력 / 닉네임 검색 / QR 스캔 / 카카오 공유 4개 버튼

### 친구 기반 후속 기능 (선 hook only)
- 매칭 화면에 "친구와 매칭" 빠른 진입
- 팀 랭크의 팀원 초대 시 친구 목록에서 선택
- 게시판 친구 활동 피드 (장기 과제)

## DB 스키마

### `friends` 테이블 신규
```sql
CREATE TABLE friends (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status          varchar(16) NOT NULL DEFAULT 'PENDING',
                  -- PENDING / ACCEPTED / BLOCKED / DECLINED
  created_at      timestamptz DEFAULT now(),
  accepted_at     timestamptz,
  UNIQUE (requester_id, addressee_id),
  CHECK (requester_id <> addressee_id)
);

CREATE INDEX idx_friends_requester_status ON friends(requester_id, status);
CREATE INDEX idx_friends_addressee_status ON friends(addressee_id, status);
```

### `users` 컬럼 추가
```sql
ALTER TABLE users
  ADD COLUMN friend_code varchar(16) UNIQUE;
-- 회원가입 시 자동 발급 (예: PNDR-A4K2)
-- 기존 유저는 마이그레이션으로 일괄 발급
```

## API 설계

```
POST   /v1/friends/request          # body: { targetUserId } 또는 { friendCode } 또는 { nickname }
POST   /v1/friends/:id/accept
POST   /v1/friends/:id/decline
DELETE /v1/friends/:id              # 친구 삭제 (양쪽 모두 ACCEPTED → DECLINED 또는 row 삭제)
GET    /v1/friends                  # 내 친구 목록
GET    /v1/friends/requests?type=received|sent
GET    /v1/users/me/friend-code     # 내 코드 + QR payload 반환
POST   /v1/friends/qr/scan          # body: { qrPayload } — 위 코드와 동일하나 QR 전용 로깅
```

## 엣지 케이스

- 자기 자신 신청 → 400 (DB CHECK로 1차 방어)
- 이미 `BLOCKED` 상태 → 신청 불가 (양방향 모두)
- 이미 `PENDING` 상태에서 또 신청 → 멱등(기존 row 반환)
- A→B 신청 후 B→A 신청 → 자동 ACCEPTED 처리 (race condition 주의: SELECT FOR UPDATE)
- 친구 삭제 후 재신청 → 가능 (row 삭제 또는 status 변경)
- 차단 해제 시 친구 관계 복구 안 됨 (다시 신청해야 함)

## 카카오 링크 공유

- 카카오 SDK `KakaoLink` 사용
- 딥링크: `pindor://friend/add?code=PNDR-A4K2`
- 앱 미설치 → App Store / Play Store fallback (Universal Link / App Link)

## QR 코드

- 페이로드: `pindor://friend/add?code=PNDR-A4K2` (카카오 링크와 동일)
- 패키지: `qr_flutter` (생성), `mobile_scanner` (스캔)
- 보안: 코드만 들어가므로 도용해도 친구 신청만 가능. 추가 보호 불필요.

## UI 흐름 (간단)

```
마이 탭
 └─ 친구 [N명]
     ├─ 친구 목록
     ├─ 친구 신청함 (받음 / 보냄)
     └─ [+] 친구 추가
         ├─ 내 코드/QR 표시
         ├─ 코드 입력
         ├─ 닉네임 검색
         ├─ QR 스캔
         └─ 카카오로 공유
```

## 마일스톤

1. DB 스키마 + 친구 코드 발급 마이그레이션
2. REST API + 단위 테스트
3. 친구 목록 / 신청함 UI
4. 친구 추가 4개 경로 (코드 → 닉네임 → QR → 카카오 순)
5. 어드민 — 친구 관계 통계, 차단 관리 연동
6. 알림 — 친구 신청/수락 시 푸시
