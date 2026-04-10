import { z } from 'zod';
import { PostCategory, SportType } from '../../entities/index.js';

export const nearbyPinsQuerySchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(1).max(100).default(10),
});

export const listPostsQuerySchema = z.object({
  category: z.nativeEnum(PostCategory).optional(),
  sportType: z.nativeEnum(SportType).optional(),
  search: z.string().max(100).optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

export const createPostSchema = z.object({
  title: z.string().min(1, '제목을 입력해 주세요.').max(100, '제목은 최대 100자입니다.'),
  content: z
    .string()
    .min(1, '내용을 입력해 주세요.')
    .max(2000, '내용은 최대 2000자입니다.'),
  category: z.nativeEnum(PostCategory).default(PostCategory.GENERAL),
  sportType: z.nativeEnum(SportType).optional(),
  imageUrls: z.array(z.string().url()).max(5, '이미지는 최대 5장까지 첨부할 수 있습니다.').optional(),
});

export const updatePostSchema = z.object({
  title: z.string().min(1).max(100).optional(),
  content: z.string().min(1).max(2000).optional(),
  category: z.nativeEnum(PostCategory).optional(),
});

export const createCommentSchema = z.object({
  content: z.string().min(1, '댓글 내용을 입력해 주세요.').max(500),
  parentId: z.string().uuid().optional(),
});

export type NearbyPinsQuery = z.infer<typeof nearbyPinsQuerySchema>;
export type ListPostsQuery = z.infer<typeof listPostsQuerySchema>;
export type CreatePostDto = z.infer<typeof createPostSchema>;
export type UpdatePostDto = z.infer<typeof updatePostSchema>;
export type CreateCommentDto = z.infer<typeof createCommentSchema>;
