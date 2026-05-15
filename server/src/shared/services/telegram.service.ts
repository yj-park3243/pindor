import { env } from '../../config/env.js';

/**
 * 텔레그램 관리자 알림 서비스
 *
 * - TELEGRAM_BOT_TOKEN, TELEGRAM_ADMIN_CHAT_ID 가 모두 있어야 동작
 * - 어떤 비즈니스 로직도 텔레그램 실패로 깨지지 않도록 fail-silent (catch 후 로그)
 * - HTML 파싱: 메시지 안에 사용자 입력이 들어가면 escapeHtml() 로 감쌀 것
 */

const TG_API_BASE = 'https://api.telegram.org';

function isConfigured(): boolean {
  return Boolean(env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_ADMIN_CHAT_ID);
}

/** 텔레그램 HTML mode 에서 위험한 문자 이스케이프 */
export function escapeHtml(input: unknown): string {
  return String(input ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/**
 * 관리자 채널/DM 으로 메시지 전송 (fail-silent).
 * 비동기지만 await 강제하지 않음 — 호출부에서 fire-and-forget 으로 사용.
 */
export async function sendAdminAlert(message: string): Promise<void> {
  if (!isConfigured()) return;

  try {
    const url = `${TG_API_BASE}/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: env.TELEGRAM_ADMIN_CHAT_ID,
        text: message,
        parse_mode: 'HTML',
        disable_web_page_preview: true,
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.info(`[Telegram] sendMessage failed: ${res.status} ${text}`);
    }
  } catch (err) {
    // 외부 API 일시 장애 (ETIMEDOUT 등)는 fail-silent — error.log 노이즈 방지
    console.info('[Telegram] send error:', (err as Error).message);
  }
}

/**
 * Chat ID 발견용 헬퍼 — 봇과 첫 대화 시작 후 호출하면 최근 update 의 chat.id 를 반환.
 * `npm run telegram:chat-id` 등 일회용 스크립트에서 사용.
 */
export async function discoverAdminChatId(): Promise<string | null> {
  if (!env.TELEGRAM_BOT_TOKEN) return null;
  try {
    const url = `${TG_API_BASE}/bot${env.TELEGRAM_BOT_TOKEN}/getUpdates`;
    const res = await fetch(url);
    const json = (await res.json()) as { ok: boolean; result?: any[] };
    if (!json.ok || !json.result || json.result.length === 0) return null;
    const last = json.result[json.result.length - 1];
    const chatId = last?.message?.chat?.id ?? last?.my_chat_member?.chat?.id;
    return chatId ? String(chatId) : null;
  } catch (err) {
    console.warn('[Telegram] discoverAdminChatId error:', err);
    return null;
  }
}
