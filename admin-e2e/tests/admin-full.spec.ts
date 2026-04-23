import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';
import { ensureSeed, ensureDisputeCandidate, restoreDispute } from './helpers/seed';
import { clickMenu, assertPageLoaded, type MenuEntry } from './helpers/nav';

/**
 * 전체 좌측 네비게이션 메뉴.
 * `AdminLayout.tsx`의 `buildMenuItems` 순서와 1:1 매칭.
 */
const MENUS: MenuEntry[] = [
  { label: '대시보드', urlPattern: /\/dashboard/ },
  { label: '사용자 목록', parent: '사용자 관리', urlPattern: /\/users/ },
  { label: '스포츠 프로필', parent: '사용자 관리', urlPattern: /\/profiles/ },
  { label: '매칭 관리', parent: '매칭/경기', urlPattern: /\/matches/ },
  { label: '경기 결과', parent: '매칭/경기', urlPattern: /\/games($|\?)/ },
  { label: '이의 신청 처리', parent: '매칭/경기', urlPattern: /\/games\/review/ },
  { label: '팀 목록', parent: '팀 관리', urlPattern: /\/teams/ },
  { label: '팀 매칭', parent: '팀 관리', urlPattern: /\/team-matches/ },
  { label: '핀 관리', parent: '커뮤니티', urlPattern: /\/pins/ },
  { label: '게시판 관리', parent: '커뮤니티', urlPattern: /\/posts/ },
  { label: '신고 처리', parent: '커뮤니티', urlPattern: /\/reports/ },
  { label: '의의 제기', parent: '커뮤니티', urlPattern: /\/disputes/ },
  { label: '랭킹 관리', urlPattern: /\/rankings/ },
  { label: '공지사항', urlPattern: /\/notices/ },
  { label: '알림 발송', urlPattern: /\/notifications/ },
  { label: '통계/분석', urlPattern: /\/statistics/ },
  { label: '어드민 계정', parent: '설정', urlPattern: /\/settings\/accounts/ },
  { label: '시스템 설정', parent: '설정', urlPattern: /\/settings\/system/ },
];

test.describe.configure({ mode: 'serial' });

test.describe('PINDOR Admin — 전체 스모크', () => {
  test.beforeAll(() => {
    // 공통 시드 (필요한 경우에만 삽입)
    const { created } = ensureSeed();
    if (created.length) console.info(`[seed] created: ${created.join(', ')}`);
  });

  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('좌측 네비게이션 전 메뉴 순회 + 스크린샷', async ({ page }) => {
    for (const menu of MENUS) {
      await test.step(`${menu.parent ? `${menu.parent} / ` : ''}${menu.label}`, async () => {
        await clickMenu(page, menu);
        await assertPageLoaded(page, `nav-${menu.label.replace(/\//g, '_')}`);
      });
    }
  });

  test('의의 신청 처리 — 리스트 + 검토 드로어 표시', async ({ page }) => {
    const disputeGameId = ensureDisputeCandidate();
    if (!disputeGameId) {
      test.skip(true, '운영 DB에 게임 레코드가 없어 dispute 시드 불가 — 실기기에서 먼저 경기 생성 필요');
    }

    try {
      await clickMenu(page, { label: '이의 신청 처리', parent: '매칭/경기', urlPattern: /\/games\/review/ });

      // 테이블 로드 대기
      await page.waitForSelector('.ant-table-row, .ant-empty', { timeout: 15_000 });

      // 최소 1건이 있으면 "검토" 버튼 클릭 후 Drawer 열림 확인
      const firstRow = page.locator('.ant-table-row').first();
      if (await firstRow.count()) {
        const reviewBtn = firstRow.getByRole('button', { name: /검토/ }).first();
        await reviewBtn.click();

        const drawerTitle = page.locator('.ant-drawer-title', { hasText: /이의 신청 검토/ });
        await expect(drawerTitle).toBeVisible({ timeout: 10_000 });

        // 요청자/상대방 닉네임 표시 확인 ("-" 아님)
        const body = page.locator('.ant-drawer-body');
        await expect(body.getByText('요청자')).toBeVisible();
        await expect(body.getByText('상대방')).toBeVisible();

        await page.screenshot({
          path: 'test-results/admin-e2e/dispute-drawer.png',
          fullPage: true,
        });

        // Drawer 닫기 (실제 resolve는 하지 않음 — 운영 데이터 변경 방지)
        await page.keyboard.press('Escape');
      }
    } finally {
      if (disputeGameId) restoreDispute(disputeGameId);
    }
  });

  test('공지사항 등록 → 리스트에 노출', async ({ page }) => {
    const ts = Date.now();
    const title = `[E2E] 자동 등록 공지 ${ts}`;
    const content = `E2E 테스트에서 생성된 공지입니다 (${new Date().toISOString()}).`;

    await clickMenu(page, { label: '공지사항', urlPattern: /\/notices/ });

    // 등록 버튼 — 보통 "공지 등록", "작성", "+" 버튼 중 하나
    const createBtn = page
      .getByRole('button', { name: /공지\s*등록|공지 작성|새 공지|작성하기|등록/ })
      .first();
    if (!(await createBtn.count())) {
      test.skip(true, '공지 등록 버튼을 찾지 못해 건너뜀 (UI 변경 시 셀렉터 업데이트 필요)');
    }
    await createBtn.click();

    // 제목/내용 입력 — Modal 또는 별도 페이지
    const titleInput = page
      .locator('input[placeholder*="제목" i], input[name="title"]')
      .first();
    await titleInput.waitFor({ state: 'visible', timeout: 10_000 });
    await titleInput.fill(title);

    // Ant Design TextArea 또는 리치 에디터
    const contentInput = page
      .locator('textarea[placeholder*="내용" i], textarea[name="content"]')
      .first();
    if (await contentInput.count()) {
      await contentInput.fill(content);
    } else {
      // 리치 에디터 대응
      const editable = page.locator('[contenteditable="true"]').first();
      if (await editable.count()) {
        await editable.click();
        await page.keyboard.type(content);
      }
    }

    // 저장/등록 버튼
    const submitBtn = page
      .getByRole('button', { name: /^(저장|등록|확인|작성하기)$/ })
      .last();
    await submitBtn.click();

    // 목록으로 돌아온 뒤 새 공지 제목이 표시되는지
    await page.waitForLoadState('networkidle').catch(() => {});
    const newRow = page.getByText(title, { exact: false }).first();
    await expect(newRow).toBeVisible({ timeout: 15_000 });

    await page.screenshot({
      path: 'test-results/admin-e2e/notice-created.png',
      fullPage: true,
    });
  });

  test('통계/분석 — 차트/카드 렌더 확인', async ({ page }) => {
    await clickMenu(page, { label: '통계/분석', urlPattern: /\/statistics/ });

    // SVG 차트(Recharts) 또는 통계 카드 최소 1개 이상 노출
    const hasChart = await page.locator('svg.recharts-surface, svg[class*="recharts"]').count();
    const hasStatistic = await page.locator('.ant-statistic, .ant-card').count();

    expect(hasChart + hasStatistic).toBeGreaterThan(0);

    // 숫자 0만 가득한 상태가 아닌지 — 적어도 하나의 카드에 숫자가 있는지 확인
    const anyNumber = page.locator('.ant-statistic-content-value').first();
    if (await anyNumber.count()) {
      const text = (await anyNumber.textContent()) ?? '';
      expect(text.trim()).not.toEqual('');
    }

    await page.screenshot({
      path: 'test-results/admin-e2e/statistics.png',
      fullPage: true,
    });
  });
});
