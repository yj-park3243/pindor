# 핀돌 개발 TODO

> 최종 업데이트: 2026-04-09
> 상태: `[ ]` 미착수 / `[~]` 진행중 / `[x]` 완료

---

## 1. 매칭 수락/거절 버그 수정 (CRITICAL)

- [ ] **main_tab_screen PENDING_ACCEPT 필터 수정** — 수락한 경우 탭 이동 잠금 해제 (acceptances에서 내 수락 여부 체크)
- [ ] **서버 listMatches에 acceptances 포함** — PENDING_ACCEPT 매칭에 myAcceptance 필드 반환
- [ ] **matchListProvider SWR 강제 갱신** — invalidate() 시 TTL 리셋, 항상 API 호출
- [ ] **chatRoomId null 체크** — 채팅 이동 전 chatRoomId?.isNotEmpty == true 검사

---

## 2. 타이머 / 폴링 안정화

- [ ] **타이머 단일 소스로 통합** — match_accept_screen.dart initState에서만 시작, build에서 중복 제거
- [ ] **폴링 실패 카운터** — 3회 연속 실패 시 폴링 중지, 에러 메시지 표시
- [ ] **ref.listen 중복 네비게이션 방지** — CHAT 상태 전환 시 한 번만 이동하도록 플래그 처리
- [ ] **expiresAt 서버 필수화** — listMatches, getMatch, getActiveMatch 모두에서 expiresAt 포함

---

## 3. 캐시 / 상태 정합성

- [ ] **hasMatchesCache TTL 체크** — count > 0 && !expired 조건으로 변경
- [ ] **경기 확정/취소 후 목록 동기화** — ref.invalidate(matchListProvider(null)) 추가
- [ ] **Drift 캐시 정합성** — 수락/거절 후 로컬 DB 해당 매칭 갱신, 앱 시작 시 서버에 없는 PENDING_ACCEPT 정리

---

## 4. 서버 응답 일관성

- [ ] **acceptMatch 응답에 매칭 상세 포함** — { status, message, match: { id, chatRoomId, ... } } 로 변경 (MATCHED일 때)
- [ ] **getMatchStatus 응답 형식 통일** — acceptMatch 응답과 형식 맞추기

---

## 5. 티어 / 승급 프로그레스바

- [ ] 서버: GET /users/me 응답에 pointsToNext, progress, subTier 필드 추가
- [ ] 서버: elo.ts에 getTierInfo(score) 함수 구현 (현재 티어 + 다음 티어 경계 + 남은 점수)
- [ ] 앱: 홈 화면 내 핀 상태 카드에 프로그레스바 표시
- [ ] 앱: 스포츠 프로필 카드에 프로그레스바 추가
- [ ] 앱: 매칭 결과 화면에 점수 변동 + 승급/강등 애니메이션

> 설계 문서: [design-tier-system.md](./design-tier-system.md)

---

## 6. 매칭 알고리즘

- [ ] 매칭 큐 워커 (BullMQ) — 10초마다 핀별 매칭 풀 스캔
- [ ] 같은 핀 + 같은 종목에서 MatchScore 최고 쌍 자동 매칭
- [ ] 대기 시간에 따른 MMR 범위 점진적 확대 (0~2분: +-100, 5분: +-200, 10분+: +-500)
- [ ] 매칭 수락/거절 타임아웃 처리 (10분, BullMQ Job)
- [ ] 수락/거절/타임아웃 시 점수 처리 (거절: -15, 수락+상대미응답: +5)

---

## 7. 노쇼 패널티

- [ ] 서버: 매칭 확정 후 당일 취소 또는 무응답 → 노쇼 판정
- [ ] 서버: 포기자 -30점, 상대방 +15점
- [ ] 서버: SportsProfile에 noShowCount, matchBanUntil 필드 추가
- [ ] 서버: 노쇼 누적 시 매칭 제한 (3회: 24시간, 5회: 3일, 10회: 7일)
- [ ] 앱: 노쇼 제재 시 매칭 신청 버튼 비활성화 + "N시간 후 매칭 가능" 표시

---

## 8. 활동량 보너스

- [ ] 서버: 주간 게임 수 카운트 (3게임+: K계수 +2, 5게임+: K계수 +4)
- [ ] 서버: 연승 스트릭 보너스 (2연승: +3, 3연승: +5, 5연승+: +8)
- [ ] 서버: 일간 첫 게임 승리 보너스 (+5)
- [ ] 서버: 주간 목표 달성 보상 (3게임: +10, 5게임: +20)
- [ ] 앱: 홈 화면에 주간 목표 프로그레스 표시
- [ ] 앱: 매칭 결과 화면에 보너스 점수 표시

---

## 9. 연습 게임 (캐주얼 모드)

- [ ] 서버: RequestType에 CASUAL 추가
- [ ] 서버: SportsProfile에 casualScore, casualWin, casualLoss 필드 추가
- [ ] 서버: 연습 매칭 요청 시 별도 MMR로 매칭, 랭크 점수 변동 없음
- [ ] 앱: 매칭 요청 화면에 "랭크 / 연습" 토글 추가
- [ ] 앱: 매칭 카드에 "연습" 뱃지 표시

---

## 10. 게시판 입장 조건

- [ ] 서버: canAccessPinBoard(userId, pinId) 미들웨어 — 해당 핀 완료 매칭 1회 이상 시 작성/댓글/좋아요 허용
- [ ] 서버: 게시글/댓글/좋아요 라우트에 미들웨어 적용
- [ ] 앱: 권한 없을 때 "이 핀에서 1회 이상 매칭에 참가해야 합니다" 다이얼로그

---

## 11. 신고 / 문의 시스템

- [ ] 서버: POST /reports 신고 접수 API (유저/게시글/채팅/매칭)
- [ ] 서버: POST /inquiries 문의 접수 API
- [ ] 서버: Inquiry, UserSanction 모델 추가
- [ ] 서버: 자동 제재 규칙 (7일 내 3건+ 신고 → 24시간 정지)
- [ ] 앱: 마이페이지 > 고객센터 메뉴
- [ ] 앱: 신고 접수 바텀시트 (사유 + 상세 + 사진 첨부)
- [ ] 앱: 문의 접수 화면
- [ ] 어드민: 신고 목록/처리 UI, 문의 목록/응답 UI

> 설계 문서: [design-report-system.md](./design-report-system.md)

---

## 우선순위

| 순위 | 항목 | 이유 |
|------|------|------|
| 1 | 매칭 버그 수정 (#1~4) | 매칭이 동작해야 서비스가 됨 |
| 2 | 매칭 알고리즘 (#6) | 핵심 기능 |
| 3 | 티어 프로그레스바 (#5) | 유저 동기부여, 리텐션 |
| 4 | 노쇼 패널티 (#7) | 매칭 품질 보장 |
| 5 | 활동량 보너스 (#8) | 리텐션 + 매칭 풀 확대 |
| 6 | 연습 게임 (#9) | 신규 유저 진입 장벽 낮춤 |
| 7 | 게시판 입장 조건 (#10) | 커뮤니티 품질 |
| 8 | 신고/문의 (#11) | 서비스 안정성 |
