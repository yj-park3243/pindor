import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { KcpService } from './kcp.service.js';
import { AppDataSource } from '../../config/database.js';

const DEFAULT_CALLBACK_URL = 'https://api.pins.kr/v1/auth/kcp/callback';

export async function kcpRoutes(fastify: FastifyInstance): Promise<void> {
  const kcpService = new KcpService(AppDataSource);

  // ─── GET /auth/kcp/form — KCP 인증 HTML Form 생성 ───
  fastify.get(
    '/auth/kcp/form',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Auth'],
        summary: 'KCP 본인인증 HTML Form 생성',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userId = request.user.userId;
      const html = await kcpService.generateCertForm(userId, DEFAULT_CALLBACK_URL);

      return reply.status(200).send({
        success: true,
        data: { html },
      });
    },
  );

  // ─── POST /auth/kcp/callback — KCP 인증 완료 후 콜백 (KCP → 서버) ───
  // KCP가 인증 완료 후 이 URL로 POST (application/x-www-form-urlencoded)
  // 암호화된 데이터를 받아서 복호화 API 호출 → 유저 정보 저장 → 앱으로 리다이렉트
  fastify.post(
    '/auth/kcp/callback',
    {
      schema: {
        tags: ['Auth'],
        summary: 'KCP 본인인증 콜백 (인증 불필요 — KCP가 직접 호출)',
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      try {
        const body = request.body as Record<string, any>;
        const query = (request.query as Record<string, any>) ?? {};
        console.info(
          '[KCP Callback] Received body keys:',
          Object.keys(body),
          'query keys:',
          Object.keys(query),
        );

        // 1. 콜백 데이터 처리 + KCP 복호화 API 호출
        const { userId, kcpData } = await kcpService.handleCallback(body, query);

        // 2. 유저 정보 저장 + CI 중복 처리
        const result = await kcpService.verifyCert(userId, kcpData);

        // 3. 앱 WebView로 결과 전달 (커스텀 스킴 리다이렉트)
        const appUrl = `spots://kcp-cert?status=success&userId=${result.user.id}&nickname=${encodeURIComponent(result.user.nickname ?? '')}&accessToken=${encodeURIComponent(result.accessToken)}&refreshToken=${encodeURIComponent(result.refreshToken)}&nextRoute=${result.nextRoute}&isNewUser=${result.user.isNewUser}`;

        // HTML로 리다이렉트 (WebView에서 커스텀 스킴 감지)
        const redirectHtml = `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>인증 완료</title></head>
<body>
<script>window.location.href = '${appUrl}';</script>
<p>인증이 완료되었습니다. 앱으로 이동 중...</p>
<a href="${appUrl}">앱으로 이동</a>
</body></html>`;

        return reply.status(200).header('Content-Type', 'text/html; charset=utf-8').send(redirectHtml);
      } catch (err: any) {
        console.error('[KCP Callback] Error:', err.message);

        // 에러 시에도 앱으로 리다이렉트 (에러 정보 포함)
        const errorMsg = encodeURIComponent(err.message || '인증에 실패했습니다.');
        const errorUrl = `spots://kcp-cert?status=error&message=${errorMsg}`;

        const errorHtml = `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>인증 실패</title></head>
<body>
<script>window.location.href = '${errorUrl}';</script>
<p>인증에 실패했습니다. 앱으로 이동 중...</p>
<a href="${errorUrl}">앱으로 이동</a>
</body></html>`;

        return reply.status(200).header('Content-Type', 'text/html; charset=utf-8').send(errorHtml);
      }
    },
  );
}
