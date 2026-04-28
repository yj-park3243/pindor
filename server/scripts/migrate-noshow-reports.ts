/**
 * 노쇼 신고 데이터 백필 스크립트
 *
 * 기존 reports 테이블의 reason='NOSHOW' 데이터를 noshow_reports로 이전 (status=APPROVED)
 * 기존 sports_profiles.no_show_count → noshow_confirmed_count 복사
 *
 * 멱등성 보장: 이미 이전된 데이터는 SKIP
 *
 * 실행: npx ts-node -e "require('./scripts/migrate-noshow-reports.ts')"
 */

import 'reflect-metadata';
import 'dotenv/config';
import { AppDataSource } from '../src/config/database.js';

async function main() {
  await AppDataSource.initialize();
  console.log('[BackfillNoshow] Connected to database');

  // 1. reports NOSHOW → noshow_reports (status=APPROVED) 백필
  // description 형식: "매치 {matchId} 노쇼 신고"에서 matchId 추출
  const noshowReports = await AppDataSource.query(
    `SELECT r.id, r.reporter_id, r.target_id, r.description, r.image_urls, r.created_at
     FROM reports r
     WHERE r.reason = 'NOSHOW'
     ORDER BY r.created_at ASC`,
  );

  console.log(`[BackfillNoshow] Found ${noshowReports.length} legacy NOSHOW reports to backfill`);

  let inserted = 0;
  let skipped = 0;
  let failed = 0;

  for (const r of noshowReports) {
    try {
      // description에서 matchId 추출
      const matchIdMatch = r.description?.match(/매치\s+([0-9a-f-]{36})/i);
      if (!matchIdMatch) {
        console.warn(`[BackfillNoshow] Cannot extract matchId from report ${r.id}, skipping`);
        skipped++;
        continue;
      }
      const matchId = matchIdMatch[1];

      // 매칭 및 신고 대상 프로필 조회
      const matchRows = await AppDataSource.query(
        `SELECT m.id, m.requester_profile_id, m.opponent_profile_id,
                req_sp.user_id AS requester_user_id,
                opp_sp.user_id AS opponent_user_id
         FROM matches m
         LEFT JOIN sports_profiles req_sp ON req_sp.id = m.requester_profile_id
         LEFT JOIN sports_profiles opp_sp ON opp_sp.id = m.opponent_profile_id
         WHERE m.id = $1`,
        [matchId],
      );

      if (matchRows.length === 0) {
        console.warn(`[BackfillNoshow] Match ${matchId} not found for report ${r.id}, skipping`);
        skipped++;
        continue;
      }

      const match = matchRows[0];
      // reporter가 아닌 쪽이 reported
      let reportedUserId: string;
      let reportedProfileId: string;
      if (match.requester_user_id === r.reporter_id) {
        reportedUserId = match.opponent_user_id;
        reportedProfileId = match.opponent_profile_id;
      } else {
        reportedUserId = match.requester_user_id;
        reportedProfileId = match.requester_profile_id;
      }

      // 이미 백필된 경우 SKIP
      const existing = await AppDataSource.query(
        `SELECT id FROM noshow_reports WHERE match_id = $1 AND reporter_id = $2 LIMIT 1`,
        [matchId, r.reporter_id],
      );
      if (existing.length > 0) {
        skipped++;
        continue;
      }

      // noshow_reports INSERT
      await AppDataSource.query(
        `INSERT INTO noshow_reports
           (match_id, reporter_id, reported_user_id, reported_profile_id,
            status, evidence_urls, reporter_message, admin_decision_at, admin_memo, created_at, updated_at)
         VALUES ($1, $2, $3, $4, 'APPROVED', $5, '기존 노쇼 신고 (자동 백필)', NOW(), '기존 데이터 백필', $6, $6)`,
        [
          matchId,
          r.reporter_id,
          reportedUserId,
          reportedProfileId,
          r.image_urls ?? [],
          r.created_at,
        ],
      );

      inserted++;
    } catch (err) {
      console.error(`[BackfillNoshow] Error for report ${r.id}:`, err instanceof Error ? err.message : err);
      failed++;
    }
  }

  console.log(`[BackfillNoshow] Report backfill: inserted=${inserted} skipped=${skipped} failed=${failed}`);

  // 2. sports_profiles.no_show_count → noshow_confirmed_count 복사 (0인 경우 스킵)
  const copyResult = await AppDataSource.query(
    `UPDATE sports_profiles
     SET noshow_confirmed_count = no_show_count
     WHERE no_show_count > 0
       AND noshow_confirmed_count = 0`,
  );
  console.log(`[BackfillNoshow] Copied no_show_count → noshow_confirmed_count for ${copyResult.rowCount ?? 0} profiles`);

  await AppDataSource.destroy();
  console.log('[BackfillNoshow] Done');
}

main().catch((err) => {
  console.error('[BackfillNoshow] Fatal error:', err);
  process.exit(1);
});
