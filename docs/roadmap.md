# 핀돌 로드맵

| 버전 | 목표 시점 | 핵심 내용 |
|------|----------|----------|
| MVP | 2026-06-24 | 골프 1:1 매칭 핵심 플로우 (가입 → 매칭 → 채팅 → 결과 → 점수) |
| v1.1 | 2026-07 | 애플 로그인, 이의신청 동영상 증빙, 종목 어드민 UI |
| v1.2 | 2026-08 | 전국 랭킹, 시즌 시스템, 당구/배드민턴 종목 추가 |
| v1.3 | 2026-09 | 골프 OCR 스코어카드 분석 (Claude Vision API + Google Vision 폴백), 볼링, 재미 종목 |
| v2.0 | 2026-10 | 팀 매칭 시스템 (축구, 야구, 농구, 리그오브레전드) |

## v1.1 상세

- 애플 소셜 로그인 (`POST /auth/apple`)
- 이의신청 동영상 증빙 업로드 지원
- 종목 추가/수정/비활성화 어드민 UI

## v1.3 상세

- OCR 스코어카드 자동 분석 (골프 우선)
  - Claude Vision API 1차 분석 + Google Vision API 폴백
  - `ocr_jobs` 테이블로 작업 추적
  - `ocr-analysis.worker.ts` 비동기 처리
- 볼링 (스코어 사진 OCR), 가위바위보/팔씨름/동전던지기 재미 종목

## v2.0 상세 — 팀 매칭

**팀 종목**

| 종목 | 팀 인원 |
|------|---------|
| 축구 | 5~11명 (풋살/정규) |
| 야구 | 9~15명 |
| 농구 | 3~5명 (3:3 또는 5:5) |
| 리그오브레전드 | 5명 |

**핵심 기능**

- 팀 생성/초대/가입, 역할 관리 (CAPTAIN / VICE_CAPTAIN / MEMBER)
- 팀 매칭 요청 → PostGIS 반경 내 상대 팀 탐색 → 수락 시 단체 채팅방 생성
- 팀 ELO 점수 반영 (개인 매칭과 동일 로직)
- 팀 내부 게시판 (공지/일정/자유)

**탭 구조 변경**

현재: [홈] [매칭] [채팅] [랭킹] [내 프로필]

v2.0: [홈] [매칭] [팀] [채팅] [랭킹] [내 프로필]

**추가 API 엔드포인트 (v2.0)**

```
POST   /teams, GET /teams/:id, PATCH /teams/:id, DELETE /teams/:id
GET    /teams/nearby, GET /teams/search
POST   /teams/:id/members/invite, POST /teams/:id/members/join
PATCH  /teams/:id/members/:userId/role, DELETE /teams/:id/members/:userId
POST   /team-matches/requests, GET /team-matches, PATCH /team-matches/:id/confirm
PATCH  /team-matches/:id/result, POST /team-matches/:id/dispute
GET/POST /team-chat-rooms/:id/messages
GET/POST/PATCH/DELETE /teams/:id/posts, POST /teams/:id/posts/:postId/comments
```

**추가 DB 테이블 (v2.0)**

`teams`, `team_members`, `team_match_requests`, `team_matches`, `team_chat_rooms`, `team_chat_room_members`, `team_posts`
