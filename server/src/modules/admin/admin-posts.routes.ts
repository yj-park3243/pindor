import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Post, Comment, PostCategory } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminPostsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/posts ── 게시글 목록
  fastify.get(
    '/admin/posts',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '게시글 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          category?: string;
          pinId?: string;
          search?: string;
          page?: number;
          pageSize?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { category, pinId, search } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const postRepo = AppDataSource.getRepository(Post);
      const qb = postRepo
        .createQueryBuilder('post')
        .leftJoinAndSelect('post.author', 'author')
        .leftJoinAndSelect('post.pin', 'pin');

      if (category) {
        qb.andWhere('post.category = :category', { category: category as PostCategory });
      }
      if (pinId) {
        qb.andWhere('post.pinId = :pinId', { pinId });
      }
      if (search) {
        qb.andWhere('(post.title ILIKE :search OR post.content ILIKE :search)', {
          search: `%${search}%`,
        });
      }

      const [items, total] = await qb
        .orderBy('post.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/posts/:postId/comments ── 게시글 댓글 목록
  // NOTE: 구체적 경로를 파라미터 경로보다 먼저 등록
  fastify.get(
    '/admin/posts/:postId/comments',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '게시글 댓글 목록',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { postId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { postId: string } }>,
      reply: FastifyReply,
    ) => {
      const { postId } = request.params;

      const commentRepo = AppDataSource.getRepository(Comment);
      const comments = await commentRepo
        .createQueryBuilder('comment')
        .leftJoinAndSelect('comment.author', 'author')
        .where('comment.postId = :postId', { postId })
        .orderBy('comment.createdAt', 'ASC')
        .getMany();

      return reply.send({ success: true, data: comments });
    },
  );

  // ─── DELETE /admin/posts/:postId/comments/:commentId ── 댓글 삭제
  fastify.delete(
    '/admin/posts/:postId/comments/:commentId',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '댓글 삭제 (소프트)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            postId: { type: 'string', format: 'uuid' },
            commentId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { postId: string; commentId: string };
        Body: { reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { postId, commentId } = request.params;

      const commentRepo = AppDataSource.getRepository(Comment);
      const postRepo = AppDataSource.getRepository(Post);

      const comment = await commentRepo.findOne({
        where: { id: commentId, postId },
      });
      if (!comment) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '댓글을 찾을 수 없습니다.');
      }

      await AppDataSource.transaction(async (manager) => {
        await manager.getRepository(Comment).update(commentId, { isDeleted: true });
        await manager
          .getRepository(Post)
          .createQueryBuilder()
          .update()
          .set({ commentCount: () => 'comment_count - 1' })
          .where('id = :postId AND comment_count > 0', { postId })
          .execute();
      });

      return reply.send({ success: true, data: { message: '댓글이 삭제되었습니다.' } });
    },
  );

  // ─── PATCH /admin/posts/:postId/comments/:commentId/blind ── 댓글 블라인드
  fastify.patch(
    '/admin/posts/:postId/comments/:commentId/blind',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '댓글 블라인드',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            postId: { type: 'string', format: 'uuid' },
            commentId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { postId: string; commentId: string };
        Body: { reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { postId, commentId } = request.params;

      const commentRepo = AppDataSource.getRepository(Comment);
      const comment = await commentRepo.findOne({ where: { id: commentId, postId } });
      if (!comment) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '댓글을 찾을 수 없습니다.');
      }

      await commentRepo.update(commentId, { isDeleted: true });
      const updated = await commentRepo.findOne({ where: { id: commentId } });

      return reply.send({ success: true, data: updated });
    },
  );

  // ─── GET /admin/posts/:id ── 게시글 상세
  fastify.get(
    '/admin/posts/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '게시글 상세',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const postRepo = AppDataSource.getRepository(Post);
      const post = await postRepo
        .createQueryBuilder('post')
        .leftJoinAndSelect('post.author', 'author')
        .leftJoinAndSelect('post.pin', 'pin')
        .where('post.id = :id', { id: request.params.id })
        .getOne();

      if (!post) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '게시글을 찾을 수 없습니다.');
      }

      return reply.send({ success: true, data: post });
    },
  );

  // ─── DELETE /admin/posts/:id ── 게시글 삭제 (소프트)
  fastify.delete(
    '/admin/posts/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '게시글 삭제 (소프트)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const postRepo = AppDataSource.getRepository(Post);
      const post = await postRepo.findOne({ where: { id: request.params.id } });
      if (!post) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '게시글을 찾을 수 없습니다.');
      }

      await postRepo.update(request.params.id, { isDeleted: true });

      return reply.send({ success: true, data: { message: '게시글이 삭제되었습니다.' } });
    },
  );

  // ─── PATCH /admin/posts/:id/blind ── 게시글 블라인드
  fastify.patch(
    '/admin/posts/:id/blind',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '게시글 블라인드',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const postRepo = AppDataSource.getRepository(Post);
      const post = await postRepo.findOne({ where: { id: request.params.id } });
      if (!post) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '게시글을 찾을 수 없습니다.');
      }

      await postRepo.update(request.params.id, { isDeleted: true });
      const updated = await postRepo
        .createQueryBuilder('post')
        .leftJoinAndSelect('post.author', 'author')
        .leftJoinAndSelect('post.pin', 'pin')
        .where('post.id = :id', { id: request.params.id })
        .getOne();

      return reply.send({ success: true, data: updated });
    },
  );

  // ─── PATCH /admin/posts/:id/unblind ── 게시글 블라인드 해제
  fastify.patch(
    '/admin/posts/:id/unblind',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '게시글 블라인드 해제',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const postRepo = AppDataSource.getRepository(Post);
      const post = await postRepo.findOne({ where: { id: request.params.id } });
      if (!post) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '게시글을 찾을 수 없습니다.');
      }

      await postRepo.update(request.params.id, { isDeleted: false });
      const updated = await postRepo
        .createQueryBuilder('post')
        .leftJoinAndSelect('post.author', 'author')
        .leftJoinAndSelect('post.pin', 'pin')
        .where('post.id = :id', { id: request.params.id })
        .getOne();

      return reply.send({ success: true, data: updated });
    },
  );
}
