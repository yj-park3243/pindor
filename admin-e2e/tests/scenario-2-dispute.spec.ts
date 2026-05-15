import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';
import { psql } from './helpers/db';

/**
 * 시나리오 2 — 이의 제기 처리
 *
 * 사전 (호스트 sh가 준비):
 *   - A가 매칭에 대해 dispute 작성 (disputes.status='PENDING')
 *
 * 어드민:
 *   1) /disputes 진입 → PENDING dispute 1건 확인
 *   2) "처리" 버튼 → 모달에서 status=RESOLVED + action=VOID_GAME + adminReply
 *   3) DB 검증: dispute RESOLVED, games VOIDED, matches CANCELLED
 */

const REPORTER_USER_ID =
  process.env.SCENARIO_REPORTER_USER_ID ?? 'faf5f8ff-d996-4e10-9c91-aa5d09bf1503';

test('시나리오 2 — 이의 제기 VOID_GAME 처리', async ({ page }, testInfo) => {
  const shot = (name: string) =>
    page.screenshot({
      path: testInfo.outputPath(`${name}.png`),
      fullPage: true,
    });

  await loginAsAdmin(page);
  await shot('01_dashboard');

  // 사전: PENDING dispute 존재 확인
  const pendingBefore = psql(
    `SELECT COUNT(*) FROM disputes WHERE reporter_id = '${REPORTER_USER_ID}' AND status = 'PENDING';`,
  );
  expect(Number(pendingBefore.split('\n')[0]) || 0).toBeGreaterThan(0);

  // matchId 추출 (검증용)
  const matchIdRaw = psql(
    `SELECT match_id FROM disputes
      WHERE reporter_id = '${REPORTER_USER_ID}' AND status = 'PENDING'
      ORDER BY created_at DESC LIMIT 1;`,
  );
  const matchId = matchIdRaw.split('\n')[0].trim();

  // 1. /disputes 진입
  await page.goto('/disputes');
  await page.waitForLoadState('networkidle');
  await expect(page).toHaveURL(/\/disputes/);
  await shot('02_dispute_list');

  // 2. PENDING 행의 "처리" 버튼 클릭
  const pendingRow = page
    .locator('tr')
    .filter({ has: page.locator('text=대기') })
    .first();
  await pendingRow.waitFor({ state: 'visible', timeout: 15_000 });

  // 액션 컬럼이 화면 우측에 있어 스크롤 필요할 수도 있음
  await pendingRow.scrollIntoViewIfNeeded();
  const actionBtn = pendingRow.getByRole('button', { name: /검토|처리|상세/ }).first();
  await actionBtn.waitFor({ state: 'visible', timeout: 10_000 });
  await actionBtn.click();
  await page.waitForTimeout(800);
  await shot('03_dispute_modal');

  // 3. 모달: status=RESOLVED, action=VOID_GAME, adminReply
  const modal = page.locator('.ant-modal');
  await modal.waitFor({ state: 'visible', timeout: 10_000 });

  // 처리 상태 Select 열기 → "완료" 옵션 클릭
  // Ant Design Select은 form item label 기반으로 찾기
  const statusSelect = modal.locator('.ant-form-item').filter({ hasText: '처리 상태' })
    .locator('.ant-select-selector').first();
  await statusSelect.click();
  // 드롭다운 옵션은 modal 외부에 portal로 그려짐
  await page.locator('.ant-select-item-option').filter({ hasText: '완료' }).first().click();
  await page.waitForTimeout(500);

  // "처리 방식" Radio Group이 status=RESOLVED 선택 시 나타남
  // "경기 무효 처리" Radio 클릭
  const voidRadio = modal.locator('label').filter({ hasText: '경기 무효 처리' }).first();
  await voidRadio.waitFor({ state: 'visible', timeout: 5_000 });
  await voidRadio.click();
  await page.waitForTimeout(300);

  // adminReply
  const replyInput = modal.locator('.ant-form-item').filter({ hasText: '관리자 답변' })
    .locator('textarea').first();
  if (await replyInput.isVisible().catch(() => false)) {
    await replyInput.fill('E2E 시나리오 2 — 경기 무효 처리');
  }

  await shot('04_modal_filled');

  // 모달 푸터의 확인 버튼 (Ant Modal okButton)
  const confirmBtn = modal.locator('.ant-modal-footer button.ant-btn-primary').first();
  await confirmBtn.click();
  await modal.waitFor({ state: 'hidden', timeout: 10_000 });
  await page.waitForTimeout(1500);
  await shot('05_after_resolve');

  // 4. DB 검증
  // 4-1. dispute RESOLVED
  const resolvedRow = psql(
    `SELECT status, admin_reply FROM disputes
      WHERE reporter_id = '${REPORTER_USER_ID}' AND match_id = '${matchId}'
      ORDER BY created_at DESC LIMIT 1;`,
  );
  const [status] = resolvedRow.split('\n')[0].split('\t');
  expect(status).toBe('RESOLVED');

  // 4-2. game VOIDED + match CANCELLED
  const gameRow = psql(
    `SELECT g.result_status, m.status FROM games g
      JOIN matches m ON m.id = g.match_id
      WHERE g.match_id = '${matchId}' LIMIT 1;`,
  );
  const [gameStatus, matchStatus] = gameRow.split('\n')[0].split('\t');
  expect(gameStatus).toBe('VOIDED');
  expect(matchStatus).toBe('CANCELLED');
});
