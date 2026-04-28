/**
 * Telegram bot의 admin chat ID 발견 스크립트
 *
 * 사용법:
 *   1) 텔레그램에서 봇과 대화 시작 (메시지 1개 이상 보냄)
 *   2) `npx tsx scripts/discover-telegram-chat-id.ts` 실행
 *   3) 출력된 chat_id 를 .env 의 TELEGRAM_ADMIN_CHAT_ID 에 넣기
 */
import 'dotenv/config';
import { discoverAdminChatId } from '../src/shared/services/telegram.service.js';

(async () => {
  if (!process.env.TELEGRAM_BOT_TOKEN) {
    console.error('TELEGRAM_BOT_TOKEN 환경 변수가 설정되어 있지 않습니다.');
    process.exit(1);
  }
  const id = await discoverAdminChatId();
  if (!id) {
    console.error(
      '봇과의 최근 대화를 찾지 못했습니다. 텔레그램에서 봇에게 메시지를 한 번 보낸 뒤 다시 실행해주세요.',
    );
    process.exit(1);
  }
  console.log('TELEGRAM_ADMIN_CHAT_ID =', id);
})();
