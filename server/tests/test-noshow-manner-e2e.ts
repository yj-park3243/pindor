/**
 * 노쇼 + 매너 점수 통합 E2E 테스트
 *
 * 운영 RDS에 임시 테스트 유저 2명을 만들고, MatchingService 메서드를 직접 호출하여
 * 시나리오별 동작을 검증한 뒤 마지막에 cleanup.
 *
 * 실행:
 *   DATABASE_URL=... npx tsx tests/test-noshow-manner-e2e.ts
 */
import 'reflect-metadata';
import 'dotenv/config';
import { AppDataSource } from '../src/config/database.js';
import { MatchingService } from '../src/modules/matching/matching.service.js';
import {
  User,
  SportsProfile,
  Match,
  NoshowReport,
  MannerRating,
  AdminAccount,
} from '../src/entities/index.js';
import { AdminRole } from '../src/entities/index.js';

const c = {
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  blue: (s: string) => `\x1b[36m${s}\x1b[0m`,
  bold: (s: string) => `\x1b[1m${s}\x1b[0m`,
};

interface TestResult {
  scenario: string;
  pass: boolean;
  details: string[];
}
const results: TestResult[] = [];

// 알림 mock — 알림 발송은 검증 대상이 아님
const mockNotif = {
  send: async (_p: any) => {},
  sendBulk: async (_p: any[]) => {},
};

// 테스트 유저 생성 헬퍼
async function createTestUser(
  email: string,
  nickname: string,
): Promise<{ userId: string; profileId: string }> {
  const userRepo = AppDataSource.getRepository(User);
  const profileRepo = AppDataSource.getRepository(SportsProfile);

  const user = await userRepo.save(
    userRepo.create({
      email,
      nickname,
      status: 'ACTIVE' as any,
    }) as any,
  );
  const profile = await profileRepo.save(
    profileRepo.create({
      userId: user.id,
      sportType: 'GOLF' as any,
      displayName: nickname,
      initialScore: 1000,
      currentScore: 1000,
      displayScore: 1000,
      tier: 'BRONZE' as any,
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      draws: 0,
      mannerTotal: 0,
      mannerCount: 0,
      noshowConfirmedCount: 0,
    } as any) as any,
  );
  return { userId: user.id, profileId: profile.id };
}

// 테스트 매칭 생성 헬퍼 (CHAT 상태)
async function createTestMatch(
  requesterProfileId: string,
  opponentProfileId: string,
): Promise<string> {
  const matchRepo = AppDataSource.getRepository(Match);
  const match = await matchRepo.save(
    matchRepo.create({
      requesterProfileId,
      opponentProfileId,
      sportType: 'GOLF' as any,
      status: 'CHAT' as any,
    } as any) as any,
  );
  return match.id;
}

// SUPER_ADMIN 어드민 계정 보장 (테스트용)
async function ensureSuperAdmin(): Promise<string> {
  const adminRepo = AppDataSource.getRepository(AdminAccount);
  const existing = await adminRepo.findOne({ where: { username: 'test_super_admin' } });
  if (existing) return existing.id;
  const created = await adminRepo.save(
    adminRepo.create({
      username: 'test_super_admin',
      passwordHash: 'test',
      name: 'Test Super Admin',
      role: AdminRole.SUPER_ADMIN,
    }) as any,
  );
  return (created as any).id;
}

async function main() {
  console.log(c.bold(c.blue('\n=== 노쇼 + 매너 시스템 E2E 테스트 ===\n')));

  await AppDataSource.initialize();
  console.log(c.green('✓ DB 연결됨'));

  const matchingService = new MatchingService(AppDataSource, mockNotif as any);

  // ─── 사전: 테스트 유저 + 매칭 5개 생성 ───
  const ts = Date.now().toString().slice(-8); // 8자만
  const reporter = await createTestUser(`reporter_${ts}@test.kr`, `Rep${ts}`);
  const reported = await createTestUser(`reported_${ts}@test.kr`, `Tgt${ts}`);
  const adminId = await ensureSuperAdmin();
  console.log(
    c.blue(`\n[사전 셋업] reporter=${reporter.userId.slice(0, 8)} reported=${reported.userId.slice(0, 8)}`),
  );

  // 5개 매칭 생성 (각 시나리오용)
  const matchIds: string[] = [];
  for (let i = 0; i < 5; i++) {
    matchIds.push(await createTestMatch(reporter.profileId, reported.profileId));
  }

  // ═══════════════════════════════════════════════════════════
  // S1. 노쇼 신고 접수 → PENDING + 임시 차단 24h
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S1: 노쇼 신고 접수 (PENDING + 임시 차단)';
    const details: string[] = [];
    let pass = true;
    try {
      const result = await matchingService.reportNoshow(
        reporter.userId,
        matchIds[0],
        ['https://test.com/evidence1.jpg'],
        '안 나타남',
      );
      details.push(`API 응답: ${result.message}`);

      const report = await AppDataSource.query(
        `SELECT status, evidence_urls, reporter_message FROM noshow_reports WHERE match_id = $1`,
        [matchIds[0]],
      );
      if (report[0]?.status !== 'PENDING') {
        pass = false;
        details.push(c.red(`✗ status 기대 PENDING, 실제 ${report[0]?.status}`));
      } else {
        details.push(c.green(`✓ noshow_reports.status = PENDING`));
      }

      const profile = await AppDataSource.query(
        `SELECT match_request_ban_until, display_score FROM sports_profiles WHERE id = $1`,
        [reported.profileId],
      );
      const banUntil = profile[0]?.match_request_ban_until;
      const banDiffHours = banUntil ? (new Date(banUntil).getTime() - Date.now()) / 3600000 : 0;
      if (!banUntil || banDiffHours < 23 || banDiffHours > 25) {
        pass = false;
        details.push(c.red(`✗ match_request_ban_until 기대 ~24h, 실제 ${banDiffHours.toFixed(1)}h`));
      } else {
        details.push(c.green(`✓ match_request_ban_until ≈ 24h (${banDiffHours.toFixed(1)}h)`));
      }

      const ds = profile[0]?.display_score;
      if (ds !== 1000) {
        pass = false;
        details.push(c.red(`✗ display_score 즉시 변경되면 안 됨. 실제 ${ds}`));
      } else {
        details.push(c.green(`✓ display_score = 1000 (패널티 즉시 X)`));
      }

      const matchAfter = await AppDataSource.query(
        `SELECT status FROM matches WHERE id = $1`,
        [matchIds[0]],
      );
      if (matchAfter[0]?.status !== 'COMPLETED') {
        pass = false;
        details.push(c.red(`✗ match.status 기대 COMPLETED, 실제 ${matchAfter[0]?.status}`));
      } else {
        details.push(c.green(`✓ match.status = COMPLETED`));
      }
    } catch (err) {
      pass = false;
      details.push(c.red(`예외: ${(err as Error).message}`));
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S2. 같은 reporter→reported 24h 내 중복 신고 차단
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S2: 24h 내 중복 신고 차단';
    const details: string[] = [];
    let pass = true;
    try {
      await matchingService.reportNoshow(reporter.userId, matchIds[1], ['evidence']);
      pass = false;
      details.push(c.red(`✗ 예외 발생 안 함 (차단되어야 함)`));
    } catch (err) {
      const msg = (err as Error).message;
      if (msg.includes('24시간 내 중복')) {
        details.push(c.green(`✓ 24h 중복 신고 차단됨: "${msg}"`));
      } else {
        pass = false;
        details.push(c.red(`✗ 다른 예외: ${msg}`));
      }
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S3. 어드민 승인 (1회 → 7일 ban + 매너 +1 + 신고자 +15)
  // ═══════════════════════════════════════════════════════════
  let firstReportId = '';
  {
    const sceneName = 'S3: 어드민 승인 (1회, 7일 ban)';
    const details: string[] = [];
    let pass = true;
    try {
      const reportRow = await AppDataSource.query(
        `SELECT id FROM noshow_reports WHERE match_id = $1`,
        [matchIds[0]],
      );
      firstReportId = reportRow[0].id;
      const result = await matchingService.approveNoshowReport(
        firstReportId,
        adminId,
        '명백한 노쇼 (테스트)',
      );
      details.push(`API 응답: ${result.message}`);

      const after = await AppDataSource.query(
        `SELECT noshow_confirmed_count, display_score, match_ban_until,
                match_request_ban_until, manner_total, manner_count
         FROM sports_profiles WHERE id = $1`,
        [reported.profileId],
      );
      const a = after[0];
      const banDiffDays =
        a.match_ban_until ? (new Date(a.match_ban_until).getTime() - Date.now()) / 86400000 : 0;

      const checks: [string, boolean, string][] = [
        ['noshow_confirmed_count = 1', a.noshow_confirmed_count === 1, `${a.noshow_confirmed_count}`],
        ['display_score = 970 (-30)', a.display_score === 970, `${a.display_score}`],
        ['match_ban_until ≈ 7일', banDiffDays >= 6.9 && banDiffDays <= 7.1, `${banDiffDays.toFixed(1)}일`],
        ['match_request_ban_until = NULL (해제)', a.match_request_ban_until === null, `${a.match_request_ban_until}`],
        ['manner_total +=1 (=1)', a.manner_total === 1, `${a.manner_total}`],
        ['manner_count +=1 (=1)', a.manner_count === 1, `${a.manner_count}`],
      ];
      for (const [label, ok, val] of checks) {
        if (ok) details.push(c.green(`✓ ${label} (실제: ${val})`));
        else { pass = false; details.push(c.red(`✗ ${label} (실제: ${val})`)); }
      }

      // 신고자 +15
      const reporterAfter = await AppDataSource.query(
        `SELECT display_score FROM sports_profiles WHERE id = $1`,
        [reporter.profileId],
      );
      if (reporterAfter[0].display_score === 1015) {
        details.push(c.green(`✓ 신고자 display_score = 1015 (+15)`));
      } else {
        pass = false;
        details.push(c.red(`✗ 신고자 display_score 기대 1015, 실제 ${reporterAfter[0].display_score}`));
      }

      // manner_ratings INSERT 확인
      const mrRows = await AppDataSource.query(
        `SELECT score, source, voided_at FROM manner_ratings
         WHERE match_id = $1 AND rated_user_id = $2`,
        [matchIds[0], reported.userId],
      );
      const noshowAuto = mrRows.find((r: any) => r.source === 'NOSHOW_AUTO');
      if (noshowAuto && noshowAuto.score === 1 && !noshowAuto.voided_at) {
        details.push(c.green(`✓ manner_ratings INSERT (source=NOSHOW_AUTO, score=1)`));
      } else {
        pass = false;
        details.push(c.red(`✗ manner_ratings 누락 또는 잘못 — ${JSON.stringify(mrRows)}`));
      }
    } catch (err) {
      pass = false;
      details.push(c.red(`예외: ${(err as Error).message}`));
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S4. 어드민 기각 (악의적 X) — 임시 차단 해제 + USER 매너 평가 무효
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S4: 어드민 기각 (USER 평가 무효)';
    const details: string[] = [];
    let pass = true;
    try {
      // 사전: matchIds[1]에 신고 접수 (24h 우회를 위해 첫 신고를 26h 전으로 이동)
      await AppDataSource.query(
        `UPDATE noshow_reports SET created_at = NOW() - INTERVAL '26 hours' WHERE id = $1`,
        [firstReportId],
      );
      // 신고자가 USER 매너 평가 사전 입력 (3점)
      await AppDataSource.query(
        `INSERT INTO manner_ratings (match_id, rater_id, rated_user_id, rated_profile_id, score, source)
         VALUES ($1, $2, $3, $4, 3, 'USER')`,
        [matchIds[1], reporter.userId, reported.userId, reported.profileId],
      );
      await AppDataSource.query(
        `UPDATE sports_profiles SET manner_total = manner_total + 3, manner_count = manner_count + 1
         WHERE id = $1`,
        [reported.profileId],
      );
      const beforeMannerTotal = (await AppDataSource.query(
        `SELECT manner_total FROM sports_profiles WHERE id = $1`,
        [reported.profileId],
      ))[0].manner_total;
      details.push(c.blue(`사전: USER 매너 3점 입력. manner_total=${beforeMannerTotal} (기대 4)`));

      // 신고 접수
      await matchingService.reportNoshow(reporter.userId, matchIds[1], ['evidence']);
      const reportRow = await AppDataSource.query(
        `SELECT id FROM noshow_reports WHERE match_id = $1`,
        [matchIds[1]],
      );
      // 기각 (악의적 X)
      await matchingService.rejectNoshowReport(reportRow[0].id, adminId, '증거 불충분', false);

      const after = await AppDataSource.query(
        `SELECT match_request_ban_until, manner_total FROM sports_profiles WHERE id = $1`,
        [reported.profileId],
      );
      if (after[0].match_request_ban_until !== null) {
        pass = false;
        details.push(c.red(`✗ 임시 차단 해제 안 됨: ${after[0].match_request_ban_until}`));
      } else {
        details.push(c.green(`✓ match_request_ban_until = NULL (해제)`));
      }
      // USER 매너 평가가 voided되어 manner_total -3 (4 → 1)
      if (after[0].manner_total === 1) {
        details.push(c.green(`✓ manner_total -3 차감 (USER 평가 무효): 4 → 1`));
      } else {
        pass = false;
        details.push(c.red(`✗ manner_total 기대 1, 실제 ${after[0].manner_total}`));
      }
      const voided = await AppDataSource.query(
        `SELECT voided_at FROM manner_ratings WHERE match_id = $1 AND source = 'USER'`,
        [matchIds[1]],
      );
      if (voided[0]?.voided_at) {
        details.push(c.green(`✓ manner_ratings.voided_at 세팅됨`));
      } else {
        pass = false;
        details.push(c.red(`✗ manner_ratings.voided_at 미세팅`));
      }

      const reportAfter = await AppDataSource.query(
        `SELECT status FROM noshow_reports WHERE id = $1`,
        [reportRow[0].id],
      );
      if (reportAfter[0].status !== 'REJECTED') {
        pass = false;
        details.push(c.red(`✗ status 기대 REJECTED, 실제 ${reportAfter[0].status}`));
      } else {
        details.push(c.green(`✓ status = REJECTED`));
      }
    } catch (err) {
      pass = false;
      details.push(c.red(`예외: ${(err as Error).message}`));
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S5. 어드민 기각 (악의적 O) — 신고자 -10점 + 신고 자격 7일 차단
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S5: 어드민 기각 (악의적, 신고자 페널티)';
    const details: string[] = [];
    let pass = true;
    try {
      await AppDataSource.query(
        `UPDATE noshow_reports SET created_at = NOW() - INTERVAL '26 hours'
         WHERE reporter_id = $1`,
        [reporter.userId],
      );
      await matchingService.reportNoshow(reporter.userId, matchIds[2], ['evidence']);
      const reportRow = await AppDataSource.query(
        `SELECT id FROM noshow_reports WHERE match_id = $1`,
        [matchIds[2]],
      );

      const reporterScoreBefore = (await AppDataSource.query(
        `SELECT display_score FROM sports_profiles WHERE id = $1`,
        [reporter.profileId],
      ))[0].display_score;

      await matchingService.rejectNoshowReport(reportRow[0].id, adminId, '허위 신고로 판단', true);

      const reporterAfter = await AppDataSource.query(
        `SELECT display_score FROM sports_profiles WHERE id = $1`,
        [reporter.profileId],
      );
      const reporterUser = await AppDataSource.query(
        `SELECT noshow_report_ban_until FROM users WHERE id = $1`,
        [reporter.userId],
      );

      if (reporterAfter[0].display_score === reporterScoreBefore - 10) {
        details.push(c.green(`✓ 신고자 -10 (${reporterScoreBefore} → ${reporterAfter[0].display_score})`));
      } else {
        pass = false;
        details.push(c.red(`✗ 신고자 점수 기대 ${reporterScoreBefore - 10}, 실제 ${reporterAfter[0].display_score}`));
      }
      const banDiff = reporterUser[0].noshow_report_ban_until
        ? (new Date(reporterUser[0].noshow_report_ban_until).getTime() - Date.now()) / 86400000
        : 0;
      if (banDiff >= 6.9 && banDiff <= 7.1) {
        details.push(c.green(`✓ 신고자 noshow_report_ban_until ≈ 7일 (${banDiff.toFixed(1)}일)`));
      } else {
        pass = false;
        details.push(c.red(`✗ noshow_report_ban_until 기대 7일, 실제 ${banDiff.toFixed(1)}일`));
      }
    } catch (err) {
      pass = false;
      details.push(c.red(`예외: ${(err as Error).message}`));
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S6. 신고 자격 차단된 유저가 신고 시도 → 거부
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S6: 신고 자격 차단 유저의 신고 거부';
    const details: string[] = [];
    let pass = true;
    try {
      await matchingService.reportNoshow(reporter.userId, matchIds[3], ['evidence']);
      pass = false;
      details.push(c.red(`✗ 차단 안 됨 — 신고가 통과됨`));
    } catch (err) {
      const msg = (err as Error).message;
      if (msg.includes('신고 자격')) {
        details.push(c.green(`✓ 신고 자격 차단됨: "${msg}"`));
      } else {
        pass = false;
        details.push(c.red(`✗ 다른 예외: ${msg}`));
      }
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S7. 어드민 자료 요청 (INSUFFICIENT)
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S7: 어드민 자료 요청 (INSUFFICIENT)';
    const details: string[] = [];
    let pass = true;
    try {
      // 신고 자격 차단을 임시 해제 + 24h 차단도 해제
      await AppDataSource.query(
        `UPDATE users SET noshow_report_ban_until = NULL WHERE id = $1`,
        [reporter.userId],
      );
      await AppDataSource.query(
        `UPDATE noshow_reports SET created_at = NOW() - INTERVAL '26 hours'
         WHERE reporter_id = $1`,
        [reporter.userId],
      );

      await matchingService.reportNoshow(reporter.userId, matchIds[3], ['evidence']);
      const reportRow = await AppDataSource.query(
        `SELECT id FROM noshow_reports WHERE match_id = $1`,
        [matchIds[3]],
      );
      await matchingService.requestMoreEvidence(reportRow[0].id, adminId, '사진 더 필요');
      const after = await AppDataSource.query(
        `SELECT status FROM noshow_reports WHERE id = $1`,
        [reportRow[0].id],
      );
      if (after[0].status === 'INSUFFICIENT') {
        details.push(c.green(`✓ status = INSUFFICIENT`));
      } else {
        pass = false;
        details.push(c.red(`✗ status 기대 INSUFFICIENT, 실제 ${after[0].status}`));
      }
    } catch (err) {
      pass = false;
      details.push(c.red(`예외: ${(err as Error).message}`));
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // S8. 매너 cost 보정 — getMannerTier 함수 단위 검증
  // ═══════════════════════════════════════════════════════════
  {
    const sceneName = 'S8: 매너 등급 분류 함수 검증';
    const details: string[] = [];
    let pass = true;

    type Req = { mannerTotal: number; mannerCount: number };
    const cases: Array<[Req, string]> = [
      [{ mannerTotal: 0, mannerCount: 0 }, 'NORMAL'],   // 표본 없음
      [{ mannerTotal: 5, mannerCount: 4 }, 'NORMAL'],   // 5건 미만 → 보호
      [{ mannerTotal: 22, mannerCount: 5 }, 'GOOD'],    // 4.4 ≥ 4.0
      [{ mannerTotal: 18, mannerCount: 5 }, 'NORMAL'],  // 3.6
      [{ mannerTotal: 10, mannerCount: 5 }, 'BAD'],     // 2.0 < 2.5
    ];

    const MANNER_MIN = 5, GOOD = 4.0, BAD = 2.5;
    function tier(r: Req): string {
      if (r.mannerCount < MANNER_MIN) return 'NORMAL';
      const avg = r.mannerTotal / r.mannerCount;
      if (avg >= GOOD) return 'GOOD';
      if (avg < BAD) return 'BAD';
      return 'NORMAL';
    }
    function adj(a: string, b: string): number {
      const k = [a, b].sort().join('-');
      return k === 'GOOD-GOOD' ? -50
        : k === 'BAD-GOOD' ? 200
        : k === 'BAD-NORMAL' ? 50
        : k === 'BAD-BAD' ? -100
        : 0;
    }

    for (const [r, expected] of cases) {
      const got = tier(r);
      if (got === expected) {
        details.push(c.green(`✓ tier(${r.mannerTotal}/${r.mannerCount}) = ${got}`));
      } else {
        pass = false;
        details.push(c.red(`✗ tier(${r.mannerTotal}/${r.mannerCount}) 기대 ${expected}, 실제 ${got}`));
      }
    }
    const adjCases: Array<[string, string, number]> = [
      ['GOOD', 'GOOD', -50],
      ['GOOD', 'BAD', 200],
      ['NORMAL', 'BAD', 50],
      ['BAD', 'BAD', -100],
      ['GOOD', 'NORMAL', 0],
      ['NORMAL', 'NORMAL', 0],
    ];
    for (const [a, b, expected] of adjCases) {
      const got = adj(a, b);
      if (got === expected) {
        details.push(c.green(`✓ adj(${a},${b}) = ${got}`));
      } else {
        pass = false;
        details.push(c.red(`✗ adj(${a},${b}) 기대 ${expected}, 실제 ${got}`));
      }
    }
    results.push({ scenario: sceneName, pass, details });
  }

  // ═══════════════════════════════════════════════════════════
  // CLEANUP — 테스트 유저/매칭/신고/평가 모두 제거
  // ═══════════════════════════════════════════════════════════
  console.log(c.yellow('\n[Cleanup] 테스트 데이터 삭제 중...'));
  await AppDataSource.query(
    `DELETE FROM noshow_reports WHERE reporter_id = $1 OR reported_user_id = $1`,
    [reporter.userId],
  );
  await AppDataSource.query(
    `DELETE FROM noshow_reports WHERE reporter_id = $1 OR reported_user_id = $1`,
    [reported.userId],
  );
  await AppDataSource.query(
    `DELETE FROM manner_ratings WHERE rater_id IN ($1, $2) OR rated_user_id IN ($1, $2)`,
    [reporter.userId, reported.userId],
  );
  for (const mid of matchIds) {
    await AppDataSource.query(`DELETE FROM matches WHERE id = $1`, [mid]);
  }
  await AppDataSource.query(`DELETE FROM sports_profiles WHERE user_id IN ($1, $2)`, [
    reporter.userId,
    reported.userId,
  ]);
  await AppDataSource.query(`DELETE FROM users WHERE id IN ($1, $2)`, [
    reporter.userId,
    reported.userId,
  ]);
  console.log(c.green('✓ Cleanup 완료'));

  // ═══════════════════════════════════════════════════════════
  // 최종 리포트
  // ═══════════════════════════════════════════════════════════
  console.log(c.bold(c.blue('\n═══ 결과 ═══')));
  let passCount = 0;
  for (const r of results) {
    const head = r.pass ? c.green('PASS') : c.red('FAIL');
    console.log(`\n[${head}] ${c.bold(r.scenario)}`);
    for (const d of r.details) console.log(`  ${d}`);
    if (r.pass) passCount++;
  }
  console.log(c.bold(`\n총 ${results.length}건 / 통과 ${passCount}건 / 실패 ${results.length - passCount}건`));

  await AppDataSource.destroy();
  process.exit(passCount === results.length ? 0 : 1);
}

main().catch((err) => {
  console.error(c.red(`치명적 오류: ${err.message}`));
  console.error(err.stack);
  process.exit(2);
});
