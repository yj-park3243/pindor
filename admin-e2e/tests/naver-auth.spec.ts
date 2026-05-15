import { test, expect } from '@playwright/test';

/**
 * admin.pins.kr origin에서 Naver Maps 인증이 통과하는지 확인.
 * 로그인 불필요 — /login 페이지에 스크립트 직접 주입해서 검증.
 */
test('Naver Maps 인증 — admin.pins.kr origin에서 통과', async ({ page }) => {
  const consoleMessages: { type: string; text: string }[] = [];
  page.on('console', (msg) => {
    consoleMessages.push({ type: msg.type(), text: msg.text() });
  });

  // 공개 페이지(로그인) — admin.pins.kr origin으로 들어가야 Referer/Origin이 맞음
  await page.goto('/login', { waitUntil: 'domcontentloaded' });

  const result = await page.evaluate(async () => {
    return new Promise<{ ok: boolean; reason: string; mapInited?: boolean }>((resolve) => {
      // navermap_authFailure는 인증 실패 시 글로벌로 호출됨
      (window as any).navermap_authFailure = () => {
        resolve({ ok: false, reason: 'navermap_authFailure callback fired' });
      };

      const script = document.createElement('script');
      script.src = 'https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=539desbv96';
      script.onload = () => {
        try {
          const naver = (window as any).naver;
          if (!naver?.maps) {
            resolve({ ok: false, reason: 'naver.maps not present after load' });
            return;
          }
          const div = document.createElement('div');
          div.style.width = '300px';
          div.style.height = '300px';
          document.body.appendChild(div);
          const map = new naver.maps.Map(div, {
            center: new naver.maps.LatLng(37.5665, 126.978),
            zoom: 10,
          });
          // 인증 실패는 비동기로 일어나므로 잠시 대기
          setTimeout(() => {
            resolve({ ok: !!map, reason: 'map instantiated', mapInited: !!map });
          }, 3000);
        } catch (e) {
          resolve({ ok: false, reason: 'exception: ' + (e as Error).message });
        }
      };
      script.onerror = () => resolve({ ok: false, reason: 'script load error' });
      document.head.appendChild(script);
    });
  });

  // 콘솔 에러에서 'Authentication Failed'가 있는지도 확인
  const authFailMsg = consoleMessages.find((m) =>
    m.text.includes('Authentication Failed') || m.text.includes('인증이 실패')
  );

  console.log('--- Naver auth check ---');
  console.log('result:', result);
  if (authFailMsg) console.log('console auth fail:', authFailMsg.text);

  expect(authFailMsg, '콘솔에 Naver 인증 실패 메시지가 떴습니다').toBeUndefined();
  expect(result.ok, `결과: ${result.reason}`).toBe(true);
});
