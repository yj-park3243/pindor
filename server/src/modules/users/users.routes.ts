import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { UsersService } from './users.service.js';
import {
  updateUserSchema,
  updateLocationSchema,
  deleteUserSchema,
  type UpdateUserDto,
  type UpdateLocationDto,
  type DeleteUserDto,
} from './users.schema.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { optionalAuth } from '../../shared/middleware/auth.middleware.js';

export async function usersRoutes(fastify: FastifyInstance): Promise<void> {
  const usersService = new UsersService(AppDataSource);

  // ─── GET /users/check-nickname ───
  fastify.get(
    '/users/check-nickname',
    {
      onRequest: [optionalAuth],
      schema: {
        tags: ['Users'],
        summary: '닉네임 중복 확인',
        querystring: {
          type: 'object',
          properties: { nickname: { type: 'string' } },
          required: ['nickname'],
        },
      },
    },
    async (request: FastifyRequest<{ Querystring: { nickname: string } }>, reply: FastifyReply) => {
      const { nickname } = request.query;
      const userId = request.user?.userId;
      const isAvailable = await usersService.checkNickname(nickname, userId);
      return reply.send({ success: true, data: { available: isAvailable } });
    },
  );

  // ─── GET /users/me ───
  fastify.get(
    '/users/me',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Users'],
        summary: '내 정보 조회',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const data = await usersService.getMe(request.user.userId);
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /users/me ───
  fastify.patch(
    '/users/me',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Users'],
        summary: '내 정보 수정',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: UpdateUserDto }>, reply: FastifyReply) => {
      const dto = updateUserSchema.parse(request.body);
      const data = await usersService.updateMe(request.user.userId, dto);
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /users/me/location ───
  fastify.post(
    '/users/me/location',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Users'],
        summary: '활동 지역 설정',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: UpdateLocationDto }>, reply: FastifyReply) => {
      const dto = updateLocationSchema.parse(request.body);
      const data = await usersService.updateLocation(request.user.userId, dto);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /users/batch ── (배치 조회: ids 쿼리 파라미터)
  fastify.get(
    '/users/batch',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Users'],
        summary: '사용자 배치 조회 (ids)',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            ids: { type: 'string', description: '콤마 구분 사용자 ID 목록' },
          },
          required: ['ids'],
        },
      },
    },
    async (request: FastifyRequest<{ Querystring: { ids: string } }>, reply: FastifyReply) => {
      const ids = request.query.ids.split(',').map((id) => id.trim()).filter(Boolean);
      if (ids.length === 0 || ids.length > 50) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'ids는 1~50개까지 가능합니다.' },
        });
      }
      const data = await usersService.getUsersByIds(ids);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /users/:id/profile ───
  fastify.get(
    '/users/:id/profile',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Users'],
        summary: '타 사용자 프로필 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const data = await usersService.getUserProfile(
        request.params.id,
        request.user.userId,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── DELETE /users/me ───
  fastify.delete(
    '/users/me',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Users'],
        summary: '회원 탈퇴',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: DeleteUserDto }>, reply: FastifyReply) => {
      const dto = deleteUserSchema.parse(request.body ?? {});
      await usersService.deleteMe(request.user.userId);
      return reply.status(200).send({
        success: true,
        data: { message: '탈퇴 처리가 완료되었습니다.' },
      });
    },
  );
}
