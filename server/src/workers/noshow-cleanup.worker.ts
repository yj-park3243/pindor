import 'reflect-metadata';
import 'dotenv/config';
import { AppDataSource } from '../config/database.js';

// ─────────────────────────────────────
// 노쇼 신고 정리 워커
// 매일 1회 실행:
// 1. 7일 이상 PENDING/INSUFFICIENT → 자동 REJECTED
// 2. match_request_ban_until 만료된 임시 차단 자동 해제
// ─────────────────────────────────────

export async function runNoshowCleanup(): Promise<void> {
  if (!AppDataSource.isInitialized) {
    await AppDataSource.initialize();
  }

  const now = new Date();

  // 1. 7일 이상 PENDING/INSUFFICIENT 자동 REJECTED 처리
  const autoRejectResult = await AppDataSource.query(
    `UPDATE noshow_reports
     SET status = 'REJECTED',
         admin_memo = '7일 초과 미처리로 자동 기각',
         admin_decision_at = NOW(),
         updated_at = NOW()
     WHERE status IN ('PENDING', 'INSUFFICIENT')
       AND created_at < NOW() - INTERVAL '7 days'
     RETURNING id, reported_profile_id AS "reportedProfileId"`,
  );

  if (autoRejectResult.length > 0) {
    console.info(`[NoshowCleanup] Auto-rejected ${autoRejectResult.length} overdue reports`);

    // 자동 기각된 신고의 임시 차단 해제
    const profileIds = autoRejectResult.map((r: any) => r.reportedProfileId);
    if (profileIds.length > 0) {
      await AppDataSource.query(
        `UPDATE sports_profiles
         SET match_request_ban_until = NULL
         WHERE id = ANY($1::uuid[])`,
        [profileIds],
      );
    }
  }

  // 2. match_request_ban_until 만료된 임시 차단 자동 해제
  const expiredBanResult = await AppDataSource.query(
    `UPDATE sports_profiles
     SET match_request_ban_until = NULL
     WHERE match_request_ban_until IS NOT NULL
       AND match_request_ban_until <= $1
     RETURNING id`,
    [now],
  );

  if (expiredBanResult.length > 0) {
    console.info(`[NoshowCleanup] Cleared ${expiredBanResult.length} expired match_request_ban_until`);
  }
}

// ─────────────────────────────────────
// server.ts에서 registerNoshowCleanupCron() 호출로 등록
// ─────────────────────────────────────

export async function registerNoshowCleanupCron(): Promise<void> {
  // 매일 새벽 2시 실행 (UTC 기준 17:00 = KST 02:00)
  const now = new Date();
  const nextRun = new Date(now);
  nextRun.setUTCHours(17, 0, 0, 0);
  if (nextRun <= now) {
    nextRun.setUTCDate(nextRun.getUTCDate() + 1);
  }

  const delayMs = nextRun.getTime() - now.getTime();

  const scheduleNext = async () => {
    try {
      await runNoshowCleanup();
    } catch (err) {
      console.error('[NoshowCleanup] Error during cleanup:', err instanceof Error ? err.message : err);
    }
    // 24시간 후 재실행
    setTimeout(scheduleNext, 24 * 60 * 60 * 1000);
  };

  setTimeout(scheduleNext, delayMs);
  console.info(`[NoshowCleanup] Scheduled daily cleanup, next run in ${Math.round(delayMs / 1000 / 60)} minutes`);
}
