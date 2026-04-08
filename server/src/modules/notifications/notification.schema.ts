import { z } from 'zod';

export const listNotificationsQuerySchema = z.object({
  isRead: z
    .string()
    .optional()
    .transform((v) => (v === 'true' ? true : v === 'false' ? false : undefined)),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

export const registerPushTokenSchema = z.object({
  token: z.string().min(1, '푸시 토큰이 필요합니다.').max(512),
  platform: z.enum(['ANDROID', 'IOS']),
});

export const deletePushTokenSchema = z.object({
  token: z.string().min(1, '푸시 토큰이 필요합니다.'),
});

export const updateNotificationSettingsSchema = z.object({
  chatMessage: z.boolean().optional(),
  matchFound: z.boolean().optional(),
  matchRequest: z.boolean().optional(),
  gameResult: z.boolean().optional(),
  scoreChange: z.boolean().optional(),
  communityReply: z.boolean().optional(),
  doNotDisturbStart: z
    .string()
    .regex(/^\d{2}:\d{2}$/, 'HH:MM 형식이어야 합니다.')
    .optional()
    .nullable(),
  doNotDisturbEnd: z
    .string()
    .regex(/^\d{2}:\d{2}$/, 'HH:MM 형식이어야 합니다.')
    .optional()
    .nullable(),
});

export type ListNotificationsQuery = z.infer<typeof listNotificationsQuerySchema>;
export type RegisterPushTokenDto = z.infer<typeof registerPushTokenSchema>;
export type DeletePushTokenDto = z.infer<typeof deletePushTokenSchema>;
export type UpdateNotificationSettingsDto = z.infer<typeof updateNotificationSettingsSchema>;
