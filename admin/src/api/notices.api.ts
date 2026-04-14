import apiClient from '@/config/api';
import type { PaginatedResponse } from '@/types/common';

export interface Notice {
  id: string;
  title: string;
  content: string;
  isPinned: boolean;
  isPublished: boolean;
  authorId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateNoticeRequest {
  title: string;
  content: string;
  isPinned?: boolean;
  isPublished?: boolean;
}

export const noticesApi = {
  list: async (page = 1, pageSize = 20): Promise<PaginatedResponse<Notice>> => {
    const res = await apiClient.get('/admin/notices', { params: { page, pageSize } });
    return res.data.data;
  },
  create: async (data: CreateNoticeRequest): Promise<Notice> => {
    const res = await apiClient.post('/admin/notices', data);
    return res.data.data;
  },
  update: async (id: string, data: Partial<CreateNoticeRequest>): Promise<Notice> => {
    const res = await apiClient.patch(`/admin/notices/${id}`, data);
    return res.data.data;
  },
  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/admin/notices/${id}`);
  },
};
