# 신고/문의 접수 시스템 설계

> 작성일: 2026-04-04

## 1. 현행 시스템

- `Report` 모델 존재: `targetType` (USER, POST, COMMENT, GAME_RESULT, CHAT)
- 어드민에서 PENDING → REVIEWED → RESOLVED/DISMISSED 처리
- 문의(Support) 전용 채널 없음
- 자동 제재 규칙 없음

## 2. 개선안

### 2.1 신고 유형 확장

| 유형 | 대상 | 신고 사유 (선택형) |
|------|------|-------------------|
| USER | 유저 프로필 | 부적절한 프로필, 사기, 비매너, 노쇼 반복, 랭크 조작 |
| POST | 게시글 | 스팸, 욕설/혐오, 허위 정보, 광고, 부적절한 이미지 |
| COMMENT | 댓글 | 욕설/혐오, 스팸, 개인정보 노출 |
| GAME_RESULT | 게임 결과 | 허위 결과, 점수 조작, 증거 미제출 |
| CHAT | 채팅 메시지 | 욕설/혐오, 성희롱, 협박, 스팸 |
| **MATCH** (신규) | 매칭 | 노쇼, 매칭 후 연락두절, 비매너 플레이 |

### 2.2 신고 프로세스

```
[유저] 신고 접수
   ↓
[시스템] 자동 분류 + 중복 체크
   ↓
[시스템] 자동 제재 조건 확인
   ├── 조건 충족 → 자동 제재 (정지/경고)
   └── 조건 미충족 → 어드민 큐에 추가
         ↓
      [어드민] 검토
         ├── 타당 → 제재 (경고/정지/영구정지)
         └── 부당 → 기각
```

### 2.3 자동 제재 규칙

| 조건 | 자동 제재 |
|------|-----------|
| 7일 내 동일 유저에 대한 신고 3건+ (서로 다른 신고자) | 24시간 임시 정지 + 어드민 검토 |
| 30일 내 동일 유저에 대한 신고 5건+ | 7일 정지 + 어드민 검토 |
| 노쇼 신고 3회 누적 (전체 기간) | 72시간 매칭 제한 |
| 게임 결과 분쟁 5회 누적 | 결과 입력 제한 + 어드민 검토 |

### 2.4 제재 단계

| 단계 | 제재 | 해제 조건 |
|------|------|-----------|
| 1차 경고 | 경고 알림 | - |
| 2차 경고 | 24시간 기능 제한 (매칭/채팅 불가) | 자동 해제 |
| 1차 정지 | 7일 정지 | 자동 해제 |
| 2차 정지 | 30일 정지 | 자동 해제 |
| 영구 정지 | 계정 비활성화 | 어드민 수동 해제만 가능 |

### 2.5 문의 접수 시스템

**현행**: 없음
**개선안**: 인앱 문의 + Support 채팅룸

#### 문의 카테고리
| 카테고리 | 설명 |
|----------|------|
| ACCOUNT | 계정 관련 (로그인, 탈퇴, 정보 변경) |
| MATCH | 매칭 관련 (매칭 오류, 취소, 노쇼) |
| SCORE | 점수/등급 관련 (점수 오류, 등급 이의) |
| PAYMENT | 결제 관련 (향후 유료 기능 대비) |
| BUG | 버그 제보 |
| SUGGESTION | 건의사항 |
| OTHER | 기타 |

#### 문의 플로우
```
[유저] 마이 > 고객센터 > 문의하기
   ↓
[유저] 카테고리 선택 + 제목 + 내용 + 스크린샷(선택)
   ↓
[시스템] Support 채팅룸 자동 생성 (type: SUPPORT)
   ↓
[어드민] 문의 확인 + 채팅으로 응답
   ↓
[유저] 알림 수신 + 채팅으로 확인
```

## 3. DB 스키마 변경

### 3.1 Report 모델 확장
```prisma
model Report {
  // 기존 필드 유지
  id          String           @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  reporterId  String           @map("reporter_id") @db.Uuid
  targetType  ReportTargetType @map("target_type")
  targetId    String           @map("target_id") @db.Uuid
  reason      String           @db.VarChar(50)
  description String?          @db.Text
  status      ReportStatus     @default(PENDING)
  resolvedBy  String?          @map("resolved_by") @db.Uuid
  resolvedAt  DateTime?        @map("resolved_at") @db.Timestamptz
  createdAt   DateTime         @default(now()) @map("created_at") @db.Timestamptz

  // 신규 필드
  category    String?          @db.VarChar(30) // 세부 사유 카테고리
  evidence    String[]         @default([])    // 증거 이미지 URL
  resolution  String?          @db.Text        // 해결 내용
  actionTaken String?          @map("action_taken") @db.VarChar(30) // WARNING, SUSPEND_24H, SUSPEND_7D, ...
}
```

### 3.2 Inquiry 모델 (신규)
```prisma
model Inquiry {
  id          String       @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId      String       @map("user_id") @db.Uuid
  category    String       @db.VarChar(20) // ACCOUNT, MATCH, SCORE, BUG, etc.
  title       String       @db.VarChar(200)
  content     String       @db.Text
  screenshots String[]     @default([])
  status      String       @default("OPEN") @db.VarChar(20) // OPEN, IN_PROGRESS, RESOLVED, CLOSED
  chatRoomId  String?      @map("chat_room_id") @db.Uuid
  assignedTo  String?      @map("assigned_to") @db.Uuid
  resolvedAt  DateTime?    @map("resolved_at") @db.Timestamptz
  createdAt   DateTime     @default(now()) @map("created_at") @db.Timestamptz
  updatedAt   DateTime     @updatedAt @map("updated_at") @db.Timestamptz

  user     User      @relation(fields: [userId], references: [id])
  chatRoom ChatRoom? @relation(fields: [chatRoomId], references: [id])
  admin    User?     @relation("AssignedAdmin", fields: [assignedTo], references: [id])

  @@index([userId, status])
  @@index([status, createdAt])
  @@map("inquiries")
}
```

### 3.3 UserSanction 모델 (신규)
```prisma
model UserSanction {
  id          String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId      String   @map("user_id") @db.Uuid
  type        String   @db.VarChar(20) // WARNING, SUSPEND, BAN
  reason      String   @db.Text
  reportId    String?  @map("report_id") @db.Uuid
  issuedBy    String?  @map("issued_by") @db.Uuid // null = 자동
  expiresAt   DateTime? @map("expires_at") @db.Timestamptz
  isActive    Boolean  @default(true) @map("is_active")
  createdAt   DateTime @default(now()) @map("created_at") @db.Timestamptz

  user    User    @relation(fields: [userId], references: [id])
  report  Report? @relation(fields: [reportId], references: [id])
  admin   User?   @relation("SanctionIssuer", fields: [issuedBy], references: [id])

  @@index([userId, isActive])
  @@map("user_sanctions")
}
```

## 4. API 엔드포인트

### 유저용
| Method | Path | 설명 |
|--------|------|------|
| POST | `/v1/reports` | 신고 접수 |
| GET | `/v1/reports/mine` | 내 신고 내역 |
| POST | `/v1/inquiries` | 문의 접수 |
| GET | `/v1/inquiries` | 내 문의 내역 |
| GET | `/v1/inquiries/:id` | 문의 상세 |

### 어드민용
| Method | Path | 설명 |
|--------|------|------|
| GET | `/v1/admin/reports` | 신고 목록 (기존) |
| PATCH | `/v1/admin/reports/:id/resolve` | 신고 처리 (기존 + actionTaken 추가) |
| GET | `/v1/admin/inquiries` | 문의 목록 |
| PATCH | `/v1/admin/inquiries/:id/assign` | 문의 담당자 배정 |
| PATCH | `/v1/admin/inquiries/:id/resolve` | 문의 해결 처리 |
| GET | `/v1/admin/sanctions` | 제재 내역 |
| POST | `/v1/admin/sanctions` | 수동 제재 |
| PATCH | `/v1/admin/sanctions/:id/revoke` | 제재 해제 |

## 5. 신고 접수 UI

```
┌──────────────────────────────┐
│ ← 신고하기                    │
├──────────────────────────────┤
│                              │
│ 신고 대상: test_user_042     │
│                              │
│ 신고 사유 (택1)              │
│ ○ 비매너 행동               │
│ ● 노쇼 (매칭 불참)          │
│ ○ 랭크 조작 의심            │
│ ○ 욕설/혐오 발언            │
│ ○ 기타                      │
│                              │
│ 상세 내용 (선택)             │
│ ┌────────────────────────┐   │
│ │ 매칭 확정 후 나타나지    │   │
│ │ 않았습니다...            │   │
│ └────────────────────────┘   │
│                              │
│ 증거 첨부 (선택)             │
│ [📷 + 사진 추가]            │
│                              │
│ ┌────────────────────────┐   │
│ │      신고 접수하기       │   │
│ └────────────────────────┘   │
│                              │
│ ⚠️ 허위 신고 시 제재를 받을  │
│    수 있습니다.              │
└──────────────────────────────┘
```
