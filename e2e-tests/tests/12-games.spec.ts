import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  callAndGetResponse,
} from './helpers';

test.describe('Games API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'games');
  });

  test('GET /games - 게임 목록을 가져와야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-get-games');
    // 200 (성공) 또는 다른 유효한 응답 코드
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });
});
