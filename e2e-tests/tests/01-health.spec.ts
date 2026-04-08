import { test, expect } from '@playwright/test';
import { navigateTo, callAndGetResponse } from './helpers';

test.describe('Health Check', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await navigateTo(page, 'health');
  });

  test('GET /health - 서버 헬스 체크가 정상 응답을 반환해야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-v1-health-check');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });
});
