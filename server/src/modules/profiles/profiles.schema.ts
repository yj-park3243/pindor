import { z } from 'zod';
import { SportType } from '../../entities/index.js';

export const createSportsProfileSchema = z.object({
  sportType: z.nativeEnum(SportType),
  displayName: z.string().max(50).optional(),
  matchMessage: z.string().max(100).optional(),
  gHandicap: z
    .number()
    .min(0, 'G핸디는 0 이상이어야 합니다.')
    .max(54, 'G핸디는 54 이하여야 합니다.')
    .optional(),
  extraData: z.record(z.unknown()).optional(),
});

export const updateSportsProfileSchema = z.object({
  displayName: z.string().max(50).optional(),
  matchMessage: z.string().max(100).optional(),
  gHandicap: z
    .number()
    .min(0, 'G핸디는 0 이상이어야 합니다.')
    .max(54, 'G핸디는 54 이하여야 합니다.')
    .optional(),
  extraData: z.record(z.unknown()).optional(),
});

export type CreateSportsProfileDto = z.infer<typeof createSportsProfileSchema>;
export type UpdateSportsProfileDto = z.infer<typeof updateSportsProfileSchema>;
