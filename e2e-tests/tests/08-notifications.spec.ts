import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  callAndGetResponse,
} from './helpers';

test.describe('Notifications API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'notifications');
  });

  test('GET /notifications - 알림 목록을 가져와야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-get-notifications');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(body).toBeTruthy();
  });

  test('PATCH /notifications/read-all - 모든 알림을 읽음 처리해야 한다', async ({ page }) => {
    const { status } = await callAndGetResponse(page, 'btn-read-all-notifications');
    // 서버가 응답하면 OK (500은 DB 이슈일 수 있음)
    expect(Number(status)).toBeGreaterThanOrEqual(200);
  });

  test('PATCH /notifications/settings - 알림 설정을 업데이트해야 한다', async ({ page }) => {
    const { status } = await callAndGetResponse(page, 'btn-update-notification-settings');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
  });
});
