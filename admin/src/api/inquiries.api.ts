import apiClient from '@/config/api';
import type { PaginatedResponse } from '@/types/common';

export type InquiryStatus = 'OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED';
export type InquiryCategory = 'ACCOUNT' | 'MATCH' | 'SCORE' | 'BUG' | 'SUGGESTION' | 'OTHER';

export interface Inquiry {
  id: string;
  userId: string;
  category: InquiryCategory;
  title: string;
  content: string;
  status: InquiryStatus;
  adminReply: string | null;
  resolvedAt: string | null;
  createdAt: string;
  updatedAt: string;
  user?: {
    id: string;
    nickname: string;
    email: string;
  };
}

export interface InquiryListParams {
  status?: InquiryStatus;
  category?: InquiryCategory;
  page?: number;
  pageSize?: number;
}

export interface InquiryUpdateRequest {
  status?: InquiryStatus;
  adminReply?: string;
}

export const inquiriesApi = {
  list: async (params?: InquiryListParams): Promise<PaginatedResponse<Inquiry>> => {
    const response = await apiClient.get('/admin/inquiries', { params });
    const items = (response.data?.data ?? []) as Inquiry[];
    const meta = response.data?.meta ?? {};
    return {
      items,
      total: meta.total ?? items.length,
      page: meta.page ?? 1,
      pageSize: meta.pageSize ?? items.length,
      totalPages: meta.totalPages ?? 1,
    } as PaginatedResponse<Inquiry>;
  },

  get: async (id: string): Promise<Inquiry> => {
    const response = await apiClient.get(`/admin/inquiries/${id}`);
    return response.data.data;
  },

  update: async (id: string, data: InquiryUpdateRequest): Promise<Inquiry> => {
    const response = await apiClient.patch(`/admin/inquiries/${id}`, data);
    return response.data.data;
  },
};
