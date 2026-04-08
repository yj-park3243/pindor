import apiClient from '@/config/api';
import type { SportsProfile, ScoreHistory } from '@/types/user';
import type { PaginatedResponse } from '@/types/common';

export interface ProfileListParams {
  search?: string;
  sportType?: string;
  tier?: string;
  page?: number;
  pageSize?: number;
}

export interface ScoreAdjustRequest {
  adjustment: number; // 양수: 증가, 음수: 감소
  reason: string;
}

export const profilesApi = {
  // 스포츠 프로필 목록 조회
  getList: async (params?: ProfileListParams): Promise<PaginatedResponse<SportsProfile>> => {
    const response = await apiClient.get('/admin/sports-profiles', { params });
    return response.data.data;
  },

  // 스포츠 프로필 상세 조회
  getDetail: async (id: string): Promise<SportsProfile> => {
    const response = await apiClient.get(`/admin/sports-profiles/${id}`);
    return response.data.data;
  },

  // 점수 수동 조정
  adjustScore: async (id: string, data: ScoreAdjustRequest): Promise<SportsProfile> => {
    const response = await apiClient.post(`/admin/sports-profiles/${id}/score-adjust`, data);
    return response.data.data;
  },

  // 점수 히스토리 조회
  getScoreHistory: async (
    id: string,
    params?: { page?: number; pageSize?: number }
  ): Promise<PaginatedResponse<ScoreHistory>> => {
    const response = await apiClient.get(`/admin/sports-profiles/${id}/score-history`, { params });
    return response.data.data;
  },

  // G핸디 인증 처리
  verifyGHandicap: async (id: string, isVerified: boolean): Promise<SportsProfile> => {
    const response = await apiClient.patch(`/admin/sports-profiles/${id}/verify`, { isVerified });
    return response.data.data;
  },
};
