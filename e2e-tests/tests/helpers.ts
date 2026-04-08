import { Page, expect } from '@playwright/test';

/**
 * 테스트 유저 드롭다운에서 특정 인덱스의 유저를 선택한다.
 * 첫 번째 옵션은 placeholder이므로 index+1 위치의 옵션을 선택한다.
 */
export async function selectUser(page: Page, index: number): Promise<void> {
  const selector = page.getByTestId('user-selector');
  await selector.waitFor({ state: 'visible' });

  // test-users.json 로드 대기 (option이 placeholder 외에 추가될 때까지)
  await expect(selector.locator('option')).not.toHaveCount(1, { timeout: 10000 });

  const options = await selector.locator('option').all();
  // 첫 번째 옵션은 "-- 유저 선택 --" placeholder
  const actualIndex = index + 1;
  const targetIndex = Math.min(actualIndex, options.length - 1);
  const targetValue = await options[targetIndex].getAttribute('value');

  if (targetValue === null || targetValue === '') {
    throw new Error(`인덱스 ${index}에 해당하는 유저 옵션이 없습니다.`);
  }

  await selector.selectOption({ index: targetIndex });
  // 유저 선택 후 상태 반영 대기
  await page.waitForTimeout(300);
}

/**
 * data-testid로 버튼을 클릭한다.
 */
export async function clickButton(page: Page, testId: string): Promise<void> {
  const button = page.getByTestId(testId);
  await button.scrollIntoViewIfNeeded();
  await button.click();
}

/**
 * data-testid로 입력 필드를 찾아 값을 입력한다.
 */
export async function fillInput(page: Page, testId: string, value: string): Promise<void> {
  const input = page.getByTestId(testId);
  await input.scrollIntoViewIfNeeded();
  await input.clear();
  await input.fill(value);
}

/**
 * data-testid로 select 필드를 찾아 값을 선택한다.
 */
export async function selectOption(page: Page, testId: string, value: string): Promise<void> {
  const select = page.getByTestId(testId);
  await select.scrollIntoViewIfNeeded();
  await select.selectOption(value);
}

/**
 * response-status 영역에서 현재 응답 상태 코드를 가져온다.
 */
export async function getResponseStatus(page: Page): Promise<string> {
  const statusEl = page.getByTestId('response-status');
  const text = (await statusEl.textContent()) ?? '';
  // "200 45ms" -> "200"
  return text.split(' ')[0];
}

/**
 * response-viewer 영역에서 응답 본문을 파싱하여 반환한다.
 */
export async function getResponseBody(page: Page): Promise<unknown> {
  const viewer = page.getByTestId('response-viewer');
  const text = (await viewer.textContent()) ?? '';

  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

/**
 * API 응답이 도착할 때까지 기다린다.
 * response-status에 숫자가 나타나고 response-viewer에 내용이 있을 때까지 대기.
 */
export async function waitForResponse(page: Page): Promise<void> {
  // response-status (response-viewer-mini)에 숫자가 나타날 때까지 대기
  await expect(page.getByTestId('response-status')).toHaveText(/\d+/, { timeout: 15000 });
  // response-viewer에 내용이 있을 때까지 대기
  await expect(page.getByTestId('response-viewer')).not.toBeEmpty({ timeout: 15000 });
}

/**
 * 사이드바 네비게이션에서 특정 모듈로 이동한다.
 */
export async function navigateTo(page: Page, module: string): Promise<void> {
  const navItem = page.getByTestId(`nav-${module}`);
  await navItem.waitFor({ state: 'visible' });
  await navItem.click();
  await page.waitForTimeout(300);
}

/**
 * API 호출 후 응답을 확인하고 반환한다 (버튼 클릭 + 응답 대기 + 결과 리턴).
 */
export async function callAndGetResponse(page: Page, buttonTestId: string): Promise<{ status: string; body: unknown }> {
  // 기존 응답을 초기화 (새 응답 대기를 위해)
  await page.evaluate(() => {
    const viewer = document.querySelector('[data-testid="response-viewer"]');
    const status = document.querySelector('[data-testid="response-status"]');
    if (viewer) viewer.textContent = '';
    if (status) status.textContent = '';
  });

  await clickButton(page, buttonTestId);
  await waitForResponse(page);

  const status = await getResponseStatus(page);
  const body = await getResponseBody(page);
  return { status, body };
}
