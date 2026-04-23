# PINDOR Admin E2E (Playwright)

어드민(admin.pins.kr) UI 전체를 자동으로 순회하며 검증하는 E2E 테스트.

## 무엇을 확인하는가

1. **로그인** — `/login` → `/dashboard` 진입
2. **좌측 네비게이션 18개 메뉴 순회** — 각 화면이 에러 없이 로드되는지 + 스크린샷
3. **의의 신청 처리 화면** — 리스트 → 검토 Drawer → 요청자/상대방 닉네임 표시 확인
4. **공지사항 등록** — 제목·내용 입력 → 등록 → 목록 반영 확인
5. **통계/분석** — 차트/Statistic 카드 렌더 및 값 확인

데이터가 비어있으면 **SSH + psql**로 최소 시드를 자동 삽입한다. 테스트 종료 후 dispute 플래그는 원복.

## 전제 조건

- macOS + Node 18+
- SSH 키: `~/WebProject2/match/spots-key.pem` (EC2 접근용)
- 운영 서버 admin.pins.kr 접근 가능 (VPN 불필요)
- 어드민 계정: `dydwn3243` / 비밀번호는 실행 시점에 env로 주입

## 실행

```bash
cd /Users/yongju/WebProject2/match/admin-e2e
ADMIN_PASSWORD='본인_패스워드' bash run.sh
```

헤드리스 해제하고 관찰하고 싶으면:

```bash
ADMIN_PASSWORD='xxx' npx playwright test --headed
```

특정 테스트만:

```bash
ADMIN_PASSWORD='xxx' npx playwright test -g '공지사항 등록'
```

HTML 리포트:

```bash
npx playwright show-report
```

## 환경 변수

| 이름 | 기본값 | 설명 |
|------|--------|------|
| `ADMIN_BASE_URL` | `https://admin.pins.kr` | 테스트 대상 URL |
| `ADMIN_USERNAME` | `dydwn3243` | 관리자 계정 |
| `ADMIN_PASSWORD` | (필수) | 관리자 비밀번호 |
| `ADMIN_DB_SSH_KEY` | `~/WebProject2/match/spots-key.pem` | EC2 SSH 키 경로 |
| `ADMIN_DB_SSH_HOST` | `ec2-user@43.203.165.114` | EC2 호스트 |

## 산출물

- `test-results/admin-e2e/nav-*.png` — 각 메뉴 스크린샷
- `test-results/admin-e2e/dispute-drawer.png` — 의의 신청 검토 Drawer
- `test-results/admin-e2e/notice-created.png` — 공지 등록 후 목록
- `test-results/admin-e2e/statistics.png` — 통계 화면
- `playwright-report/index.html` — 전체 리포트

## 주의

- **운영 DB에 직접 접근**한다. 시드 공지는 `[E2E]` 접두사로 마킹되므로 필요 시 수동 정리:
  ```sql
  DELETE FROM notices WHERE title LIKE '[E2E]%';
  ```
- 공지 등록 테스트는 실제로 운영 DB에 row를 남긴다. 앱 유저에게 노출되므로 주기적으로 정리 권장.
- 의의 신청 테스트는 resolve 액션까지는 **하지 않는다** (점수 변동 방지). Drawer 열림/닉네임 표시까지만 확인.
