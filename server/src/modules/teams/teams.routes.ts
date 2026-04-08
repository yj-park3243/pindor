import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { TeamsService } from './teams.service.js';
import {
  createTeamSchema,
  updateTeamSchema,
  changeRoleSchema,
  createTeamMatchRequestSchema,
  submitTeamResultSchema,
  createTeamPostSchema,
  updateTeamPostSchema,
  createTeamPostCommentSchema,
  searchTeamsQuerySchema,
  nearbyTeamsQuerySchema,
  listTeamPostsQuerySchema,
  getTeamMessagesQuerySchema,
  type CreateTeamDto,
  type UpdateTeamDto,
  type ChangeRoleDto,
  type CreateTeamMatchRequestDto,
  type SubmitTeamResultDto,
  type CreateTeamPostDto,
  type UpdateTeamPostDto,
  type CreateTeamPostCommentDto,
  type SearchTeamsQuery,
  type NearbyTeamsQuery,
  type ListTeamPostsQuery,
  type GetTeamMessagesQuery,
} from './teams.schema.js';
export async function teamsRoutes(fastify: FastifyInstance): Promise<void> {
  const teamsService = new TeamsService();

  // ═══════════════════════════════════════
  // 팀 CRUD
  // ═══════════════════════════════════════

  // ─── POST /teams ───
  fastify.post(
    '/teams',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 생성',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: CreateTeamDto }>,
      reply: FastifyReply,
    ) => {
      const dto = createTeamSchema.parse(request.body);
      const data = await teamsService.createTeam(request.user.userId, dto);
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── GET /teams/nearby ───
  // (/:id 보다 먼저 등록해야 'nearby'가 id로 파싱되지 않음)
  fastify.get(
    '/teams/nearby',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '주변 팀 조회 (PostGIS)',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            lat: { type: 'number' },
            lng: { type: 'number' },
            radiusKm: { type: 'number' },
            sportType: { type: 'string' },
          },
          required: ['lat', 'lng'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Querystring: NearbyTeamsQuery }>,
      reply: FastifyReply,
    ) => {
      const query = nearbyTeamsQuerySchema.parse(request.query);
      const data = await teamsService.getNearbyTeams(query);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /teams/search ───
  fastify.get(
    '/teams/search',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 검색',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: {
            q: { type: 'string' },
            sportType: { type: 'string' },
            cursor: { type: 'string' },
            limit: { type: 'integer' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Querystring: SearchTeamsQuery }>,
      reply: FastifyReply,
    ) => {
      const query = searchTeamsQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await teamsService.searchTeams(query);
      return reply.send({
        success: true,
        data: items,
        meta: { cursor: nextCursor, hasMore },
      });
    },
  );

  // ─── GET /teams/:id ───
  fastify.get(
    '/teams/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 상세 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.getTeam(request.params.id);
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /teams/:id ───
  fastify.patch(
    '/teams/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 정보 수정 (캡틴 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: UpdateTeamDto }>,
      reply: FastifyReply,
    ) => {
      const dto = updateTeamSchema.parse(request.body);
      const data = await teamsService.updateTeam(request.user.userId, request.params.id, dto);
      return reply.send({ success: true, data });
    },
  );

  // ─── DELETE /teams/:id ───
  fastify.delete(
    '/teams/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 해산 (캡틴 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      await teamsService.disbandTeam(request.user.userId, request.params.id);
      return reply.send({ success: true, data: { message: '팀이 해산되었습니다.' } });
    },
  );

  // ═══════════════════════════════════════
  // 팀원 관리
  // ═══════════════════════════════════════

  // ─── GET /teams/:id/members ───
  fastify.get(
    '/teams/:id/members',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀원 목록 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.getTeamMembers(request.params.id);
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /teams/:id/members/join ───
  fastify.post(
    '/teams/:id/members/join',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 가입 신청',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.joinTeam(request.user.userId, request.params.id);
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── POST /teams/:id/members/:userId/kick ───
  fastify.post(
    '/teams/:id/members/:userId/kick',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀원 추방 (캡틴 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
            userId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string; userId: string } }>,
      reply: FastifyReply,
    ) => {
      await teamsService.kickMember(
        request.user.userId,
        request.params.id,
        request.params.userId,
      );
      return reply.send({ success: true, data: { message: '팀원을 추방했습니다.' } });
    },
  );

  // ─── PATCH /teams/:id/members/:userId/role ───
  fastify.patch(
    '/teams/:id/members/:userId/role',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀원 역할 변경 (캡틴 전용) — 방장 양도, 부방장 임명/해임',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
            userId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string; userId: string }; Body: ChangeRoleDto }>,
      reply: FastifyReply,
    ) => {
      const dto = changeRoleSchema.parse(request.body);
      await teamsService.changeRole(
        request.user.userId,
        request.params.id,
        request.params.userId,
        dto,
      );
      return reply.send({ success: true, data: { message: '역할이 변경되었습니다.' } });
    },
  );

  // ─── DELETE /teams/:id/members/me ───
  fastify.delete(
    '/teams/:id/members/me',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Teams'],
        summary: '팀 탈퇴',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      await teamsService.leaveTeam(request.user.userId, request.params.id);
      return reply.send({ success: true, data: { message: '팀을 탈퇴했습니다.' } });
    },
  );

  // ═══════════════════════════════════════
  // 팀 매칭
  // ═══════════════════════════════════════

  // ─── POST /team-matches/requests ───
  fastify.post(
    '/team-matches/requests',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamMatches'],
        summary: '팀 매칭 요청 생성 (캡틴/부캡틴 전용)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: CreateTeamMatchRequestDto & { teamId: string } }>,
      reply: FastifyReply,
    ) => {
      const { teamId, ...rest } = request.body as any;
      const dto = createTeamMatchRequestSchema.parse(rest);
      const data = await teamsService.createTeamMatchRequest(
        request.user.userId,
        teamId,
        dto,
      );
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── DELETE /team-matches/requests/:id ───
  fastify.delete(
    '/team-matches/requests/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamMatches'],
        summary: '팀 매칭 요청 취소',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      await teamsService.cancelTeamMatchRequest(request.user.userId, request.params.id);
      return reply.send({ success: true, data: { message: '팀 매칭 요청이 취소되었습니다.' } });
    },
  );

  // ─── GET /team-matches ───
  fastify.get(
    '/team-matches',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamMatches'],
        summary: '팀 매칭 목록 조회',
        security: [{ bearerAuth: [] }],
        querystring: {
          type: 'object',
          properties: { teamId: { type: 'string', format: 'uuid' } },
          required: ['teamId'],
        },
      },
    },
    async (
      request: FastifyRequest<{ Querystring: { teamId: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.getTeamMatches(
        request.user.userId,
        request.query.teamId,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /team-matches/:id ───
  fastify.get(
    '/team-matches/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamMatches'],
        summary: '팀 매칭 상세 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.getTeamMatch(request.user.userId, request.params.id);
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /team-matches/:id/confirm ───
  fastify.patch(
    '/team-matches/:id/confirm',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamMatches'],
        summary: '팀 매칭 확정 (홈팀 캡틴/부캡틴 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.confirmTeamMatch(
        request.user.userId,
        request.params.id,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── POST /team-matches/:id/result ───
  fastify.post(
    '/team-matches/:id/result',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamMatches'],
        summary: '팀 경기 결과 입력 (캡틴/부캡틴 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: SubmitTeamResultDto }>,
      reply: FastifyReply,
    ) => {
      const dto = submitTeamResultSchema.parse(request.body);
      const data = await teamsService.submitTeamResult(
        request.user.userId,
        request.params.id,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ═══════════════════════════════════════
  // 팀 채팅
  // ═══════════════════════════════════════

  // ─── GET /team-chat-rooms ───
  fastify.get(
    '/team-chat-rooms',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamChat'],
        summary: '팀 채팅방 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const data = await teamsService.getTeamChatRooms(request.user.userId);
      return reply.send({ success: true, data });
    },
  );

  // ─── GET /team-chat-rooms/:id/messages ───
  fastify.get(
    '/team-chat-rooms/:id/messages',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamChat'],
        summary: '팀 채팅 메시지 목록',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
        querystring: {
          type: 'object',
          properties: {
            cursor: { type: 'string' },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 50 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Querystring: GetTeamMessagesQuery }>,
      reply: FastifyReply,
    ) => {
      const query = getTeamMessagesQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await teamsService.getTeamChatMessages(
        request.user.userId,
        request.params.id,
        query,
      );
      return reply.send({
        success: true,
        data: items,
        meta: { cursor: nextCursor, hasMore },
      });
    },
  );

  // ═══════════════════════════════════════
  // 팀 게시판
  // ═══════════════════════════════════════

  // ─── GET /teams/:id/posts ───
  fastify.get(
    '/teams/:id/posts',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamPosts'],
        summary: '팀 게시글 목록',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
        querystring: {
          type: 'object',
          properties: {
            category: { type: 'string' },
            cursor: { type: 'string' },
            limit: { type: 'integer' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Querystring: ListTeamPostsQuery }>,
      reply: FastifyReply,
    ) => {
      const query = listTeamPostsQuerySchema.parse(request.query);
      const { items, nextCursor, hasMore } = await teamsService.getTeamPosts(
        request.params.id,
        query,
      );
      return reply.send({
        success: true,
        data: items,
        meta: { cursor: nextCursor, hasMore },
      });
    },
  );

  // ─── POST /teams/:id/posts ───
  fastify.post(
    '/teams/:id/posts',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamPosts'],
        summary: '팀 게시글 작성',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: CreateTeamPostDto }>,
      reply: FastifyReply,
    ) => {
      const dto = createTeamPostSchema.parse(request.body);
      const data = await teamsService.createTeamPost(
        request.user.userId,
        request.params.id,
        dto,
      );
      return reply.status(201).send({ success: true, data });
    },
  );

  // ─── GET /teams/:id/posts/:postId ───
  fastify.get(
    '/teams/:id/posts/:postId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamPosts'],
        summary: '팀 게시글 상세 조회',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string; postId: string } }>,
      reply: FastifyReply,
    ) => {
      const data = await teamsService.getTeamPost(request.params.id, request.params.postId);
      return reply.send({ success: true, data });
    },
  );

  // ─── PATCH /teams/:id/posts/:postId ───
  fastify.patch(
    '/teams/:id/posts/:postId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamPosts'],
        summary: '팀 게시글 수정 (작성자 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string; postId: string }; Body: UpdateTeamPostDto }>,
      reply: FastifyReply,
    ) => {
      const dto = updateTeamPostSchema.parse(request.body);
      const data = await teamsService.updateTeamPost(
        request.user.userId,
        request.params.id,
        request.params.postId,
        dto,
      );
      return reply.send({ success: true, data });
    },
  );

  // ─── DELETE /teams/:id/posts/:postId ───
  fastify.delete(
    '/teams/:id/posts/:postId',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamPosts'],
        summary: '팀 게시글 삭제 (작성자 또는 캡틴 전용)',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string; postId: string } }>,
      reply: FastifyReply,
    ) => {
      await teamsService.deleteTeamPost(
        request.user.userId,
        request.params.id,
        request.params.postId,
      );
      return reply.send({ success: true, data: { message: '게시글이 삭제되었습니다.' } });
    },
  );

  // ─── POST /teams/:id/posts/:postId/comments ───
  fastify.post(
    '/teams/:id/posts/:postId/comments',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['TeamPosts'],
        summary: '팀 게시글 댓글 작성',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string; postId: string };
        Body: CreateTeamPostCommentDto;
      }>,
      reply: FastifyReply,
    ) => {
      const dto = createTeamPostCommentSchema.parse(request.body);
      const data = await teamsService.createTeamPostComment(
        request.user.userId,
        request.params.id,
        request.params.postId,
        dto,
      );
      return reply.status(201).send({ success: true, data });
    },
  );
}
