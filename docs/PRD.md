# 핀돌 (PINDOR) — 제품 요구사항 문서

> 작성일: 2026-04-01 | 초기 종목: 골프 (추후 당구, 테니스, 탁구 등 확장)
> 시스템 구성: 서버(Node.js/Fastify) + 어드민(React) + 모바일 앱(Flutter)

로드맵: [roadmap.md](roadmap.md)

---

## 목차

1. [제품 개요](#1-제품-개요)
2. [핵심 기능](#2-핵심-기능)
3. [화면 목록](#3-화면-목록)
4. [기술 요구사항](#4-기술-요구사항)

---

# 1. 제품 개요

**비전**: 위치와 실력 기반으로 최적의 스포츠 매칭을 제공하는 플랫폼

| 구분 | 내용 |
|------|------|
| 비즈니스 목표 | 론칭 6개월 내 MAU 10,000명, 월 매칭 성사 5,000건 |
| 사용자 목표 | 반경 내 비슷한 실력의 상대를 30분 이내에 찾는다 |
| 품질 목표 | 매칭 수락률 60% 이상, 경기 완료율 70% 이상 |

**제약 조건**

- G핸디: 골프존 공식 데이터를 자체 입력 (자동 연동 불가, 추후 API 연동 검토)
- 초기 서비스 지역: 수도권 우선 론칭 후 전국 확대
- 결제 시스템: MVP 제외, 추후 프리미엄 구독 모델 검토
- 경기 결과 인증: 스코어카드 사진 기반 (OCR 자동화는 v1.3)

---

# 2. 핵심 기능

## 2.1 회원 및 프로필 관리

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-001-1 | 소셜 로그인 (카카오, 애플) | Must |
| FR-001-2 | 이메일/비밀번호 로그인 | Should |
| FR-001-3 | 스포츠 프로필 생성 (종목별 1개, G핸디 입력) | Must |
| FR-001-4 | 프로필 사진 업로드 (최대 5MB, JPG/PNG) | Must |
| FR-001-5 | 활동 지역 설정 (지도 핀 선택 또는 현재 위치) | Must |
| FR-001-6 | 매칭 반경 설정 (1km~50km, 기본 10km) | Must |
| FR-001-7 | 스포츠 종목 어드민 관리 | Should |

**스포츠 종목 목록**

| 종목 | slug | 결과 방식 |
|------|------|----------|
| 골프 | golf | OCR (타수 비교, 핸디캡 적용) |
| 탁구/테니스/배드민턴 | table-tennis/tennis/badminton | SET (3세트 2선승) |
| 볼링 | bowling | OCR |
| 당구 | billiards | SCORE (목표 점수 선취) |
| 가위바위보/팔씨름/동전던지기 | — | SELF_REPORT (재미 종목) |

---

## 2.2 매칭 시스템

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-002-1 | 자동 매칭 요청 등록 (종목/날짜/시간대/위치) | Must |
| FR-002-2 | "오늘 대결" 즉시 매칭 (현재 위치 기반, 2시간 이내) | Must |
| FR-002-3 | 매칭 조건 설정 (실력 범위, 거리, 날짜, 시간대) | Must |
| FR-002-4 | 매칭 수락/거절 (푸시 알림, 30분 미응답 시 자동 거절) | Must |
| FR-002-5 | 매칭 취소 (경기 24시간 전까지, 반복 취소 시 패널티) | Must |
| FR-002-6 | 매칭 히스토리 조회 (최근 50건) | Should |
| FR-002-7 | 미완료 경기 있을 시 신규 매칭 차단 | Must |

**매칭 차단 로직**: 이전 경기 `result_status`가 `VERIFIED` 또는 `VOIDED`가 아닌 경우 신규 매칭 요청 시 `MATCH_BLOCKED_PENDING_RESULT` (HTTP 409) 반환. 앱은 `GET /matches/pending-result-check` 호출 후 미완료 경기 있으면 상단 배너 표시 + 요청 버튼 비활성화.

---

## 2.3 채팅

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-003-1 | 1:1 채팅방 자동 생성 (매칭 성사 즉시) | Must |
| FR-003-2 | 텍스트 메시지 (실시간, 최대 500자) | Must |
| FR-003-3 | 이미지 메시지 (최대 10MB) | Should |
| FR-003-4 | 골프장/시간 제안 카드 | Could |
| FR-003-5 | 채팅 알림 (푸시 + 인앱 배지) | Must |
| FR-003-6 | 채팅방 신고 | Must |

---

## 2.4 경기 결과 처리

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-004-1 | 경기 결과 사진 업로드 (최대 3장) | Must |
| FR-004-2 | 결과 상호 인증 (양측 동의 시 점수 반영) | Must |
| FR-004-3 | 결과 이의 신청 (인증 후 48시간 이내, 사진 증빙) | Must |
| FR-004-4 | 점수 자동 계산 및 반영 (인증 완료 후 즉시) | Must |
| FR-004-5 | 결과 미입력 패널티 (72시간 내 미입력 시 경고) | Should |
| FR-004-6 | 양측 승리 주장 시 자동 무승부 (DRAW_AUTO) | Must |
| FR-004-7 | OCR 스코어카드 분석 (v1.3) | Should |

**양측 승리 주장 처리 흐름**

1. 양측 서로 자신이 이겼다고 제출 → `result_status = DRAW_AUTO`
2. 양측에 "자동 무승부 처리" 푸시 알림 발송
3. 72시간 이내 이의신청 없으면 → `VERIFIED` 확정 (무승부 ELO 반영)
4. 이의신청 접수 → `DISPUTED` → 어드민 검토 큐 등록
5. 어드민 결과: 증거 불충분 → 무승부 확정 / 한쪽 승리 납득 → 거짓 주장 측 `false_claim_count` +1 (3회 시 계정 정지)

---

## 2.5 랭킹 및 티어

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-005-1 | 지역 핀 단위 랭킹 (실시간, 상위 100명) | Must |
| FR-005-2 | 전국 랭킹 (주 1회 갱신, v1.2) | Should |
| FR-005-3 | 티어 배지 표시 (브론즈/실버/골드/플래티넘) | Must |
| FR-005-4 | 랭킹 히스토리 (월별 추이) | Could |

**ELO 점수 시스템**

기본 ELO 공식 사용 (`E_A = 1 / (1 + 10^((R_B - R_A) / 400))`).

| 조건 | K 계수 | 티어 | 점수 범위 |
|------|--------|------|----------|
| 첫 10게임 | 40 | BRONZE | 800 ~ 1,099 |
| 11~30게임 | 30 | SILVER | 1,100 ~ 1,349 |
| 31게임 이상 | 20 | GOLD | 1,350 ~ 1,649 |
| 플래티넘 티어 | 16 | PLATINUM | 1,650 이상 |

**골프 초기 점수 (G핸디 → ELO)**

| G핸디 | 초기 ELO | 티어 |
|-------|---------|------|
| 0~8 | 1,650~1,800 | PLATINUM |
| 9~17 | 1,300~1,649 | GOLD |
| 18~30 | 1,100~1,299 | SILVER |
| 31~54 | 800~1,099 | BRONZE |

티어 강등 보호: 경계에서 -50점 버퍼, 최대 3게임 유예 후 강등.

**부정행위 패널티**

| 위반 | 1회 | 2회 | 3회 이상 |
|------|-----|-----|---------|
| 결과 미입력 | 경고 | 3일 매칭 제한 | 7일 매칭 제한 |
| 허위 결과 입력 | 경고 + 점수 취소 | 14일 정지 | 영구 정지 |
| 반복 취소 (월 3회 초과) | 경고 | 7일 매칭 제한 | 30일 제한 |
| 동일 기기 다중 계정 | 계정 정지 검토 | 영구 정지 | — |

---

## 2.6 지역 핀 게시판

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-006-1 | 핀별 게시판 (글쓰기/수정/삭제, 최대 2000자) | Must |
| FR-006-2 | 댓글/대댓글 (2depth) | Must |
| FR-006-3 | 게시글 좋아요 (1인 1회) | Should |
| FR-006-4 | 게시글 신고 | Must |
| FR-006-5 | 사진 첨부 (게시글당 최대 5장) | Should |

---

## 2.7 지역 핀 정책

핀은 행정구역 기반 계층 구조 (광역 → 구/시 → 동).

**핀 활성화 최소 인원**

| 레벨 | 최소 인원 |
|------|---------|
| DONG (동) | 10명 |
| GU (구) | 30명 |
| CITY (시) | 50명 |
| PROVINCE (광역) | 100명 |

기준 미달 시 상위 레벨 핀으로 자동 병합.

---

## 2.8 비기능 요구사항

| ID | 항목 | 요구사항 |
|----|------|----------|
| NFR-001 | 응답 시간 | API p95 < 300ms |
| NFR-002 | 가용성 | 월 가동률 99.5% 이상 |
| NFR-003 | 동시 접속 | 최대 5,000명 처리 |
| NFR-004 | 위치 검색 | 반경 검색 100ms 이내 |
| NFR-005 | 채팅 지연 | 메시지 전달 1초 이내 |
| NFR-006 | 보안 | HTTPS 전용, JWT 7일, Refresh 30일 |
| NFR-007 | 개인정보 | 위치 정보 최소 수집, 동의 기반 |
| NFR-008 | 확장성 | 종목 추가 시 어드민에서만 처리 (코드 변경 없음) |

---

# 3. 화면 목록

## 온보딩 플로우

| ID | 화면명 |
|----|--------|
| SCREEN-001 | 스플래시 |
| SCREEN-002 | 온보딩 소개 (3장 슬라이드) |
| SCREEN-003 | 로그인 선택 (카카오/애플) |
| SCREEN-004 | 닉네임 설정 |
| SCREEN-005 | 스포츠 종목 선택 |
| SCREEN-006 | 스포츠 프로필 설정 (G핸디 입력) |
| SCREEN-007 | 활동 지역 설정 (지도 핀 선택) |
| SCREEN-008 | 매칭 반경 설정 |
| SCREEN-009 | 온보딩 완료 |

## 메인 탭 구조

| 탭 ID | 탭명 |
|-------|------|
| TAB-001 | 홈 |
| TAB-002 | 매칭 |
| TAB-003 | 채팅 |
| TAB-004 | 랭킹/지도 |
| TAB-005 | 내 프로필 |

## 홈 탭

| ID | 화면명 | 구성 요소 |
|----|--------|----------|
| SCREEN-010 | 홈 피드 | 현재 대결 요청 현황 카드, 주변 활성 매칭 요청 목록, 내 점수/티어 요약, 핀 게시판 최신글 미리보기 |
| SCREEN-011 | "오늘 대결" 요청 생성 | 현재 위치 확인, 가능 시간대 선택, 요청 완료 확인 |

## 매칭 탭

| ID | 화면명 | 구성 요소 |
|----|--------|----------|
| SCREEN-020 | 매칭 목록 | 진행중/완료/취소 탭 |
| SCREEN-021 | 매칭 요청 생성 | 종목, 날짜/시간, 위치, 상대 실력 범위 / 미완료 경기 시 배너 + 버튼 비활성화 |
| SCREEN-022 | 매칭 요청 목록 | 내가 보낸/받은 요청 |
| SCREEN-023 | 매칭 상세 | — |
| SCREEN-024 | 상대 프로필 미리보기 | 바텀시트 |
| SCREEN-025 | 경기 확정 | 날짜/장소 확정 |
| SCREEN-026 | 경기 결과 입력 | 내/상대 점수 입력, 결과 사진 업로드 |
| SCREEN-027 | 결과 인증 대기 | 상대 입력 대기 |
| SCREEN-028 | 결과 확인 및 인증 | 인증 동의/거절 |
| SCREEN-029 | 점수 변동 결과 | 애니메이션, 랭킹 변동 표시 |
| SCREEN-030 | 이의 신청 | 사유 입력 + 사진/동영상 증빙 업로드 |

## 채팅 탭

| ID | 화면명 | 구성 요소 |
|----|--------|----------|
| SCREEN-031 | 채팅방 목록 | — |
| SCREEN-032 | 채팅방 (1:1) | 메시지 목록, 이미지 전송, 일정 제안 카드, 경기 확정 버튼, 신고 기능 |
| SCREEN-033 | 이미지 뷰어 | 채팅 내 이미지 전체화면 |

## 랭킹/지도 탭

| ID | 화면명 | 구성 요소 |
|----|--------|----------|
| SCREEN-040 | 지도 뷰 | 핀 클러스터, 활성 매칭 요청 마커, 내 위치 마커 |
| SCREEN-041 | 핀 상세 바텀시트 | 핀 이름/설명, TOP 10 랭킹, 핀 게시판 바로가기 |
| SCREEN-042 | 핀 랭킹 전체 목록 | — |
| SCREEN-043 | 전국 랭킹 (v1.2) | — |
| SCREEN-044 | 내 랭킹 상세 | 점수 히스토리 차트 |

## 프로필 탭

| ID | 화면명 | 구성 요소 |
|----|--------|----------|
| SCREEN-050 | 내 프로필 메인 | 티어 배지 + 점수, 경기 전적(승/패/무), 최근 경기 목록, 핀 랭킹 순위 |
| SCREEN-051 | 프로필 수정 | — |
| SCREEN-052 | 스포츠 프로필 관리 | — |
| SCREEN-053 | 활동 지역 변경 | — |
| SCREEN-054 | 알림 목록 | — |
| SCREEN-055 | 설정 | 알림 설정, 개인정보 처리방침, 서비스 이용약관, 로그아웃/탈퇴 |
| SCREEN-056 | 매칭 이력 | — |
| SCREEN-057 | 신고/문의 | — |

---

# 4. 기술 요구사항

## 4.1 기술 스택

| 계층 | 기술 |
|------|------|
| 서버 런타임 | Node.js 22 LTS + TypeScript 5.x |
| 서버 프레임워크 | Fastify 4.x |
| ORM | Prisma 5.x |
| DB | PostgreSQL 17 + PostGIS |
| Cache / 메시지큐 | Redis 7 + BullMQ |
| WebSocket | Socket.io 4.x |
| 파일 저장 | AWS S3 + CloudFront |
| 인증 | JWT (jose), JWT 7일 / Refresh 30일 |
| 푸시 알림 | Firebase FCM + APNs |
| 모바일 앱 | Flutter 3.x |
| 어드민 | React 18 + Ant Design Pro + TanStack Query |
| 인프라 | AWS EC2/RDS/S3 |

## 4.2 API 기본 규칙

| 항목 | 규칙 |
|------|------|
| Base URL | `https://api.pindor.kr/v1` |
| 인증 | Bearer JWT (Authorization 헤더) |
| 응답 형식 | JSON, UTF-8 |
| 날짜 형식 | ISO 8601 |
| 페이지네이션 | cursor 기반 (`cursor`, `limit`) |
| 에러 형식 | `{ code, message, details }` |

## 4.3 주요 API 엔드포인트

```
# 인증
POST /auth/kakao, /auth/apple, /auth/refresh, /auth/logout

# 사용자/프로필
GET/PATCH /users/me
POST /users/me/location
GET /users/:id/profile
POST/PATCH /sports-profiles, /sports-profiles/:id

# 매칭
POST/GET /matches/requests
DELETE /matches/requests/:id
GET /matches/pending-result-check
POST /matches/instant
GET /matches, /matches/:id
PATCH /matches/:id/confirm, /matches/:id/cancel

# 경기 결과
POST /games/:gameId/proofs, /games/:gameId/result, /games/:gameId/confirm
POST /games/:gameId/dispute
GET /games/:gameId/ocr-result

# 채팅
GET /chat-rooms
GET/POST /chat-rooms/:id/messages

# 랭킹/핀
GET /rankings/pins/:pinId, /rankings/nearby, /rankings/national
GET /pins/nearby, /pins/:id
GET/POST /pins/:pinId/posts
PATCH/DELETE /pins/:pinId/posts/:postId
POST /pins/:pinId/posts/:postId/comments, /pins/:pinId/posts/:postId/like

# 알림/설정
GET /notifications
PATCH /notifications/read-all, /notifications/:id/read, /notifications/settings
POST/DELETE /devices/push-token
POST /uploads/presigned-url

# 종목 (공개)
GET /sports
```

## 4.4 실시간 알림 시스템

Socket.io + Redis Pub/Sub + FCM/APNs 조합 사용.

| type | 트리거 | Socket | 푸시 |
|------|--------|:------:|:----:|
| `MATCH_FOUND` | 매칭 성사 | O | O |
| `MATCH_REQUEST_RECEIVED` | 매칭 요청 수신 | O | O |
| `MATCH_ACCEPTED` / `MATCH_REJECTED` | 수락/거절 | O | O |
| `MATCH_EXPIRED` | 30분 타임아웃 | O | O |
| `CHAT_MESSAGE` | 새 채팅 메시지 | O | O (백그라운드만) |
| `GAME_RESULT_SUBMITTED` / `CONFIRMED` | 결과 제출/인증 | O | O |
| `SCORE_UPDATED` / `TIER_CHANGED` | 점수/티어 변동 | O | O |
| `RESULT_DEADLINE` | 결과 기한 임박 (3시간 전) | — | O |
| `RESULT_INPUT_REQUIRED` | 결과 미입력 24시간 경과 | — | O |
| `GAME_DRAW_AUTO` | 자동 무승부 처리 | O | O |
| `COMMUNITY_REPLY` | 게시글/댓글 답글 | O | O |

## 4.5 DB 핵심 테이블

| 테이블 | 설명 |
|--------|------|
| users, social_accounts | 사용자 기본 정보, 소셜 로그인 연동 |
| user_locations | 활동 위치 + 매칭 반경 (PostGIS GEOGRAPHY) |
| sports, sports_profiles | 종목 마스터, 종목별 사용자 프로필 + ELO |
| score_histories | 점수 변동 이력 |
| pins, user_pins | 지역 핀, 사용자-핀 연관 |
| match_requests, matches, games | 매칭 요청, 매칭, 경기 |
| game_result_submissions, game_result_proofs | 개별 결과 제출, 증빙 사진 |
| result_confirmations, disputes, ocr_jobs | 상호 인증, 이의 신청, OCR 작업 추적 |
| chat_rooms, messages | 채팅방, 메시지 |
| ranking_entries | 핀별 랭킹 스냅샷 |
| posts, post_images, comments | 핀 게시판 게시글, 이미지, 댓글 |
| notifications, notification_settings, device_tokens | 알림, 설정, 디바이스 토큰 |
| reports | 신고 내역 |

인프라 최적화: `messages`, `score_histories` 월/연별 파티셔닝 | 위치 컬럼 PostGIS GIST 인덱스 | 랭킹 Redis Sorted Set + PostgreSQL Materialized View

## 4.6 어드민 기능

기술 스택: React 18 + Vite + TanStack Query + Ant Design Pro | 인증: 관리자 계정 MFA 필수 | 권한: SUPER_ADMIN / ADMIN / MODERATOR

주요 메뉴: 대시보드, 사용자 관리, 종목/스포츠 프로필 관리, 매칭/경기 결과 관리, 핀 관리, 게시판 관리, 랭킹 관리, 알림 발송, 통계/분석, 설정 (K계수·티어 기준·어드민 계정)

## 4.7 서버 프로젝트 구조

```
server/src/
├── modules/        # auth, users, matching, games, chat, rankings, pins, sports, notifications, teams(v2.0)
├── shared/         # middleware, utils(elo.ts, geo.ts), errors
└── workers/        # match-expiry, result-deadline, ranking-refresh, auto-verify-draw, ocr-analysis(v1.3)
```
