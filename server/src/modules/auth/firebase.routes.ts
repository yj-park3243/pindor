import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AuthService } from './auth.service.js';
import {
  firebaseSignupSchema,
  firebaseLoginSchema,
  type FirebaseSignupDto,
  type FirebaseLoginDto,
} from './auth.schema.js';
import { AppDataSource } from '../../config/database.js';
import { authRateLimitConfig } from '../../shared/middleware/rate-limit.js';

export async function firebaseAuthRoutes(fastify: FastifyInstance): Promise<void> {
  const authService = new AuthService(AppDataSource);

  // ─── POST /auth/firebase/signup ───
  fastify.post(
    '/auth/firebase/signup',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: 'Firebase 이메일 회원가입',
        body: {
          type: 'object',
          required: ['idToken'],
          properties: {
            idToken: { type: 'string' },
            agreedTerms: { type: 'boolean' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: FirebaseSignupDto }>, reply: FastifyReply) => {
      const dto = firebaseSignupSchema.parse(request.body);
      const result = await authService.firebaseSignup(dto);
      return reply.status(201).send({ success: true, data: result });
    },
  );

  // ─── POST /auth/firebase/login ───
  fastify.post(
    '/auth/firebase/login',
    {
      ...authRateLimitConfig,
      schema: {
        tags: ['Auth'],
        summary: 'Firebase 이메일 로그인',
        body: {
          type: 'object',
          required: ['idToken'],
          properties: {
            idToken: { type: 'string' },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: FirebaseLoginDto }>, reply: FastifyReply) => {
      const dto = firebaseLoginSchema.parse(request.body);
      const result = await authService.firebaseLogin(dto);
      return reply.status(200).send({ success: true, data: result });
    },
  );
}
