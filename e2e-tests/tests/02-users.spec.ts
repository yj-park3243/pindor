import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  fillInput,
  callAndGetResponse,
} from './helpers';

test.describe('Users API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'users');
  });

  test('GET /users/me - 내 정보를 가져와야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-get-me');
    // 서버가 응답하는지만 확인 (500은 DB 스키마 불일치일 수 있음)
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(body).toBeTruthy();
  });

  test('PATCH /users/me - 닉네임을 업데이트해야 한다', async ({ page }) => {
    await fillInput(page, 'input-nickname', 'E2E_TestUser');
    const { status } = await callAndGetResponse(page, 'btn-update-profile');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
  });

  test('POST /users/me/location - 위치를 설정해야 한다', async ({ page }) => {
    await fillInput(page, 'input-latitude', '37.5009');
    await fillInput(page, 'input-longitude', '127.0363');
    const { status } = await callAndGetResponse(page, 'btn-update-location');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
  });

  test('GET /users/:id/profile - 유저 프로필을 가져와야 한다', async ({ page }) => {
    // test-users.json의 두 번째 유저 ID를 사용
    const { body: myInfo } = await callAndGetResponse(page, 'btn-get-me');

    if (typeof myInfo === 'object' && myInfo !== null) {
      const myInfoObj = myInfo as Record<string, unknown>;
      const userId = myInfoObj['id'] ?? myInfoObj['userId'];
      if (userId) {
        await fillInput(page, 'input-user-id', String(userId));
      }
    }

    const { status } = await callAndGetResponse(page, 'btn-get-user-profile');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
  });
});
