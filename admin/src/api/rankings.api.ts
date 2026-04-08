import apiClient from '@/config/api';
import type { RankingEntry, RankingAnomalyFlag, RankingListFilter } from '@/types/ranking';
import type { PaginatedResponse } from '@/types/common';

export interface RankingListParams extends RankingListFilter {
  page?: number;
  pageSize?: number;
}

export const rankingsApi = {
  // 핀별 랭킹 조회
  getPinRanking: async (pinId: string, params?: RankingListParams): Promise<RankingEntry[]> => {
    const response = await apiClient.get(`/admin/rankings/pins/${pinId}`, { params });
    return response.data.data;
  },

  // 전체 랭킹 목록 조회 (어드민용)
  getList: async (params?: RankingListParams): Promise<PaginatedResponse<RankingEntry>> => {
    const response = await apiClient.get('/admin/rankings', { params });
    return response.data.data;
  },

  // 이상 감지 목록 조회
  getAnomalyList: async (
    params?: { page?: number; pageSize?: number; isResolved?: boolean }
  ): Promise<PaginatedResponse<RankingAnomalyFlag>> => {
    const response = await apiClient.get('/admin/rankings/anomalies', { params });
    return response.data.data;
  },

  // 이상 감지 해결 처리
  resolveAnomaly: async (id: string, note: string): Promise<RankingAnomalyFlag> => {
    const response = await apiClient.patch(`/admin/rankings/anomalies/${id}/resolve`, { note });
    return response.data.data;
  },

  // 시즌 리셋 실행
  resetSeason: async (sportType: string): Promise<void> => {
    await apiClient.post('/admin/rankings/season-reset', { sportType });
  },
};
