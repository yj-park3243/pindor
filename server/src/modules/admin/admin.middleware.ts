import { FastifyRequest, FastifyReply } from 'fastify';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { AppDataSource } from '../../config/database.js';
import { AdminAccount, AdminRole } from '../../entities/index.js';

/**
 * 어드민 역할 검증 미들웨어 (독립 admin_accounts 테이블 기반)
 * 사용법: onRequest: [fastify.authenticate, requireAdmin()]
 */
export function requireAdmin(minRole: AdminRole = AdminRole.MODERATOR) {
  return async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const userId = request.user?.userId;

    if (!userId) {
      throw AppError.unauthorized();
    }

    const adminAccountRepo = AppDataSource.getRepository(AdminAccount);
    const account = await adminAccountRepo.findOne({ where: { id: userId } });

    if (!account || !account.isActive) {
      throw AppError.forbidden(ErrorCode.ADMIN_ACCESS_DENIED);
    }

    const roleOrder: AdminRole[] = [
      AdminRole.MODERATOR,
      AdminRole.ADMIN,
      AdminRole.SUPER_ADMIN,
    ];

    const adminRoleIndex = roleOrder.indexOf(account.role);
    const requiredRoleIndex = roleOrder.indexOf(minRole);

    if (adminRoleIndex < requiredRoleIndex) {
      throw AppError.forbidden(
        ErrorCode.ADMIN_INVALID_ROLE,
        `${minRole} 이상의 권한이 필요합니다.`,
      );
    }

    (request as any).adminRole = account.role;
  };
}
