import { test, expect, Page, ConsoleMessage } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';
import * as fs from 'fs';
import * as path from 'path';

/**
 * 어드민 전 페이지 크롤러.
 *
 * 목적: 각 페이지가 빈 화면/JS 에러 없이 렌더되는지 확인 + 단계별 스크린샷.
 * - 조회 페이지: 그대로 방문 → 스크린샷
 * - 입력 페이지(모달): 추가/생성 버튼 클릭 → 모달 열림 스크린샷 (제출 X)
 * - 동적 :id 라우트: 리스트 페이지에서 첫 번째 행 ID 추출 → 상세 방문
 *
 * 결과:
 *   test-results/admin-e2e/crawl/{step:02d}_{phase}_{label}.png
 *   test-results/admin-e2e/crawl-report.json
 */

interface PageReport {
  step: number;
  label: string;
  url: string;
  status: 'ok' | 'fail';
  reasons: string[];
  consoleErrors: string[];
  pageErrors: string[];
  failedRequests: string[];
  screenshots: string[]; // 이 단계에서 찍힌 스크린샷 파일 경로
}

const SAMPLE_USER_ID = 'd54ed596-a92e-427b-83ce-ae62cfc8368e';

// 정적 조회 페이지
const STATIC_ROUTES: Array<{ label: string; path: string }> = [
  { label: '대시보드', path: '/dashboard' },
  { label: '사용자목록', path: '/users' },
  { label: '사용자상세_지정ID', path: `/users/${SAMPLE_USER_ID}` },
  { label: '스포츠프로필', path: '/profiles' },
  { label: '매칭관리', path: '/matches' },
  { label: '경기결과', path: '/games' },
  { label: '이의신청처리', path: '/games/review' },
  { label: '핀관리', path: '/pins' },
  { label: '게시판관리', path: '/posts' },
  { label: '신고처리', path: '/reports' },
  { label: '랭킹관리', path: '/rankings' },
  { label: '알림발송', path: '/notifications' },
  { label: '통계분석', path: '/statistics' },
  { label: '팀목록', path: '/teams' },
  { label: '팀매칭', path: '/team-matches' },
  { label: '공지사항', path: '/notices' },
  { label: '이의제기', path: '/disputes' },
  { label: '노쇼신고', path: '/noshow-reports' },
  { label: '어드민계정', path: '/settings/accounts' },
  { label: '시스템설정', path: '/settings/system' },
];

// 모달이 떠야 하는 입력 페이지 — 버튼만 클릭하고 제출 X
const MODAL_TRIGGER_PAGES: Array<{
  label: string;
  path: string;
  buttonText: RegExp;
}> = [
  { label: '핀생성모달', path: '/pins', buttonText: /핀 추가|핀 생성|^추가$|^생성$/ },
  { label: '공지사항생성모달', path: '/notices', buttonText: /새 공지 작성|공지 추가|공지 작성|새 공지/ },
];

// 리스트 → 상세 진입. 첫 행에서 ID 추출하거나, 액션 버튼 클릭으로 URL 캡처
type DetailEntry =
  | {
      kind: 'extract';
      label: string;
      listLabel: string;
      listPath: string;
      detailPathTemplate: (id: string) => string;
      rowIdSelector: string;
    }
  | {
      kind: 'click';
      label: string;
      listLabel: string;
      listPath: string;
      // 첫 행 안의 클릭할 요소 (URL 변경 유도)
      rowClickSelector: string;
      // 진입한 URL이 매칭하는 패턴 (sanity check)
      urlPattern: RegExp;
    };

const DYNAMIC_DETAIL_PAGES: DetailEntry[] = [
  {
    kind: 'click',
    label: '경기상세_첫행',
    listLabel: '경기결과_ID추출',
    listPath: '/games',
    rowClickSelector: 'tbody tr:first-child button[type="button"]', // action column 첫 버튼 (눈 아이콘)
    urlPattern: /\/games\/[0-9a-f-]+$/,
  },
  {
    kind: 'extract',
    label: '팀상세_첫행',
    listLabel: '팀목록_ID추출',
    listPath: '/teams',
    detailPathTemplate: (id) => `/teams/${id}`,
    rowIdSelector: 'tbody tr:first-child td:first-child',
  },
];

const SHOT_DIR = path.join(process.cwd(), 'test-results', 'admin-e2e', 'crawl');
let stepCounter = 0;

function nextStep(): number {
  stepCounter += 1;
  return stepCounter;
}

function shotPath(step: number, phase: string, label: string): string {
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  const safeLabel = label.replace(/[^a-zA-Z0-9가-힣_]/g, '_');
  const safePhase = phase.replace(/[^a-zA-Z0-9_]/g, '_');
  const padded = String(step).padStart(2, '0');
  return path.join(SHOT_DIR, `step${padded}_${safePhase}_${safeLabel}.png`);
}

async function snap(page: Page, step: number, phase: string, label: string): Promise<string> {
  const p = shotPath(step, phase, label);
  await page.screenshot({ path: p, fullPage: true });
  return p;
}

function hookErrorCollectors(page: Page) {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  const failedRequests: string[] = [];

  const consoleHandler = (msg: ConsoleMessage) => {
    if (msg.type() !== 'error') return;
    const text = msg.text();
    // 외부/확장 노이즈 무시
    if (text.includes('SES Removing unpermitted')) return;
    if (text.includes('lockdown-install')) return;
    consoleErrors.push(text);
  };
  const pageErrorHandler = (err: Error) =>
    pageErrors.push(`${err.name}: ${err.message}`);
  const requestFailedHandler = (req: any) => {
    const url = req.url();
    if (/google-analytics|doubleclick|hotjar|sentry/.test(url)) return;
    const failure = req.failure();
    failedRequests.push(`${req.method()} ${url} — ${failure?.errorText ?? 'unknown'}`);
  };
  const responseHandler = (resp: any) => {
    if (resp.status() >= 500) {
      failedRequests.push(`${resp.status()} ${resp.request().method()} ${resp.url()}`);
    }
  };

  page.on('console', consoleHandler);
  page.on('pageerror', pageErrorHandler);
  page.on('requestfailed', requestFailedHandler);
  page.on('response', responseHandler);

  return {
    consoleErrors,
    pageErrors,
    failedRequests,
    detach: () => {
      page.off('console', consoleHandler);
      page.off('pageerror', pageErrorHandler);
      page.off('requestfailed', requestFailedHandler);
      page.off('response', responseHandler);
    },
  };
}

async function visitAndReport(page: Page, label: string, url: string): Promise<PageReport> {
  const step = nextStep();
  const collector = hookErrorCollectors(page);
  const reasons: string[] = [];
  const screenshots: string[] = [];

  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    if (resp && !resp.ok() && resp.status() !== 304) {
      reasons.push(`HTTP ${resp.status()}`);
    }

    // 첫 도착 시점 스크린샷 (DOM은 들어왔지만 데이터/스피너 처리 전)
    screenshots.push(await snap(page, step, 'arrived', label));

    await page.waitForLoadState('networkidle', { timeout: 10_000 }).catch(() => {});
    await page
      .locator('.ant-spin-spinning')
      .first()
      .waitFor({ state: 'hidden', timeout: 10_000 })
      .catch(() => {});

    if (/\/login/.test(page.url()) && !url.includes('/login')) {
      reasons.push('로그인 페이지로 리다이렉트됨 (인증/세션 만료)');
    }

    const bodyText = (await page.locator('body').innerText().catch(() => '')) || '';
    if (bodyText.trim().length < 30) {
      reasons.push(`본문 비어있음 (innerText 길이=${bodyText.trim().length})`);
    }

    if ((await page.locator('.ant-result-error').count()) > 0) {
      reasons.push('Ant ResultError 표시됨');
    }

    // 최종(데이터 로딩 후) 스크린샷
    screenshots.push(await snap(page, step, 'loaded', label));
  } catch (e) {
    reasons.push(`예외: ${(e as Error).message}`);
    screenshots.push(await snap(page, step, 'exception', label).catch(() => ''));
  } finally {
    await page.waitForTimeout(700);
    collector.detach();
  }

  const status: PageReport['status'] =
    reasons.length === 0 &&
    collector.pageErrors.length === 0 &&
    collector.consoleErrors.length === 0
      ? 'ok'
      : 'fail';

  return {
    step,
    label,
    url,
    status,
    reasons,
    consoleErrors: collector.consoleErrors,
    pageErrors: collector.pageErrors,
    failedRequests: collector.failedRequests,
    screenshots: screenshots.filter(Boolean),
  };
}

async function tryOpenModal(
  page: Page,
  label: string,
  url: string,
  buttonText: RegExp,
): Promise<PageReport> {
  const step = nextStep();
  const collector = hookErrorCollectors(page);
  const reasons: string[] = [];
  const screenshots: string[] = [];

  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
    await page
      .locator('.ant-spin-spinning')
      .first()
      .waitFor({ state: 'hidden', timeout: 10_000 })
      .catch(() => {});

    screenshots.push(await snap(page, step, 'before_open', label));

    const btn = page.getByRole('button', { name: buttonText }).first();
    const visible = await btn.isVisible({ timeout: 3_000 }).catch(() => false);
    if (!visible) {
      reasons.push(`버튼을 찾지 못함 (pattern: ${buttonText})`);
    } else {
      await btn.click();
      const modal = page.locator('.ant-modal-content').first();
      await modal.waitFor({ state: 'visible', timeout: 5_000 }).catch(() => {});
      const modalText = (await modal.innerText().catch(() => '')) || '';
      if (modalText.trim().length < 20) {
        reasons.push('모달이 비어있음');
      }
      screenshots.push(await snap(page, step, 'modal_open', label));

      const cancelBtn = page.getByRole('button', { name: /취소|닫기|cancel/i }).last();
      if (await cancelBtn.isVisible({ timeout: 1_500 }).catch(() => false)) {
        await cancelBtn.click();
      } else {
        await page.keyboard.press('Escape');
      }
      await page.waitForTimeout(400);
      screenshots.push(await snap(page, step, 'modal_closed', label));
    }
  } catch (e) {
    reasons.push(`예외: ${(e as Error).message}`);
    screenshots.push(await snap(page, step, 'exception', label).catch(() => ''));
  } finally {
    await page.waitForTimeout(500);
    collector.detach();
  }

  const status: PageReport['status'] =
    reasons.length === 0 &&
    collector.pageErrors.length === 0 &&
    collector.consoleErrors.length === 0
      ? 'ok'
      : 'fail';

  return {
    step,
    label,
    url,
    status,
    reasons,
    consoleErrors: collector.consoleErrors,
    pageErrors: collector.pageErrors,
    failedRequests: collector.failedRequests,
    screenshots: screenshots.filter(Boolean),
  };
}

async function visitDetailViaClick(
  page: Page,
  label: string,
  listLabel: string,
  listPath: string,
  rowClickSelector: string,
  urlPattern: RegExp,
): Promise<PageReport> {
  const step = nextStep();
  const collector = hookErrorCollectors(page);
  const reasons: string[] = [];
  const screenshots: string[] = [];

  try {
    await page.goto(listPath, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
    await page
      .locator('.ant-spin-spinning')
      .first()
      .waitFor({ state: 'hidden', timeout: 10_000 })
      .catch(() => {});
    screenshots.push(await snap(page, step, 'list', listLabel));

    const target = page.locator(rowClickSelector).first();
    if (!(await target.isVisible({ timeout: 3_000 }).catch(() => false))) {
      reasons.push('리스트에 데이터가 없거나 클릭할 행이 없음 (스킵)');
    } else {
      await target.click();
      await page.waitForURL(urlPattern, { timeout: 8_000 }).catch(() => {
        reasons.push(`상세 URL로 이동하지 않음 (현재: ${page.url()})`);
      });
      await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
      await page
        .locator('.ant-spin-spinning')
        .first()
        .waitFor({ state: 'hidden', timeout: 10_000 })
        .catch(() => {});
      screenshots.push(await snap(page, step, 'detail_loaded', label));

      const bodyText = (await page.locator('body').innerText().catch(() => '')) || '';
      if (bodyText.trim().length < 30) {
        reasons.push(`본문 비어있음 (innerText 길이=${bodyText.trim().length})`);
      }
    }
  } catch (e) {
    reasons.push(`예외: ${(e as Error).message}`);
    screenshots.push(await snap(page, step, 'exception', label).catch(() => ''));
  } finally {
    await page.waitForTimeout(500);
    collector.detach();
  }

  // "데이터 없음 스킵"은 fail이 아니라 ok + 메모로 처리
  const isJustSkip =
    reasons.length === 1 && reasons[0].includes('스킵') &&
    collector.pageErrors.length === 0 &&
    collector.consoleErrors.length === 0;

  const status: PageReport['status'] =
    (reasons.length === 0 || isJustSkip) &&
    collector.pageErrors.length === 0 &&
    collector.consoleErrors.length === 0
      ? 'ok'
      : 'fail';

  return {
    step,
    label,
    url: listPath,
    status,
    reasons,
    consoleErrors: collector.consoleErrors,
    pageErrors: collector.pageErrors,
    failedRequests: collector.failedRequests,
    screenshots: screenshots.filter(Boolean),
  };
}

async function pickFirstRowId(
  page: Page,
  listLabel: string,
  listPath: string,
  selector: string,
): Promise<{ id: string | null; screenshot: string }> {
  const step = nextStep();
  await page.goto(listPath, { waitUntil: 'domcontentloaded', timeout: 30_000 });
  await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
  await page
    .locator('.ant-spin-spinning')
    .first()
    .waitFor({ state: 'hidden', timeout: 10_000 })
    .catch(() => {});
  const screenshot = await snap(page, step, 'list_for_id', listLabel);

  const cell = page.locator(selector).first();
  if (!(await cell.isVisible().catch(() => false))) {
    return { id: null, screenshot };
  }
  const text = (await cell.innerText().catch(() => '')) || '';
  const m = text.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
  return { id: m ? m[0] : null, screenshot };
}

test('admin 전체 페이지 크롤 + 단계별 스크린샷', async ({ page }) => {
  test.setTimeout(900_000); // 15분
  fs.mkdirSync(SHOT_DIR, { recursive: true });

  // 0) 로그인
  const loginStep = nextStep();
  await snap(page, loginStep, 'login_before', '로그인전');
  await loginAsAdmin(page);
  await snap(page, loginStep, 'login_after', '로그인후');

  const reports: PageReport[] = [];

  // 1) 정적 조회 페이지
  for (const r of STATIC_ROUTES) {
    reports.push(await visitAndReport(page, r.label, r.path));
  }

  // 2) 동적 :id 라우트
  for (const d of DYNAMIC_DETAIL_PAGES) {
    if (d.kind === 'extract') {
      const { id, screenshot } = await pickFirstRowId(page, d.listLabel, d.listPath, d.rowIdSelector);
      if (!id) {
        // 데이터가 없는 건 페이지 버그가 아니므로 status='ok' + reasons에 메모만
        reports.push({
          step: stepCounter,
          label: d.label,
          url: d.listPath,
          status: 'ok',
          reasons: ['리스트에 데이터가 없어 상세 진입 스킵 (페이지 버그 아님)'],
          consoleErrors: [],
          pageErrors: [],
          failedRequests: [],
          screenshots: [screenshot],
        });
        continue;
      }
      reports.push(await visitAndReport(page, d.label, d.detailPathTemplate(id)));
    } else {
      // click kind
      const r = await visitDetailViaClick(
        page,
        d.label,
        d.listLabel,
        d.listPath,
        d.rowClickSelector,
        d.urlPattern,
      );
      reports.push(r);
    }
  }

  // 3) 모달 입력 페이지 (제출 X)
  for (const m of MODAL_TRIGGER_PAGES) {
    reports.push(await tryOpenModal(page, m.label, m.path, m.buttonText));
  }

  // ── 결과 요약 ──
  const ok = reports.filter((r) => r.status === 'ok');
  const fail = reports.filter((r) => r.status === 'fail');

  console.log('\n=========================================');
  console.log(`[CRAWL] ✅ ${ok.length}  ❌ ${fail.length}  / 총 ${reports.length}`);
  console.log('=========================================\n');
  for (const r of reports) {
    const mark = r.status === 'ok' ? '✅' : '❌';
    console.log(`${mark} step${String(r.step).padStart(2, '0')} [${r.label}] ${r.url}`);
    for (const reason of r.reasons) console.log(`   - reason: ${reason}`);
    for (const e of r.pageErrors) console.log(`   - pageError: ${e.slice(0, 220)}`);
    for (const e of r.consoleErrors.slice(0, 3))
      console.log(`   - console: ${e.slice(0, 220)}`);
    for (const e of r.failedRequests.slice(0, 3))
      console.log(`   - failed: ${e.slice(0, 220)}`);
  }
  console.log(`\n[CRAWL] 스크린샷 디렉터리: ${SHOT_DIR}`);

  const reportPath = path.join(SHOT_DIR, '..', 'crawl-report.json');
  fs.writeFileSync(
    reportPath,
    JSON.stringify(
      { summary: { ok: ok.length, fail: fail.length, total: reports.length }, reports },
      null,
      2,
    ),
    'utf-8',
  );
  console.log(`[CRAWL] JSON 리포트: ${reportPath}`);

  expect(fail, `실패 페이지: ${fail.map((f) => f.label).join(', ')}`).toEqual([]);
});
