import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { AppErrorLog } from '../../entities/index.js';
import { verifyAccessToken } from '../../shared/utils/jwt.js';

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
