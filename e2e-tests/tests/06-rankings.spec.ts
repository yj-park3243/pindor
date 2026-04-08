import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  callAndGetResponse,
} from './helpers';

test.describe('Rankings API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'rankings');
  });

  test('GET /rankings/me - 내 랭킹을 가져와야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-get-my-ranking');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('GET /rankings/national - 전국 랭킹을 가져와야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-get-national-rankings');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });
});
