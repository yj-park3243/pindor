// KST (UTC+9) 타임존 유틸리티
// 한국 유저 대상 서비스이므로 모든 날짜 경계는 KST 기준

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** KST 기준 현재 Date 객체 */
export function getKSTNow(): Date {
  return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Seoul' }));
}

/** KST 기준 오늘 날짜 문자열 (YYYY-MM-DD) */
export function getKSTDateString(date?: Date): string {
  const kst = date
    ? new Date(date.toLocaleString('en-US', { timeZone: 'Asia/Seoul' }))
    : getKSTNow();
  const y = kst.getFullYear();
  const m = String(kst.getMonth() + 1).padStart(2, '0');
  const d = String(kst.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** KST 기준 현재 시간 (0-23) */
export function getKSTHour(): number {
  return getKSTNow().getHours();
}

/** KST 기준 오늘 자정 (00:00:00) → UTC Date 객체 */
export function getKSTMidnight(date?: Date): Date {
  const kstDateStr = getKSTDateString(date);
  return new Date(`${kstDateStr}T00:00:00+09:00`);
}

/** KST 기준 오늘 끝 (23:59:59) → UTC Date 객체 */
export function getKSTEndOfDay(date?: Date): Date {
  const kstDateStr = getKSTDateString(date);
  return new Date(`${kstDateStr}T23:59:59+09:00`);
}
