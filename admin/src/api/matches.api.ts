import apiClient from '@/config/api';
import type { Match, MatchListFilter } from '@/types/match';
import type { PaginatedResponse } from '@/types/common';

export interface MatchListParams extends MatchListFilter {
  page?: number;
  pageSize?: number;
}

export const matchesApi = {
  // 매칭 목록 조회
  getList: async (params?: MatchListParams): Promise<PaginatedResponse<Match>> => {
    const response = await apiClient.get('/admin/matches', { params });
    return response.data.data;
  },

  // 매칭 상세 조회
  getDetail: async (id: string): Promise<Match> => {
    const response = await apiClient.get(`/admin/matches/${id}`);
    return response.data.data;
  },

  // 매칭 강제 취소
  forceCancel: async (id: string, reason: string): Promise<Match> => {
    const response = await apiClient.patch(`/admin/matches/${id}/force-cancel`, { reason });
    return response.data.data;
  },

  // 매칭 강제 완료
  forceComplete: async (id: string): Promise<Match> => {
    const response = await apiClient.patch(`/admin/matches/${id}/force-complete`);
    return response.data.data;
  },
};
