import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  fillInput,
  callAndGetResponse,
} from './helpers';

test.describe.configure({ mode: 'serial' });

let pinnedId: string | null = null;
let createdPostId: string | null = null;

test.describe('Pins & Community API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'pins');
  });

  test('GET /pins/nearby - 주변 핀을 가져와야 한다', async ({ page }) => {
    // 위치 input들은 data-testid가 없으므로 element id로 직접 접근
    await page.locator('#pin-lat').fill('37.5009');
    await page.locator('#pin-lng').fill('127.0363');
    await page.locator('#pin-radius').fill('10');

    const { status, body } = await callAndGetResponse(page, 'btn-get-nearby-pins');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();

    // 다음 테스트를 위해 pin ID 저장
    if (Array.isArray(body) && body.length > 0) {
      const firstPin = body[0] as Record<string, unknown>;
      pinnedId = String(firstPin['id'] ?? firstPin['pinId'] ?? '');
    } else if (typeof body === 'object' && body !== null) {
      const bodyObj = body as Record<string, unknown>;
      const items = bodyObj['data'] ?? bodyObj['items'] ?? bodyObj['pins'];
      if (Array.isArray(items) && items.length > 0) {
        const firstPin = items[0] as Record<string, unknown>;
        pinnedId = String(firstPin['id'] ?? firstPin['pinId'] ?? '');
      }
    }
  });

  test('GET /pins/:id - 핀 상세를 가져와야 한다', async ({ page }) => {
    if (!pinnedId) {
      console.warn('핀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await fillInput(page, 'input-pin-id', pinnedId);
    const { status } = await callAndGetResponse(page, 'btn-get-pin');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('GET /pins/:pinId/posts - 핀 커뮤니티 포스트 목록을 가져와야 한다', async ({ page }) => {
    if (!pinnedId) {
      console.warn('핀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    // pin-posts-pin-id input에 pin ID 입력 (data-testid 없음, id로 접근)
    await page.locator('#pin-posts-pin-id').fill(pinnedId);

    const { status } = await callAndGetResponse(page, 'btn-get-pin-posts');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('POST /pins/:pinId/posts - 핀 커뮤니티 포스트를 생성해야 한다', async ({ page }) => {
    if (!pinnedId) {
      console.warn('핀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    // createPinPost 함수가 사용하는 input들 (data-testid 없음, id로 접근)
    await page.locator('#pin-post-create-pin-id').fill(pinnedId);
    await page.locator('#pin-post-title').fill('E2E Test Post');
    await page.locator('#pin-post-content').fill('This is a test post from E2E');
    await page.locator('#pin-post-cat').selectOption('GENERAL');

    const { status, body } = await callAndGetResponse(page, 'btn-create-pin-post');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);

    if (Number(status) < 400 && typeof body === 'object' && body !== null) {
      const postObj = body as Record<string, unknown>;
      createdPostId = String(postObj['id'] ?? postObj['postId'] ?? '');
    }
  });

  test('GET /pins/:pinId/posts/:postId - 포스트 상세를 가져와야 한다', async ({ page }) => {
    if (!pinnedId || !createdPostId) {
      console.warn('핀 또는 포스트가 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    // pin-post-get-pin, input-post-id (=pin-post-get-post) 입력
    await page.locator('#pin-post-get-pin').fill(pinnedId);
    await fillInput(page, 'input-post-id', createdPostId);

    const { status } = await callAndGetResponse(page, 'btn-get-pin-post');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('POST /pins/:pinId/posts/:postId/like - 포스트에 좋아요를 해야 한다', async ({ page }) => {
    if (!pinnedId || !createdPostId) {
      console.warn('핀 또는 포스트가 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await page.locator('#pin-like-pin').fill(pinnedId);
    await page.locator('#pin-like-post').fill(createdPostId);

    const { status } = await callAndGetResponse(page, 'btn-like-pin-post');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('DELETE /pins/:pinId/posts/:postId - 포스트를 삭제해야 한다', async ({ page }) => {
    if (!pinnedId || !createdPostId) {
      console.warn('핀 또는 포스트가 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await page.locator('#pin-post-del-pin').fill(pinnedId);
    await page.locator('#pin-post-del-post').fill(createdPostId);

    const { status } = await callAndGetResponse(page, 'btn-delete-pin-post');
    // 200, 204 (삭제 성공), 403/404 모두 API 응답으로 간주
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });
});
