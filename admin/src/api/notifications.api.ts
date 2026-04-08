import apiClient from '@/config/api';
import type { NotificationSendRequest, NotificationLog } from '@/types/notification';
import type { PaginatedResponse } from '@/types/common';

export const notificationsApi = {
  // 공지 푸시 발송
  send: async (data: NotificationSendRequest): Promise<{ sentCount: number }> => {
    const response = await apiClient.post('/admin/notifications/send', data);
    return response.data.data;
  },

  // 발송 이력 조회
  getLogs: async (params?: {
    page?: number;
    pageSize?: number;
  }): Promise<PaginatedResponse<NotificationLog>> => {
    const response = await apiClient.get('/admin/notifications/logs', { params });
    return response.data.data;
  },
};
