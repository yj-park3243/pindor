import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { UserBlock, User } from '../../entities/index.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

export async function blocksRoutes(fastify: FastifyInstance): Promise<void> {
  const blockRepo = AppDataSource.getRepository(UserBlock);
  const userRepo = AppDataSource.getRepository(User);

  // POST /users/blocks - 유저 차단
  fastify.post('/users/blocks', {
    onRequest: [fastify.authenticate],
    schema: {
      tags: ['Users'],
      summary: '유저 차단',
      body: {
        type: 'object',
        required: ['blockedUserId'],
        properties: { blockedUserId: { type: 'string', format: 'uuid' } },
      },
    },
  }, async (request: FastifyRequest<{ Body: { blockedUserId: string } }>, reply: FastifyReply) => {
    const userId = request.user.userId;
    const { blockedUserId } = request.body;

    if (userId === blockedUserId) {
      throw AppError.badRequest(ErrorCode.VALIDATION_ERROR, '자기 자신을 차단할 수 없습니다.');
    }

    const targetUser = await userRepo.findOne({ where: { id: blockedUserId } });
    if (!targetUser) throw AppError.notFound(ErrorCode.USER_NOT_FOUND);

    const existing = await blockRepo.findOne({ where: { blockerId: userId, blockedId: blockedUserId } });
    if (existing) {
      return reply.status(200).send({ success: true, data: { message: '이미 차단된 유저입니다.' } });
    }

    await blockRepo.save(blockRepo.create({ blockerId: userId, blockedId: blockedUserId }));
    return reply.status(201).send({ success: true, data: { message: '차단되었습니다.' } });
  });

  // DELETE /users/blocks/:userId - 차단 해제
  fastify.delete('/users/blocks/:userId', {
    onRequest: [fastify.authenticate],
    schema: {
      tags: ['Users'],
      summary: '차단 해제',
      params: { type: 'object', properties: { userId: { type: 'string' } } },
    },
  }, async (request: FastifyRequest<{ Params: { userId: string } }>, reply: FastifyReply) => {
    const blockerId = request.user.userId;
    const blockedId = request.params.userId;

    await blockRepo.delete({ blockerId, blockedId });
    return reply.status(200).send({ success: true, data: { message: '차단이 해제되었습니다.' } });
  });

  // GET /users/blocks - 차단 목록
  fastify.get('/users/blocks', {
    onRequest: [fastify.authenticate],
    schema: { tags: ['Users'], summary: '차단 목록 조회' },
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const userId = request.user.userId;

    const blocks = await blockRepo.find({
      where: { blockerId: userId },
      relations: { blocked: true },
      order: { createdAt: 'DESC' },
    });

    const data = blocks.map(b => ({
      id: b.blocked.id,
      nickname: b.blocked.nickname,
      profileImageUrl: b.blocked.profileImageUrl,
      blockedAt: b.createdAt,
    }));

    return reply.status(200).send({ success: true, data });
  });
}
