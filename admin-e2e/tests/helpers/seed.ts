import { psql, psqlCount } from './db';

/**
 * 조회 화면 테스트용 최소 시드.
 * - users/notices/disputes가 비어있으면 테스트용 row 삽입.
 * - 이미 있으면 아무 것도 안 함.
 */
export function ensureSeed(): { created: string[] } {
  const created: string[] = [];

  // 1) 최소 사용자 1명
  const userCount = psqlCount(
    `SELECT COUNT(*) FROM users WHERE email LIKE 'e2e_seed_%@test.com';`,
  );
  if (userCount === 0) {
    psql(`
      INSERT INTO users (id, email, nickname, status, is_verified, created_at, updated_at, last_login_at)
      VALUES
        (gen_random_uuid(), 'e2e_seed_a@test.com', 'e2e시드A', 'ACTIVE', true, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'e2e_seed_b@test.com', 'e2e시드B', 'ACTIVE', true, NOW(), NOW(), NOW())
      ON CONFLICT (email) DO NOTHING;
    `);
    created.push('users');
  }

  // 2) 공지 1건 (정상 화면 검증용, 어드민이 직접 등록 테스트에서 추가될 수도 있음)
  const noticeCount = psqlCount(
    `SELECT COUNT(*) FROM notices WHERE title LIKE '[E2E]%';`,
  );
  if (noticeCount === 0) {
    psql(`
      INSERT INTO notices (id, title, content, is_pinned, is_published, created_at, updated_at)
      VALUES (gen_random_uuid(), '[E2E] 시드 공지사항', '이 공지는 E2E 테스트용 시드입니다.', false, true, NOW(), NOW());
    `);
    created.push('notices');
  }

  return { created };
}

/**
 * 이의 신청 처리 테스트용 dispute 후보 확보.
 * - `games.result_status='DISPUTED'`인 row가 없으면, COMPLETED된 매칭의 game 하나를 DISPUTED로 변경.
 * - 대상 games이 전혀 없으면 null 반환.
 */
export function ensureDisputeCandidate(): string | null {
  const existing = psql(
    `SELECT id FROM games WHERE result_status = 'DISPUTED' LIMIT 1;`,
  );
  const existingId = existing.split('\n')[0]?.trim();
  if (existingId) return existingId;

  const anyGame = psql(
    `SELECT id FROM games WHERE result_status IN ('VERIFIED', 'PENDING') LIMIT 1;`,
  );
  const gid = anyGame.split('\n')[0]?.trim();
  if (!gid) return null;

  psql(`UPDATE games SET result_status = 'DISPUTED' WHERE id = '${gid}';`);
  return gid;
}

/**
 * 방금 seed로 DISPUTED로 만든 게임이라면 원래대로 복구.
 * 오리지널 상태를 기록해두지 않아서 VERIFIED로만 되돌린다.
 */
export function restoreDispute(gameId: string): void {
  psql(
    `UPDATE games SET result_status = 'VERIFIED', verified_at = COALESCE(verified_at, NOW()) WHERE id = '${gameId}';`,
  );
}

/** 테스트 끝나고 E2E 공지/유저 정리 (선택적으로 호출). */
export function cleanupSeed(): void {
  psql(`DELETE FROM notices WHERE title LIKE '[E2E]%';`);
  psql(`DELETE FROM users WHERE email LIKE 'e2e_seed_%@test.com';`);
}
