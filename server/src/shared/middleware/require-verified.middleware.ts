import { FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { User } from '../../entities/index.js';
import { AppError, ErrorCode } from '../errors/app-error.js';

/**
 * 본인인증 완료 여부 확인 미들웨어
 * - `fastify.authenticate` 이후에 사용
 * - isVerified=false 인 유저는 403 + VERIFICATION_REQUIRED 반환
 */
export async function requireVerified(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
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
