import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AuthService } from './auth.service.js';
import {
  kakaoLoginSchema,
  googleLoginSchema,
  appleLoginSchema,
  emailRegisterSchema,
  emailLoginSchema,
  refreshTokenSchema,
  logoutSchema,
  type KakaoLoginDto,
  type GoogleLoginDto,
  type AppleLoginDto,
  type EmailRegisterDto,
  type EmailLoginDto,
  type RefreshTokenDto,
  type LogoutDto,
} from './auth.schema.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { authRateLimitConfig } from '../../shared/middleware/rate-limit.js';

export async function authRoutes(fastify: FastifyInstance): Promise<void> {
  const authService = new AuthService(AppDataSource);

  // ─── POST /auth/kakao ───
  fastify.post(
    '/auth/kakao',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: '카카오 소셜 로그인',
        body: {
          type: 'object',
          required: ['accessToken'],
          properties: {
            accessToken: { type: 'string' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: KakaoLoginDto }>, reply: FastifyReply) => {
      const dto = kakaoLoginSchema.parse(request.body);
      const result = await authService.kakaoLogin(dto);

      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  // ─── POST /auth/google ───
  fastify.post(
    '/auth/google',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: 'Google 소셜 로그인',
        body: {
          type: 'object',
          required: ['idToken'],
          properties: {
            idToken: { type: 'string' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: GoogleLoginDto }>, reply: FastifyReply) => {
      const dto = googleLoginSchema.parse(request.body);
      const result = await authService.googleLogin(dto);

      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  // ─── POST /auth/apple ───
  fastify.post(
    '/auth/apple',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: 'Apple 소셜 로그인',
        body: {
          type: 'object',
          required: ['identityToken', 'authorizationCode'],
          properties: {
            identityToken: { type: 'string' },
            authorizationCode: { type: 'string' },
            email: { type: 'string' },
            fullName: { type: 'string' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: AppleLoginDto }>, reply: FastifyReply) => {
      const dto = appleLoginSchema.parse(request.body);
      const result = await authService.appleLogin(dto);

      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  // ─── POST /auth/email/register ───
  fastify.post(
    '/auth/email/register',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: '이메일 회원가입',
        body: {
          type: 'object',
          required: ['email', 'password'],
          properties: {
            email: { type: 'string', format: 'email' },
            password: { type: 'string', minLength: 6 },
            nickname: { type: 'string', minLength: 2, maxLength: 20 },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: EmailRegisterDto }>, reply: FastifyReply) => {
      const dto = emailRegisterSchema.parse(request.body);
      const result = await authService.emailRegister(dto);
      return reply.status(201).send({ success: true, data: result });
    },
  );

  // ─── POST /auth/email/login ───
  fastify.post(
    '/auth/email/login',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: '이메일 로그인',
        body: {
          type: 'object',
          required: ['email', 'password'],
          properties: {
            email: { type: 'string', format: 'email' },
            password: { type: 'string' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: EmailLoginDto }>, reply: FastifyReply) => {
      const dto = emailLoginSchema.parse(request.body);
      const result = await authService.emailLogin(dto);
      return reply.status(200).send({ success: true, data: result });
    },
  );

  // ─── POST /auth/refresh ───
  fastify.post(
    '/auth/refresh',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: '액세스 토큰 갱신',
        body: {
          type: 'object',
          required: ['refreshToken'],
          properties: {
            refreshToken: { type: 'string' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: RefreshTokenDto }>, reply: FastifyReply) => {
      const dto = refreshTokenSchema.parse(request.body);
      const tokens = await authService.refreshToken(dto.refreshToken);

      return reply.status(200).send({
        success: true,
        data: tokens,
      });
    },
  );

  // ─── POST /auth/logout ───
  fastify.post(
    '/auth/logout',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Auth'],
        summary: '로그아웃',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: LogoutDto }>, reply: FastifyReply) => {
      const dto = logoutSchema.parse(request.body ?? {});
      await authService.logout(request.user.userId, dto.pushToken);

      return reply.status(200).send({
        success: true,
        data: { message: '로그아웃 되었습니다.' },
      });
    },
  );
}
