import { test, expect } from '@playwright/test';

/**
 * 실제 로그인 없이 admin.pins.kr이 접근 가능하고 정적 자원이 로드되는지
 * 빠르게 확인하는 스모크 테스트. (ADMIN_PASSWORD가 없을 때 디버깅용)
 */
test('admin 접근 + 로그인 페이지 렌더', async ({ page }) => {
  const resp = await page.goto('/', { waitUntil: 'domcontentloaded' });
  expect(resp?.ok()).toBeTruthy();

  // 로그인으로 리다이렉트됐거나 로그인 페이지가 떴을 것
  await page.waitForURL(/\/login|\/dashboard/, { timeout: 15_000 });

  // 최소한 react 루트 + h1/input 있는지
  const body = await page.locator('body').innerText().catch(() => '');
  expect(body.length).toBeGreaterThan(0);

  await page.screenshot({ path: 'test-results/smoke.png', fullPage: true });
});
