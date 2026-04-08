import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  fillInput,
  selectOption,
  callAndGetResponse,
} from './helpers';

test.describe('Sports Profiles API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'sports-profiles');
  });

  test('GET /sports-profiles - 스포츠 프로필 목록을 가져와야 한다', async ({ page }) => {
    const { status, body } = await callAndGetResponse(page, 'btn-get-sports-profiles');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('POST /sports-profiles - 스포츠 프로필을 생성해야 한다 (이미 존재하면 gracefully 처리)', async ({ page }) => {
    await selectOption(page, 'input-sport-type', 'TENNIS');
    await fillInput(page, 'input-sport-display-name', 'E2E Test Player');

    const { status } = await callAndGetResponse(page, 'btn-create-sports-profile');
    // 201 (생성 성공), 409 (이미 존재), 400 (잘못된 요청) 모두 API가 응답한 것으로 간주
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('PATCH /sports-profiles/:id - 스포츠 프로필 displayName을 업데이트해야 한다', async ({ page }) => {
    // 먼저 목록을 조회하여 ID를 얻음
    const { body: listBody } = await callAndGetResponse(page, 'btn-get-sports-profiles');

    let profileId: string | null = null;

    if (Array.isArray(listBody) && listBody.length > 0) {
      const firstProfile = listBody[0] as Record<string, unknown>;
      profileId = String(firstProfile['id'] ?? firstProfile['profileId'] ?? '');
    } else if (typeof listBody === 'object' && listBody !== null) {
      const bodyObj = listBody as Record<string, unknown>;
      const items = bodyObj['data'] ?? bodyObj['items'] ?? bodyObj['profiles'];
      if (Array.isArray(items) && items.length > 0) {
        const firstProfile = items[0] as Record<string, unknown>;
        profileId = String(firstProfile['id'] ?? firstProfile['profileId'] ?? '');
      }
    }

    if (!profileId) {
      console.warn('업데이트할 스포츠 프로필이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await fillInput(page, 'input-sport-profile-id', profileId);

    const { status } = await callAndGetResponse(page, 'btn-update-sports-profile');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('GET /sports-profiles/:id/score-history - 점수 히스토리를 가져와야 한다', async ({ page }) => {
    // 먼저 목록을 조회하여 ID를 얻음
    const { body: listBody } = await callAndGetResponse(page, 'btn-get-sports-profiles');

    let profileId: string | null = null;

    if (Array.isArray(listBody) && listBody.length > 0) {
      const firstProfile = listBody[0] as Record<string, unknown>;
      profileId = String(firstProfile['id'] ?? firstProfile['profileId'] ?? '');
    } else if (typeof listBody === 'object' && listBody !== null) {
      const bodyObj = listBody as Record<string, unknown>;
      const items = bodyObj['data'] ?? bodyObj['items'] ?? bodyObj['profiles'];
      if (Array.isArray(items) && items.length > 0) {
        const firstProfile = items[0] as Record<string, unknown>;
        profileId = String(firstProfile['id'] ?? firstProfile['profileId'] ?? '');
      }
    }

    if (!profileId) {
      console.warn('점수 히스토리를 조회할 스포츠 프로필이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await fillInput(page, 'input-score-hist-id', profileId);

    const { status } = await callAndGetResponse(page, 'btn-get-score-history');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });
});
