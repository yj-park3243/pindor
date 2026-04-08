import { FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { Match } from '../../entities/index.js';

/**
 * 해당 핀에서 1회 이상 매칭 완료한 유저만 게시글 작성 가능
 * GET 요청(조회)은 통과, POST/PATCH/DELETE만 체크
 */
export async function requirePinParticipation(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const userId = request.user?.userId;
  const pinId = (request.params as Record<string, string>)?.pinId;

  if (!userId || !pinId) {
    return reply.status(403).send({
      success: false,
      error: { code: 'PIN_ACCESS_DENIED', message: '핀 접근 권한이 없습니다.' },
    });
  }

  // Check if user has completed at least 1 match at this pin
  const matchRepo = AppDataSource.getRepository(Match);
  const count = await matchRepo
    .createQueryBuilder('match')
    .leftJoin('match.requesterProfile', 'rp')
    .leftJoin('match.opponentProfile', 'op')
    .where('match.pinId = :pinId', { pinId })
    .andWhere('match.status = :status', { status: 'COMPLETED' })
    .andWhere('(rp.userId = :userId OR op.userId = :userId)', { userId })
    .getCount();

  if (count === 0) {
    return reply.status(403).send({
      success: false,
      error: {
        code: 'PIN_PARTICIPATION_REQUIRED',
        message: '이 핀에서 1회 이상 매칭에 참가해야 게시글을 작성할 수 있습니다.',
      },
    });
  }
}
