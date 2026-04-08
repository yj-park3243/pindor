import apiClient from '@/config/api';
import type { AdminUser, AdminRole } from '@/store/auth.store';

export interface SystemSettings {
  kFactor: {
    beginner: number;
    intermediate: number;
    standard: number;
    platinum: number;
  };
  tierThresholds: {
    bronzeMin: number;
    silverMin: number;
    goldMin: number;
    platinumMin: number;
  };
  matchSettings: {
    expirationHours: number;
    instantMatchWindowHours: number;
    defaultRadiusKm: number;
    maxRadiusKm: number;
    minRadiusKm: number;
    cancelPenaltyThreshold: number;
  };
  rankingSettings: {
    minGamesForRanking: number;
    inactiveDaysThreshold: number;
    nationalRankingMinGames: number;
  };
}

export interface AdminAccountCreateRequest {
  email: string;
  password: string;
  name: string;
  role: AdminRole;
}

export interface AdminAccountUpdateRequest {
  name?: string;
  role?: AdminRole;
  isActive?: boolean;
}

export const settingsApi = {
  // 시스템 설정 조회
  getSystemSettings: async (): Promise<SystemSettings> => {
    const response = await apiClient.get('/admin/settings/system');
    return response.data.data;
  },

  // 시스템 설정 수정
  updateSystemSettings: async (data: Partial<SystemSettings>): Promise<SystemSettings> => {
    const response = await apiClient.patch('/admin/settings/system', data);
    return response.data.data;
  },

  // 어드민 계정 목록 조회
  getAdminAccounts: async (): Promise<AdminUser[]> => {
    const response = await apiClient.get('/admin/settings/accounts');
    return response.data.data;
  },

  // 어드민 계정 생성
  createAdminAccount: async (data: AdminAccountCreateRequest): Promise<AdminUser> => {
    const response = await apiClient.post('/admin/settings/accounts', data);
    return response.data.data;
  },

  // 어드민 계정 수정
  updateAdminAccount: async (id: string, data: AdminAccountUpdateRequest): Promise<AdminUser> => {
    const response = await apiClient.patch(`/admin/settings/accounts/${id}`, data);
    return response.data.data;
  },

  // 어드민 계정 삭제
  deleteAdminAccount: async (id: string): Promise<void> => {
    await apiClient.delete(`/admin/settings/accounts/${id}`);
  },
};
