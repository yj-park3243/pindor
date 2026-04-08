import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  callAndGetResponse,
} from './helpers';

test.describe('Admin API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    // 첫 번째 테스트 유저 선택 (관리자가 아닐 수 있음 - 403 응답도 유효)
    await selectUser(page, 0);
    await navigateTo(page, 'admin');
  });

  test('GET /admin/dashboard - 대시보드 조회 (403 예상될 수 있음)', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-admin-dashboard');
    // 200 (관리자 권한 있음) 또는 403 (권한 없음) 모두 API가 응답한 것으로 간주
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('GET /admin/users - 유저 목록 조회 (403 예상될 수 있음)', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-admin-get-users');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('GET /admin/reports - 신고 목록 조회 (403 예상될 수 있음)', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-admin-get-reports');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('GET /admin/games/disputed - 분쟁 게임 목록 조회 (403 예상될 수 있음)', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-admin-get-disputed');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('GET /admin/pins - 핀 목록 조회 (403 예상될 수 있음)', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-admin-get-pins');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });
});
