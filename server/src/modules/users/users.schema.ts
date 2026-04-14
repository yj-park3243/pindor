import { z } from 'zod';

export const updateUserSchema = z.object({
  nickname: z
    .string()
    .min(2, '닉네임은 최소 2자입니다.')
    .max(20, '닉네임은 최대 20자입니다.')
    .regex(/^[가-힣a-zA-Z0-9_]+$/, '닉네임은 한글, 영문, 숫자, 밑줄만 사용 가능합니다.')
    .optional(),
  profileImageUrl: z.string().url('올바른 URL 형식이 아닙니다.').optional(),
  phone: z
    .string()
    .regex(/^01[0-9]-?\d{3,4}-?\d{4}$/, '올바른 전화번호 형식이 아닙니다.')
    .optional(),
  gender: z.enum(['MALE', 'FEMALE', 'OTHER']).optional(),
  birthDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, '생년월일 형식은 YYYY-MM-DD 입니다.')
    .optional(),
  preferredSportType: z
    .string()
    .max(50)
    .nullable()
    .optional(),
});

export const updateLocationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  address: z.string().max(255).optional(),
  matchRadiusKm: z.number().min(1).max(50).default(10),
});

export const deleteUserSchema = z.object({
  reason: z.string().max(500).optional(),
});

export type UpdateUserDto = z.infer<typeof updateUserSchema>;
export type UpdateLocationDto = z.infer<typeof updateLocationSchema>;
export type DeleteUserDto = z.infer<typeof deleteUserSchema>;
