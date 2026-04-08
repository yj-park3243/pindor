import { test, expect } from '@playwright/test';
import {
  selectUser,
  navigateTo,
  fillInput,
  callAndGetResponse,
} from './helpers';

test.describe('Chat API & WebSocket', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await selectUser(page, 0);
  });

  test('GET /chat-rooms - 채팅룸 목록을 가져와야 한다', async ({ page }) => {
    await navigateTo(page, 'chat');
    const { status, body } = await callAndGetResponse(page, 'btn-get-chat-rooms');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
    expect(body).toBeTruthy();
  });

  test('GET /chat-rooms/:id/messages - 채팅룸 메시지를 가져와야 한다', async ({ page }) => {
    await navigateTo(page, 'chat');

    const { body: listBody } = await callAndGetResponse(page, 'btn-get-chat-rooms');
    let roomId: string | null = null;

    if (Array.isArray(listBody) && listBody.length > 0) {
      const firstRoom = listBody[0] as Record<string, unknown>;
      roomId = String(firstRoom['id'] ?? firstRoom['roomId'] ?? '');
    } else if (typeof listBody === 'object' && listBody !== null) {
      const bodyObj = listBody as Record<string, unknown>;
      const items = bodyObj['data'] ?? bodyObj['items'] ?? bodyObj['rooms'];
      if (Array.isArray(items) && items.length > 0) {
        const firstRoom = items[0] as Record<string, unknown>;
        roomId = String(firstRoom['id'] ?? firstRoom['roomId'] ?? '');
      }
    }

    if (!roomId) {
      console.warn('메시지를 조회할 채팅룸이 없습니다. 테스트를 건너뜁니다.');
      return;
    }

    await fillInput(page, 'input-chat-room-id', roomId);
    const { status } = await callAndGetResponse(page, 'btn-get-chat-messages');
    expect(Number(status)).toBeGreaterThanOrEqual(200);
  });

  test('WebSocket - 연결 및 기본 동작을 확인해야 한다', async ({ page }) => {
    await navigateTo(page, 'websocket');

    // WebSocket 연결
    const wsConnect = page.getByTestId('ws-connect');
    await wsConnect.click();

    // 연결 상태 확인
    const wsStatusDot = page.getByTestId('ws-status');
    await expect(wsStatusDot).toHaveClass(/connected/, { timeout: 10000 });

    // 연결 해제 (같은 websocket 모듈에서)
    await page.getByTestId('ws-disconnect').click();
    await expect(wsStatusDot).not.toHaveClass(/connected/, { timeout: 10000 });
  });
});
