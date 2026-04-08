import apiClient from '@/config/api';

export type DisputeStatus = 'PENDING' | 'IN_PROGRESS' | 'RESOLVED';

export interface Dispute {
  id: string;
  matchId: string;
  reporterId: string;
  title: string;
  content: string;
  imageUrls: string[];
  phoneNumber: string | null;
  status: DisputeStatus;
  adminReply: string | null;
  resolvedBy: string | null;
  createdAt: string;
  updatedAt: string;
  reporter?: {
    id: string;
    nickname: string;
    email: string;
  };
}

export interface DisputeListParams {
  status?: DisputeStatus;
  page?: number;
  pageSize?: number;
}

export interface DisputeUpdateRequest {
  status: 'IN_PROGRESS' | 'RESOLVED';
  adminReply?: string;
}

export interface PaginatedDisputeResponse {
  items: Dispute[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export const disputesApi = {
  // 의의 제기 목록 조회
  list: async (params?: DisputeListParams): Promise<PaginatedDisputeResponse> => {
    const response = await apiClient.get('/admin/disputes', { params });
    return {
      items: response.data.data,
      ...response.data.meta,
    };
  },

  // 의의 제기 상태 업데이트
  update: async (id: string, data: DisputeUpdateRequest): Promise<Dispute> => {
    const response = await apiClient.patch(`/admin/disputes/${id}`, data);
    return response.data.data;
  },
};
