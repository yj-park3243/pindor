/**
 * 전체 테스트 러너
 * 1) seed-test-users.ts 실행
 * 2) test-matching.ts 실행
 * 3) test-game-flow.ts 실행
 * 4) 결과 요약 출력
 *
 * 실행: npx tsx tests/run-all.ts
 */

import 'dotenv/config';
import { execSync, ExecSyncOptionsWithStringEncoding } from 'child_process';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

// ─────────────────────────────────────
// 컬러 출력 헬퍼
// ─────────────────────────────────────

const c = {
  green:  (s: string) => `\x1b[32m${s}\x1b[0m`,
  red:    (s: string) => `\x1b[31m${s}\x1b[0m`,
  blue:   (s: string) => `\x1b[34m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  bold:   (s: string) => `\x1b[1m${s}\x1b[0m`,
  dim:    (s: string) => `\x1b[2m${s}\x1b[0m`,
};

// ─────────────────────────────────────
// 타이머 헬퍼
// ─────────────────────────────────────

function formatMs(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

// ─────────────────────────────────────
// 스크립트 실행 헬퍼
// ─────────────────────────────────────

interface RunResult {
  name: string;
  passed: boolean;
  duration: number;
  output: string;
  error?: string;
}

function runScript(name: string, scriptPath: string): RunResult {
  const start = Date.now();
  const opts: ExecSyncOptionsWithStringEncoding = {
    cwd: ROOT,
    encoding: 'utf-8',
    env: {
      ...process.env,
      FORCE_COLOR: '1',        // 컬러 출력 유지
      NODE_ENV: 'test',
    },
    stdio: 'pipe',
  };

  try {
    const output = execSync(`npx tsx ${scriptPath}`, opts);
    const duration = Date.now() - start;
    return { name, passed: true, duration, output };
  } catch (err: any) {
    const duration = Date.now() - start;
    const output: string = err.stdout ?? '';
    const error: string  = err.stderr ?? err.message ?? String(err);
    return { name, passed: false, duration, output, error };
  }
}

// ─────────────────────────────────────
// 메인
// ─────────────────────────────────────

async function main(): Promise<void> {
  const suiteStart = Date.now();

  console.log(c.bold(c.blue('╔═══════════════════════════════════════╗')));
  console.log(c.bold(c.blue('║   SportMatch API 전체 테스트 러너     ║')));
  console.log(c.bold(c.blue('╚═══════════════════════════════════════╝')));
  console.log();
  console.log(c.dim(`  실행 시각: ${new Date().toLocaleString('ko-KR')}`));
  console.log(c.dim(`  API Base:  ${process.env.API_BASE ?? 'http://localhost:3000/v1'}`));
  console.log(c.dim(`  Root:      ${ROOT}`));
  console.log();

  const suites = [
    { name: '1. 테스트 유저 시드',     script: 'tests/seed-test-users.ts' },
    { name: '2. 매칭 시나리오 테스트', script: 'tests/test-matching.ts'   },
    { name: '3. 경기 플로우 테스트',   script: 'tests/test-game-flow.ts'  },
  ];

  const results: RunResult[] = [];

  for (const suite of suites) {
    console.log(c.bold(c.blue(`\n${'─'.repeat(43)}`)));
    console.log(c.bold(c.blue(`  ${suite.name}`)));
    console.log(c.bold(c.blue(`${'─'.repeat(43)}\n`)));

    const result = runScript(suite.name, suite.script);
    results.push(result);

    // stdout 출력 (항상)
    if (result.output) {
      // 각 줄에 들여쓰기 추가
      const lines = result.output.split('\n');
      for (const line of lines) {
        if (line.trim()) console.log(`  ${line}`);
      }
    }

    // 실패 시 stderr 출력
    if (!result.passed && result.error) {
      console.log(c.red('\n  [STDERR]'));
      const errLines = result.error.split('\n').slice(0, 20); // 최대 20줄
      for (const line of errLines) {
        if (line.trim()) console.log(c.dim(`  ${line}`));
      }
    }

    const statusLabel = result.passed
      ? c.green(`[PASS] (${formatMs(result.duration)})`)
      : c.red(`[FAIL] (${formatMs(result.duration)})`);

    console.log(`\n  ${suite.name} → ${statusLabel}`);
  }

  // ─── 최종 요약 ───
  const totalDuration = Date.now() - suiteStart;
  const passedCount = results.filter(r => r.passed).length;
  const failedCount = results.filter(r => !r.passed).length;

  console.log();
  console.log(c.bold(c.blue('╔═══════════════════════════════════════╗')));
  console.log(c.bold(c.blue('║           최종 결과 요약              ║')));
  console.log(c.bold(c.blue('╚═══════════════════════════════════════╝')));
  console.log();

  for (const r of results) {
    const icon   = r.passed ? c.green('✓') : c.red('✗');
    const label  = r.passed ? c.green(r.name) : c.red(r.name);
    const timing = c.dim(`(${formatMs(r.duration)})`);
    console.log(`  ${icon} ${label} ${timing}`);
  }

  console.log();
  console.log(`  전체 소요 시간: ${c.bold(formatMs(totalDuration))}`);
  console.log(`  결과: ${c.green(`${passedCount}개 성공`)} / ${failedCount > 0 ? c.red(`${failedCount}개 실패`) : c.dim('0개 실패')}`);
  console.log();

  if (failedCount === 0) {
    console.log(c.bold(c.green('  모든 테스트 스위트 통과!')));
  } else {
    console.log(c.bold(c.red(`  ${failedCount}개 스위트 실패 — 위 출력에서 원인을 확인하세요.`)));
    console.log(c.yellow('  도움말:'));
    console.log(c.yellow('    - 서버가 실행 중인지 확인: npm run dev'));
    console.log(c.yellow('    - DB 연결 확인: DATABASE_URL 환경변수'));
    console.log(c.yellow('    - 개별 실행: npx tsx tests/<script>.ts'));
    process.exit(1);
  }
}

main().catch(err => {
  console.error(c.red('[FATAL]'), err);
  process.exit(1);
});
