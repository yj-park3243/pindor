import { Page, expect } from '@playwright/test';

const ADMIN_USERNAME = process.env.ADMIN_USERNAME ?? 'dydwn3243';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? '';

/**
 * admin.pins.kr에 로그인.
 * ADMIN_USERNAME / ADMIN_PASSWORD 환경변수 필수.
 */
export async function loginAsAdmin(page: Page): Promise<void> {
  if (!ADMIN_PASSWORD) {
    throw new Error(
      'ADMIN_PASSWORD 환경변수가 설정되지 않았습니다. ' +
        '실행 예: ADMIN_PASSWORD=xxx npx playwright test',
    );
  }

  await page.goto('/login');
  await page.waitForLoadState('networkidle');

  // Ant Design Input: input[name=username], input[type=password]
  const usernameInput = page.locator('input[placeholder*="아이디" i], input[id*="username" i], input[name="username"]').first();
  const passwordInput = page.locator('input[type="password"]').first();

  await usernameInput.fill(ADMIN_USERNAME);
  await passwordInput.fill(ADMIN_PASSWORD);

  const loginBtn = page.getByRole('button', { name: /로그인/ }).first();
  await loginBtn.click();

  await page.waitForURL(/\/dashboard/, { timeout: 20_000 });
  await expect(page).toHaveURL(/\/dashboard/);
}
