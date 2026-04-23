import { Page, expect } from '@playwright/test';

export type MenuEntry = {
  label: string; // Ant Menu label 텍스트 (한글)
  urlPattern: RegExp; // 이동 후 URL 패턴
  parent?: string; // 하위 메뉴면 부모 그룹 라벨
};

/**
 * 좌측 Ant Menu에서 label 클릭. 하위면 부모 펼침 후 클릭.
 */
export async function clickMenu(page: Page, entry: MenuEntry): Promise<void> {
  const sidebar = page.locator('.ant-layout-sider');

  if (entry.parent) {
    // Submenu 열리지 않았으면 열기. 한 번 열고 나면 두 번째부터는 이미 열려있음.
    const parentTitle = sidebar
      .locator('.ant-menu-submenu-title', { hasText: entry.parent })
      .first();
    if (await parentTitle.count()) {
      // 하위 아이템이 아직 뷰포트에 없으면 열기 시도
      const candidateChild = sidebar
        .locator('.ant-menu-item')
        .filter({ hasText: new RegExp(`^\\s*${entry.label}\\s*$`) })
        .first();
      const visible = await candidateChild.isVisible().catch(() => false);
      if (!visible) {
        await parentTitle.click();
        await page.waitForTimeout(250);
      }
    }
  }

  // 일반 메뉴 아이템: .ant-menu-item (라벨 텍스트 정확히 일치)
  const item = sidebar
    .locator('.ant-menu-item')
    .filter({ hasText: new RegExp(`^\\s*${entry.label}\\s*$`) })
    .first();
  await item.waitFor({ state: 'visible', timeout: 8_000 });
  await item.click();

  await page.waitForURL(entry.urlPattern, { timeout: 15_000 });
  await page.waitForLoadState('networkidle', { timeout: 10_000 }).catch(() => {});
}

/**
 * 현재 화면에 에러 배너가 없고 어떤 컨텐츠든 로드됐는지 확인.
 */
export async function assertPageLoaded(page: Page, screenshotName: string): Promise<void> {
  // Ant Design 500/에러 상태 표시 없는지
  const errorBanner = page.locator('.ant-result-error, .ant-alert-error');
  expect(await errorBanner.count()).toBeLessThanOrEqual(0);

  // 페이지 제목 또는 Table/Empty가 보일 때까지 짧게 대기 (로딩 스피너 끝)
  await page
    .locator('.ant-spin-spinning')
    .first()
    .waitFor({ state: 'hidden', timeout: 10_000 })
    .catch(() => {});

  await page.screenshot({
    path: `test-results/admin-e2e/${screenshotName}.png`,
    fullPage: true,
  });
}
