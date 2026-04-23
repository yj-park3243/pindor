/**
 * EC2 psql SSH 터널을 통해 운영 DB에 SQL을 실행하는 유틸.
 * - ADMIN_DB_SSH_KEY 환경변수로 SSH 키 경로 지정 (기본: ~/WebProject2/match/spots-key.pem)
 * - ADMIN_DB_SSH_HOST (기본: ec2-user@43.203.165.114)
 */
import { execFileSync } from 'node:child_process';
import * as os from 'node:os';
import * as path from 'node:path';

const SSH_KEY =
  process.env.ADMIN_DB_SSH_KEY ??
  path.join(os.homedir(), 'WebProject2/match/spots-key.pem');
const SSH_HOST = process.env.ADMIN_DB_SSH_HOST ?? 'ec2-user@43.203.165.114';

function runSsh(inlineScript: string): string {
  // ssh 원격에서 스크립트 전체를 한 번에 실행.
  // `ssh host "..."` 형태로 인자를 하나의 문자열로 전달해야 &&/source 등이 정상 해석됨.
  return execFileSync(
    'ssh',
    [
      '-i', SSH_KEY,
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ConnectTimeout=15',
      SSH_HOST,
      inlineScript,
    ],
    { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] },
  );
}

/** DB 접속 URL 로드 + psql 호출. SQL 문자열을 STDIN으로 전달. */
export function psql(sql: string): string {
  // SQL은 heredoc로 stdin 전달 (따옴표 escape 불필요)
  const cmd = [
    'cd spots-server',
    'set -a && source .env && set +a',
    "DB=$(echo \"$DATABASE_URL\" | cut -d'?' -f1)",
    `psql "$DB" -v ON_ERROR_STOP=1 -t -A -F $'\\t' <<'__E2E_SQL__'\n${sql}\n__E2E_SQL__`,
  ].join(' && ');
  return runSsh(cmd).trim();
}

/** psql 결과를 개수로 반환 (첫 줄 -> Number). */
export function psqlCount(selectSql: string): number {
  const out = psql(selectSql);
  const first = out.split('\n')[0]?.trim() ?? '0';
  return Number(first) || 0;
}
