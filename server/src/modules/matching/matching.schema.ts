import { z } from 'zod';
import { SportType, TimeSlot, RequestType } from '../../entities/index.js';

export const createMatchRequestSchema = z.object({
  sportType: z.nativeEnum(SportType),
  requestType: z.nativeEnum(RequestType).default(RequestType.SCHEDULED),
  desiredDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, '날짜 형식은 YYYY-MM-DD 입니다.')
    .optional(),
  desiredTimeSlot: z.nativeEnum(TimeSlot).optional(),
  pinId: z.string().uuid(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  locationName: z.string().max(255).optional(),
  minOpponentScore: z.number().min(100).max(3000).default(800),
  maxOpponentScore: z.number().min(100).max(3000).default(1200),
  genderPreference: z.enum(['SAME', 'ANY']).default('ANY'),
  minAge: z.number().int().min(14).max(100).optional(),
  maxAge: z.number().int().min(14).max(100).optional(),
  ageRange: z.number().int().min(0).max(10).optional(),
  message: z.string().max(500).optional(),
  isCasual: z.boolean().optional().default(false),
}).refine(
  (data) => data.minOpponentScore <= data.maxOpponentScore,
  { message: '최소 점수는 최대 점수보다 작거나 같아야 합니다.', path: ['minOpponentScore'] },
).refine(
  (data) => {
    if (data.minAge !== undefined && data.maxAge !== undefined) {
      return data.minAge <= data.maxAge;
    }
    return true;
  },
  { message: '최소 나이는 최대 나이보다 작거나 같아야 합니다.', path: ['minAge'] },
);

export const instantMatchSchema = z.object({
  sportType: z.nativeEnum(SportType),
  pinId: z.string().uuid(),
  availableUntil: z.string().datetime({ message: '올바른 ISO 8601 날짜 형식이 아닙니다.' }),
});

export const listMatchRequestsQuerySchema = z.object({
  status: z.enum(['WAITING', 'MATCHED', 'CANCELLED', 'EXPIRED']).optional(),
  sportType: z.nativeEnum(SportType).optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

export const listMatchesQuerySchema = z.object({
  status: z.enum(['PENDING_ACCEPT', 'CHAT', 'CONFIRMED', 'COMPLETED', 'CANCELLED', 'DISPUTED']).optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

export const confirmMatchSchema = z.object({
  scheduledDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  scheduledTime: z
    .string()
    .regex(/^\d{2}:\d{2}$/)
    .optional(),
  venueName: z.string().max(255).optional(),
  venueLatitude: z.number().min(-90).max(90).optional(),
  venueLongitude: z.number().min(-180).max(180).optional(),
});

export const cancelMatchSchema = z.object({
  reason: z.string().max(500).optional(),
});

export type CreateMatchRequestDto = z.infer<typeof createMatchRequestSchema>;
export type InstantMatchDto = z.infer<typeof instantMatchSchema>;
export type ListMatchRequestsQuery = z.infer<typeof listMatchRequestsQuerySchema>;
export type ListMatchesQuery = z.infer<typeof listMatchesQuerySchema>;
export type ConfirmMatchDto = z.infer<typeof confirmMatchSchema>;
export type CancelMatchDto = z.infer<typeof cancelMatchSchema>;

// 매칭 수락/거절 스키마 (body 없음, matchId는 params에서)
export const acceptMatchParamsSchema = z.object({
  matchId: z.string().uuid('올바른 매칭 ID 형식이 아닙니다.'),
});

export const rejectMatchParamsSchema = z.object({
  matchId: z.string().uuid('올바른 매칭 ID 형식이 아닙니다.'),
});

export const getMatchStatusParamsSchema = z.object({
  matchId: z.string().uuid('올바른 매칭 ID 형식이 아닙니다.'),
});
