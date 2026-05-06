import { FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { User } from '../../entities/index.js';
import { AppError, ErrorCode } from '../errors/app-error.js';

/**
 * 본인인증 완료 여부 확인 미들웨어
 * - `fastify.authenticate` 이후에 사용
 * - isVerified=false 인 유저는 403 + VERIFICATION_REQUIRED 반환
 *
 * ⚠️ App Store 심사 대응을 위해 임시로 본인인증 검증 우회 (2026-04-29)
 *    REQUIRE_VERIFIED_ENABLED=true 설정 시에만 검증 활성화.
 *    심사 통과 후 env 켜서 다시 활성화할 것.
 */
const VERIFICATION_ENABLED =
  process.env.REQUIRE_VERIFIED_ENABLED === 'true';

export async function requireVerified(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  // 임시 우회 — env 비활성 시 모든 인증된 유저 통과
  if (!VERIFICATION_ENABLED) return;

  const userId = request.user?.userId;
  if (!userId) {
    return reply
      .status(401)
      .send(new AppError(ErrorCode.AUTH_MISSING_TOKEN, 401).toJSON());
  }

  const userRepo = AppDataSource.getRepository(User);
  const user = await userRepo.findOne({
    where: { id: userId },
    select: { id: true, isVerified: true, status: true },
  });

  if (!user) {
    return reply
      .status(401)
      .send(new AppError(ErrorCode.USER_NOT_FOUND, 401).toJSON());
  }

  if (!user.isVerified) {
    return reply
      .status(403)
      .send(
        new AppError(
          ErrorCode.VERIFICATION_REQUIRED,
          403,
          '본인인증이 필요합니다. 앱에서 본인인증을 완료해주세요.',
        ).toJSON(),
      );
  }
}
