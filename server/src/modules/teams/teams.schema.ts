import { z } from 'zod';
import { SportType, TimeSlot, TeamRole, TeamPostCategory } from '../../entities/index.js';

// ─────────────────────────────────────
// 팀 생성
// ─────────────────────────────────────

export const createTeamSchema = z.object({
  name: z.string().min(2, '팀 이름은 최소 2자 이상이어야 합니다.').max(50, '팀 이름은 최대 50자입니다.'),
  sportType: z.nativeEnum(SportType),
  logoUrl: z.string().url('올바른 URL 형식이 아닙니다.').optional(),
  description: z.string().max(500, '설명은 최대 500자입니다.').optional(),
  homePinId: z.string().uuid('올바른 핀 ID 형식이 아닙니다.').optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  activityRegion: z.string().max(100).optional(),
  minMembers: z.number().int().min(2).max(50).default(3),
  maxMembers: z.number().int().min(2).max(50).default(11),
}).refine(
  (data) => data.minMembers <= data.maxMembers,
  { message: '최소 인원은 최대 인원보다 작거나 같아야 합니다.', path: ['minMembers'] },
);

// ─────────────────────────────────────
// 팀 수정
// ─────────────────────────────────────

export const updateTeamSchema = z.object({
  name: z.string().min(2).max(50).optional(),
  logoUrl: z.string().url().optional().nullable(),
  description: z.string().max(500).optional().nullable(),
  homePinId: z.string().uuid().optional().nullable(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  activityRegion: z.string().max(100).optional().nullable(),
  minMembers: z.number().int().min(2).max(50).optional(),
  maxMembers: z.number().int().min(2).max(50).optional(),
  isRecruiting: z.boolean().optional(),
});

// ─────────────────────────────────────
// 팀원 역할 변경
// ─────────────────────────────────────

export const changeRoleSchema = z.object({
  role: z.nativeEnum(TeamRole),
});

// ─────────────────────────────────────
// 팀 매칭 요청 생성
// ─────────────────────────────────────

export const createTeamMatchRequestSchema = z.object({
  desiredDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, '날짜 형식은 YYYY-MM-DD 입니다.')
    .optional(),
  desiredTimeSlot: z.nativeEnum(TimeSlot).optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  locationName: z.string().max(255).optional(),
  radiusKm: z.number().min(1).max(100).default(20),
  message: z.string().max(500).optional(),
});

// ─────────────────────────────────────
// 팀 경기 결과 입력
// ─────────────────────────────────────

export const submitTeamResultSchema = z.object({
  homeScore: z.number().int().min(0),
  awayScore: z.number().int().min(0),
  venueName: z.string().max(255).optional(),
  venueLatitude: z.number().min(-90).max(90).optional(),
  venueLongitude: z.number().min(-180).max(180).optional(),
});

// ─────────────────────────────────────
// 팀 게시글 생성
// ─────────────────────────────────────

export const createTeamPostSchema = z.object({
  category: z.nativeEnum(TeamPostCategory).default('FREE'),
  title: z.string().min(1, '제목을 입력해 주세요.').max(100, '제목은 최대 100자입니다.'),
  content: z.string().min(1, '내용을 입력해 주세요.').max(5000, '내용은 최대 5000자입니다.'),
  isPinned: z.boolean().optional().default(false),
});

// ─────────────────────────────────────
// 팀 게시글 수정
// ─────────────────────────────────────

export const updateTeamPostSchema = z.object({
  category: z.nativeEnum(TeamPostCategory).optional(),
  title: z.string().min(1).max(100).optional(),
  content: z.string().min(1).max(5000).optional(),
  isPinned: z.boolean().optional(),
});

// ─────────────────────────────────────
// 팀 게시글 댓글 생성
// ─────────────────────────────────────

export const createTeamPostCommentSchema = z.object({
  content: z.string().min(1, '댓글 내용을 입력해 주세요.').max(500, '댓글은 최대 500자입니다.'),
  parentId: z.string().uuid().optional(),
});

// ─────────────────────────────────────
// 팀 검색 쿼리
// ─────────────────────────────────────

export const searchTeamsQuerySchema = z.object({
  q: z.string().min(1).max(50).optional(),
  sportType: z.nativeEnum(SportType).optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

export const nearbyTeamsQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  radiusKm: z.coerce.number().min(1).max(100).default(20),
  sportType: z.nativeEnum(SportType).optional(),
});

// ─────────────────────────────────────
// 게시글 목록 쿼리
// ─────────────────────────────────────

export const listTeamPostsQuerySchema = z.object({
  category: z.nativeEnum(TeamPostCategory).optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

// ─────────────────────────────────────
// 채팅 메시지 목록 쿼리
// ─────────────────────────────────────

export const getTeamMessagesQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(100).default(50),
});

// ─────────────────────────────────────
// 타입 추출
// ─────────────────────────────────────

export type CreateTeamDto = z.infer<typeof createTeamSchema>;
export type UpdateTeamDto = z.infer<typeof updateTeamSchema>;
export type ChangeRoleDto = z.infer<typeof changeRoleSchema>;
export type CreateTeamMatchRequestDto = z.infer<typeof createTeamMatchRequestSchema>;
export type SubmitTeamResultDto = z.infer<typeof submitTeamResultSchema>;
export type CreateTeamPostDto = z.infer<typeof createTeamPostSchema>;
export type UpdateTeamPostDto = z.infer<typeof updateTeamPostSchema>;
export type CreateTeamPostCommentDto = z.infer<typeof createTeamPostCommentSchema>;
export type SearchTeamsQuery = z.infer<typeof searchTeamsQuerySchema>;
export type NearbyTeamsQuery = z.infer<typeof nearbyTeamsQuerySchema>;
export type ListTeamPostsQuery = z.infer<typeof listTeamPostsQuerySchema>;
export type GetTeamMessagesQuery = z.infer<typeof getTeamMessagesQuerySchema>;
