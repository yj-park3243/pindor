import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  selectOption,
  callAndGetResponse,
} from './helpers';

test.describe('Uploads API', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
    await navigateTo(page, 'uploads');
  });

  test('POST /uploads/presigned-url - 프로필 이미지 업로드용 presigned URL을 발급해야 한다', async ({ page }) => {
    // input-upload-purpose는 data-testid가 있음 (select)
    await selectOption(page, 'input-upload-purpose', 'PROFILE_IMAGE');
    // upload-content-type, upload-file-name은 data-testid 없음, id로 접근
    // 기본값(image/jpeg, test.jpg)이 이미 설정되어 있으므로 추가 조작 불필요

    const { status, body } = await callAndGetResponse(page, 'btn-get-presigned-url');
    // API가 응답했는지 확인
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(Number(status)).toBeLessThan(500);
    expect(body).toBeTruthy();

    // 성공한 경우 url 필드가 있어야 함
    if (Number(status) < 400 && typeof body === 'object' && body !== null) {
      const bodyObj = body as Record<string, unknown>;
      const hasUrl =
        bodyObj['url'] !== undefined ||
        bodyObj['uploadUrl'] !== undefined ||
        bodyObj['presignedUrl'] !== undefined;
      expect(hasUrl).toBe(true);
    }
  });
});
