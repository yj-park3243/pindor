import { z } from 'zod';

export const submitGameResultSchema = z.object({
  myScore: z.number().int().min(0, '점수는 0 이상이어야 합니다.'),
  opponentScore: z.number().int().min(0, '점수는 0 이상이어야 합니다.'),
  claimedResult: z.enum(['WIN', 'LOSS', 'DRAW']).optional(),
  winnerId: z.string().uuid('올바른 스포츠 프로필 ID가 아닙니다.').optional(),
  playedAt: z.string().datetime().optional(),
  venueName: z.string().max(255).optional(),
  scoreData: z.record(z.unknown()).optional(),
  mannerScore: z.number().int().min(1).max(5).optional(),
  verificationCode: z.string().length(4, '인증번호는 4자리여야 합니다.'),
});

export const confirmGameResultSchema = z.object({
  isConfirmed: z.boolean(),
  comment: z.string().max(500).optional(),
});

export const disputeGameResultSchema = z.object({
  reason: z.string().min(10, '이의 신청 사유를 10자 이상 입력해 주세요.').max(1000),
  evidenceImageUrls: z.array(z.string().url()).max(5).optional(),
});

export const listGamesQuerySchema = z.object({
  status: z
    .enum(['PENDING', 'PROOF_UPLOADED', 'VERIFIED', 'DISPUTED', 'VOIDED'])
    .optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

export type SubmitGameResultDto = z.infer<typeof submitGameResultSchema>;
export type ConfirmGameResultDto = z.infer<typeof confirmGameResultSchema>;
export type DisputeGameResultDto = z.infer<typeof disputeGameResultSchema>;
export type ListGamesQuery = z.infer<typeof listGamesQuerySchema>;
