import { FastifyRequest, FastifyReply } from 'fastify';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { AppDataSource } from '../../config/database.js';
import { AdminProfile, AdminRole } from '../../entities/index.js';

/**
 * 어드민 역할 검증 미들웨어
 * 사용법: onRequest: [fastify.authenticate, requireAdmin()]
 */
export function requireAdmin(minRole: AdminRole = AdminRole.MODERATOR) {
  return async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const userId = request.user?.userId;

    if (!userId) {
      throw AppError.unauthorized();
    }

    const adminProfileRepo = AppDataSource.getRepository(AdminProfile);
    const adminProfile = await adminProfileRepo.findOne({ where: { userId } });

    if (!adminProfile) {
      throw AppError.forbidden(ErrorCode.ADMIN_ACCESS_DENIED);
    }

    const roleOrder: AdminRole[] = [
      AdminRole.MODERATOR,
      AdminRole.ADMIN,
      AdminRole.SUPER_ADMIN,
    ];

    const adminRoleIndex = roleOrder.indexOf(adminProfile.role);
    const requiredRoleIndex = roleOrder.indexOf(minRole);

    if (adminRoleIndex < requiredRoleIndex) {
      throw AppError.forbidden(
        ErrorCode.ADMIN_INVALID_ROLE,
        `${minRole} 이상의 권한이 필요합니다.`,
      );
    }

    // 요청 객체에 어드민 역할 저장
    (request as any).adminRole = adminProfile.role;
  };
}
