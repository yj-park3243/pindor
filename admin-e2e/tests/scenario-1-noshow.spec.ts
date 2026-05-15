import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';
import { psql } from './helpers/db';

/**
 * 시나리오 1 — 노쇼 신고 처리 + 신고 대상자 매칭 ban 검증
 *
 * 사전 조건 (호스트 측 sh 스크립트가 보장):
 *   - test1@gmail.com (테스트원, ID_A) ↔ test2@gmail.com (테스트투, ID_B) 매칭이 CHAT 상태
 *   - test1이 test2를 노쇼 신고 (noshow_reports.status='PENDING')
 *
 * 어드민에서 검증:
 *   1) 노쇼 신고 페이지 진입 → PENDING 상태의 신고 1건 표시
 *   2) 승인 버튼 → 메모 입력 → 확인
 *   3) DB: noshow_reports.status='APPROVED'
 *   4) DB: sports_profiles.noshow_confirmed_count 증가 + match_ban_until 설정
 *   5) (Flutter sh가 추가로 검증) test2로 매칭 요청 시 403 ban 에러
 */

const REPORTED_USER_ID =
  process.env.SCENARIO_REPORTED_USER_ID ?? '5997ec54-36f8-437b-99b4-cd09f951d290';

test('시나리오 1 — 노쇼 신고 승인 + DB 검증', async ({ page }, testInfo) => {
  const shot = (name: string) =>
    page.screenshot({
      path: testInfo.outputPath(`${name}.png`),
      fullPage: true,
    });

  await loginAsAdmin(page);
  await shot('01_dashboard');

  // ── 사전 검증: PENDING 신고 1건 이상 존재 ─────────────────────────
  const pendingBefore = psql(
    `SELECT COUNT(*) FROM noshow_reports
      WHERE reported_user_id = '${REPORTED_USER_ID}' AND status = 'PENDING';`,
  );
  expect(Number(pendingBefore.split('\n')[0]) || 0).toBeGreaterThan(0);

  // ── 1. 노쇼 신고 페이지로 진입 ────────────────────────────────────
  await page.goto('/noshow-reports');
  await page.waitForLoadState('networkidle');
  await expect(page).toHaveURL(/\/noshow-reports/);
  await shot('02_noshow_list');

  // ── 2. PENDING 행 찾고 [승인] 버튼 클릭 ───────────────────────────
  // 같은 row에 reportedUserId가 직접 안 보이므로, PENDING 행 중 첫 번째에서 승인 시도
  const pendingRow = page
    .locator('tr')
    .filter({ has: page.locator('text=대기') })
    .first();
  await pendingRow.waitFor({ state: 'visible', timeout: 15_000 });

  const approveBtn = pendingRow.getByRole('button', { name: /승인/ }).first();
  await approveBtn.click();
  await page.waitForTimeout(500);
  await shot('03_approve_modal');

  // ── 3. 메모 모달 → memo 입력 후 확인 ─────────────────────────────
  const modal = page.locator('.ant-modal');
  await modal.waitFor({ state: 'visible', timeout: 5_000 });
  const memoInput = modal.locator('textarea').first();
  await memoInput.fill('E2E 시나리오 1 — 노쇼 승인');

  const confirmBtn = modal.getByRole('button', { name: /확인|승인|저장/ }).first();
  await confirmBtn.click();

  // 모달 닫힘 + 목록 새로고침
  await modal.waitFor({ state: 'hidden', timeout: 10_000 });
  await page.waitForTimeout(1500);
  await shot('04_after_approve');

  // ── 4. DB 검증 ───────────────────────────────────────────────────
  // 4-1. noshow_reports.status = APPROVED
  const approvedCount = psql(
    `SELECT COUNT(*) FROM noshow_reports
      WHERE reported_user_id = '${REPORTED_USER_ID}' AND status = 'APPROVED';`,
  );
  expect(Number(approvedCount.split('\n')[0]) || 0).toBeGreaterThan(0);

  // 4-2. sports_profiles.noshow_confirmed_count >= 1 + match_ban_until 미래 시점
  const banRow = psql(
    `SELECT noshow_confirmed_count,
            CASE WHEN match_ban_until IS NULL THEN 'NULL' ELSE 'SET' END AS ban
     FROM sports_profiles
     WHERE user_id = '${REPORTED_USER_ID}'
     ORDER BY updated_at DESC LIMIT 1;`,
  );
  const [confirmedCountStr, banStatus] = banRow.split('\n')[0].split('\t');
  expect(Number(confirmedCountStr) || 0).toBeGreaterThan(0);
  expect(banStatus).toBe('SET');
});
