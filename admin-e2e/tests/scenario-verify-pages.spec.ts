import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';

/**
 * S4~S7 검증 보조 spec — 각 시나리오 실행 직후 admin UI에서 결과 페이지 스크린샷.
 * Flutter 시뮬레이터 없이 API+DB로 진행한 시나리오의 시각적 증거 확보용.
 *
 * 페이지:
 *   - 매칭 관리: forfeit/완료 매치 보임
 *   - 경기 결과: VERIFIED 게임 + 매너 점수
 *   - 신고 처리: 노쇼 신고 + 처리 결과
 *   - 대시보드: 전체 상태
 */

test('S4-S7 검증 — admin 페이지 스크린샷', async ({ page }, testInfo) => {
  const shot = (name: string) =>
    page.screenshot({
      path: testInfo.outputPath(`${name}.png`),
      fullPage: true,
    });

  await loginAsAdmin(page);
  await shot('01_dashboard');

  // 매칭 관리
  await page.goto('/matches');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  await shot('02_matches_list');

  // 경기 결과
  await page.goto('/games');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  await shot('03_games_list');

  // 노쇼 신고
  await page.goto('/noshow-reports');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  await shot('04_noshow_list');

  // 이의 제기
  await page.goto('/disputes');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  await shot('05_dispute_list');

  // 사용자 목록 (테스트원/테스트투 점수/매너 확인)
  await page.goto('/users');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  const search = page.locator('input[placeholder*="검색" i]').first();
  if (await search.isVisible().catch(() => false)) {
    await search.fill('test1@gmail.com');
    await page.waitForTimeout(800);
    await shot('06_user_test1');
    await search.fill('test2@gmail.com');
    await page.waitForTimeout(800);
    await shot('07_user_test2');
  }

  expect(true).toBe(true);
});
