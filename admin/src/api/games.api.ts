import apiClient from '@/config/api';
import type { Game, GameListFilter } from '@/types/game';
import type { PaginatedResponse } from '@/types/common';

export interface GameListParams extends GameListFilter {
  page?: number;
  pageSize?: number;
}

export type DisputeResolution = 'ORIGINAL' | 'MODIFIED' | 'VOIDED';

export interface DisputeResolveRequest {
  resolution: DisputeResolution;
  adminNote: string;
  modifiedScoreData?: Record<string, unknown>;
}

export const gamesApi = {
  // 경기 결과 목록 조회
  getList: async (params?: GameListParams): Promise<PaginatedResponse<Game>> => {
    const response = await apiClient.get('/admin/games', { params });
    return response.data.data;
  },

  // 경기 결과 상세 조회
  getDetail: async (id: string): Promise<Game> => {
    const response = await apiClient.get(`/admin/games/${id}`);
    return response.data.data;
  },

  // 이의 신청 목록 조회
  getDisputeList: async (params?: GameListParams): Promise<PaginatedResponse<Game>> => {
    const response = await apiClient.get('/admin/games/disputes', { params });
    return response.data.data;
  },

  // 이의 신청 처리 (원본 유지 / 결과 수정 / 무효 처리)
  resolveDispute: async (gameId: string, data: DisputeResolveRequest): Promise<Game> => {
    const response = await apiClient.patch(`/admin/games/${gameId}/resolve-dispute`, data);
    return response.data.data;
  },

  // 경기 무효 처리
  voidGame: async (gameId: string, reason: string): Promise<Game> => {
    const response = await apiClient.patch(`/admin/games/${gameId}/void`, { reason });
    return response.data.data;
  },
};
