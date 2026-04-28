import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { AppErrorLog } from '../../entities/index.js';
import { verifyAccessToken } from '../../shared/utils/jwt.js';
import { sendAdminAlert, escapeHtml } from '../../shared/services/telegram.service.js';

/**
 * 텔레그램 알림에서 제외할 노이즈 패턴 (4xx, 인증 실패, 단순 네트워크 등)
 * — 중요한 에러만 보내기 위함
 */
const TELEGRAM_NOISE_PATTERNS = [
  /\b401\b/,
  /\b403\b/,
  /\b404\b/,
  /\b409\b/,
  /\b422\b/,
  /AUTH_\d+/,
  /no_refresh_token/i,
  /Network is unreachable/i,
  /Connection (closed|refused|reset)/i,
  /SocketException/i,
  /Failed host lookup/i,
  /CERTIFICATE_VERIFY_FAILED/i,
  /User (canceled|cancelled)/i,
];

function isNoise(message: string): boolean {
  return TELEGRAM_NOISE_PATTERNS.some((re) => re.test(message));
}

type PostErrorLogBody = {
  errorMessage: string;
  stackTrace?: string;
  deviceInfo?: Record<string, unknown>;
  screenName?: string;
};

export async function errorLogRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── POST /error-logs ── 앱 에러 리포팅 (인증 선택적) ─────────────────────
  fastify.post(
    '/error-logs',
    {
      schema: {
        tags: ['ErrorLogs'],
        summary: '앱 에러 리포팅 (인증 선택적)',
        body: {
          type: 'object',
          required: ['errorMessage'],
          properties: {
            errorMessage: { type: 'string', minLength: 1, maxLength: 5000 },
            stackTrace: { type: 'string', maxLength: 20000 },
            deviceInfo: { type: 'object' },
            screenName: { type: 'string', maxLength: 100 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Body: PostErrorLogBody }>,
      reply: FastifyReply,
    ) => {
      try {
        const { errorMessage, stackTrace, deviceInfo, screenName } = request.body;

        // 인증 토큰이 있으면 userId 추출, 없어도 허용 (reply에 영향 없이 직접 파싱)
        let userId: string | null = null;
        try {
          const authHeader = request.headers.authorization;
          if (authHeader?.startsWith('Bearer ')) {
            const token = authHeader.slice(7);
            const payload = verifyAccessToken(token);
            userId = payload.userId ?? null;
          }
        } catch {
          // 인증 실패는 무시
        }

        const repo = AppDataSource.getRepository(AppErrorLog);
        const log = repo.create({
          userId,
          errorMessage,
          stackTrace: stackTrace ?? null,
          deviceInfo: deviceInfo ?? null,
          screenName: screenName ?? null,
        });

        await repo.save(log);

        // 중요 에러만 텔레그램 알림 (4xx/네트워크 오류 등은 노이즈로 제외)
        if (!isNoise(errorMessage)) {
          void sendAdminAlert(
            `🛑 <b>앱 에러</b>\n` +
              `• 화면: ${escapeHtml(screenName ?? '-')}\n` +
              `• userId: ${userId ? `<code>${escapeHtml(userId)}</code>` : '-'}\n` +
              `• message: ${escapeHtml(errorMessage.slice(0, 500))}` +
              (stackTrace
                ? `\n• stack:\n<pre>${escapeHtml(stackTrace.slice(0, 1500))}</pre>`
                : ''),
          );
        }

        return reply.status(201).send({
          success: true,
          data: { id: log.id },
        });
      } catch (err) {
        // 에러 로깅 자체가 서버 에러를 내도 클라이언트에 200 반환 (에러 리포팅 신뢰성 확보)
        fastify.log.error({ err }, '[ErrorLog] Failed to save error log');
        return reply.status(200).send({ success: true, data: null });
      }
    },
  );
}
