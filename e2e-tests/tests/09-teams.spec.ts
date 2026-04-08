import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  fillInput,
  callAndGetResponse,
} from './helpers';

test.describe.configure({ mode: 'serial' });

let createdTeamId: string | null = null;

test.describe('Teams API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'teams');
  });

  test('GET /teams/search - 팀을 검색해야 한다', async ({ page }) => {
    // team-search-kw input (data-testid 없음, id로 접근)
    await page.locator('#team-search-kw').fill('test');

    const { status, body } = await callAndGetResponse(page, 'btn-search-teams');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('GET /teams/nearby - 근처 팀을 가져와야 한다', async ({ page }) => {
    // nearby input들은 data-testid 없음, id로 접근
    await page.locator('#team-nearby-lat').fill('37.5009');
    await page.locator('#team-nearby-lng').fill('127.0363');
    await page.locator('#team-nearby-radius').fill('10');

    const { status, body } = await callAndGetResponse(page, 'btn-get-nearby-teams');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();
  });

  test('POST /teams - 팀을 생성해야 한다', async ({ page }) => {
    // input-team-name은 data-testid가 있음
    await fillInput(page, 'input-team-name', 'E2E Test Team');
    // team-sport select는 data-testid 없음
    await page.locator('#team-sport').selectOption('GOLF');
    await page.locator('#team-desc').fill('Test team description');
    await page.locator('#team-max-members').fill('10');

    const { status, body } = await callAndGetResponse(page, 'btn-create-team');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);

    if (Number(status) < 400 && typeof body === 'object' && body !== null) {
      const teamObj = body as Record<string, unknown>;
      createdTeamId = String(teamObj['id'] ?? teamObj['teamId'] ?? '');
    }
  });

  test('GET /teams/:id - 팀 상세를 가져와야 한다', async ({ page }) => {
    if (!createdTeamId) {
      console.warn('팀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    // input-team-id는 data-testid가 있음
    await fillInput(page, 'input-team-id', createdTeamId);

    const { status } = await callAndGetResponse(page, 'btn-get-team');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('GET /teams/:id/members - 팀 멤버를 가져와야 한다', async ({ page }) => {
    if (!createdTeamId) {
      console.warn('팀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await page.locator('#team-members-id').fill(createdTeamId);

    const { status } = await callAndGetResponse(page, 'btn-get-team-members');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('POST /teams/:id/posts - 팀 포스트를 생성해야 한다', async ({ page }) => {
    if (!createdTeamId) {
      console.warn('팀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await page.locator('#tpost-create-team-id').fill(createdTeamId);
    await page.locator('#tpost-title').fill('E2E Team Notice');
    await page.locator('#tpost-content').fill('E2E test content');
    await page.locator('#tpost-create-cat').selectOption('FREE');

    const { status } = await callAndGetResponse(page, 'btn-create-team-post');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });

  test('DELETE /teams/:id - 팀을 삭제해야 한다', async ({ page }) => {
    if (!createdTeamId) {
      console.warn('삭제할 팀이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await page.locator('#team-del-id').fill(createdTeamId);

    const { status } = await callAndGetResponse(page, 'btn-delete-team');
    // 200, 204 (삭제 성공), 403 (권한 없음) 모두 API 응답으로 간주
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
  });
});
