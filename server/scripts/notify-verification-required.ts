/**
 * 본인인증 미완료 유저에게 공지 푸시 발송 스크립트 (일회성)
 *
 * 대상: device_tokens 보유 + is_verified=false 인 유저 전체
 * 발송 방법: Firebase Admin SDK 직접 호출 (멀티캐스트)
 *
 * 실행: npx tsx scripts/notify-verification-required.ts
 */

import 'reflect-metadata';
import { AppDataSource } from '../src/config/database.js';
import { initFirebase, getFirebaseApp, isFirebaseEnabled } from '../src/config/firebase.js';
import { env } from '../src/config/env.js';

const TITLE = '본인인증 안내';
const BODY = '보다 안전한 서비스를 위해 본인인증이 필요합니다. 앱을 켜면 본인인증이 시작됩니다.';
const BATCH_SIZE = 500; // FCM 멀티캐스트 한 번에 최대 500

async function main() {
  console.log('[Script] 본인인증 미완료 유저 공지 푸시 시작');

  await AppDataSource.initialize();
  console.log('[Script] DB 연결 완료');

  initFirebase();
  if (!isFirebaseEnabled()) {
    console.error('[Script] Firebase가 활성화되어 있지 않습니다. FIREBASE_SERVICE_ACCOUNT 환경변수를 확인하세요.');
    process.exit(1);
  }

  const app = getFirebaseApp()!;

  // 미인증 유저의 FCM 토큰 조회
  const rows = await AppDataSource.query(`
    SELECT DISTINCT dt.token
    FROM device_tokens dt
    JOIN users u ON u.id = dt.user_id
    WHERE u.is_verified = FALSE
      AND u.status = 'ACTIVE'
      AND dt.is_active = TRUE
      AND dt.token IS NOT NULL
      AND dt.token != ''
  `);

  const tokens: string[] = rows.map((r: any) => r.token as string);
  console.log(`[Script] 대상 FCM 토큰 수: ${tokens.length}`);

  if (tokens.length === 0) {
    console.log('[Script] 발송 대상 없음. 종료합니다.');
    await AppDataSource.destroy();
    return;
  }

  let totalSuccess = 0;
  let totalFail = 0;

  // 배치 처리
  for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
    const batch = tokens.slice(i, i + BATCH_SIZE);
    try {
      const response = await app.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title: TITLE, body: BODY },
        data: { type: 'ADMIN', screen: 'phone-verification' },
        android: {
          priority: 'high',
          notification: { channelId: 'default', sound: 'default' },
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
      });
      totalSuccess += response.successCount;
      totalFail += response.failureCount;
      console.log(
        `[Script] 배치 ${Math.floor(i / BATCH_SIZE) + 1}: 성공=${response.successCount}, 실패=${response.failureCount}`,
      );
    } catch (e: any) {
      console.error(`[Script] 배치 ${Math.floor(i / BATCH_SIZE) + 1} 실패:`, e.message);
      totalFail += batch.length;
    }
  }

  console.log(`[Script] 완료. 총 성공=${totalSuccess}, 총 실패=${totalFail}`);
  await AppDataSource.destroy();
}

main().catch((e) => {
  console.error('[Script] 오류:', e);
  process.exit(1);
});
