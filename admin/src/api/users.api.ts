import apiClient from '@/config/api';
import type { User, UserListFilter, UserStatus } from '@/types/user';
import type { PaginatedResponse } from '@/types/common';

export interface UserListParams extends UserListFilter {
  page?: number;
  pageSize?: number;
}

export const usersApi = {
  // 사용자 목록 조회
  getList: async (params?: UserListParams): Promise<PaginatedResponse<User>> => {
    const response = await apiClient.get('/admin/users', { params });
    return response.data.data;
  },

  // 사용자 상세 조회
  getDetail: async (id: string): Promise<User> => {
    const response = await apiClient.get(`/admin/users/${id}`);
    return response.data.data;
  },

  // 사용자 정지
  suspend: async (id: string, reason: string, durationDays?: number): Promise<User> => {
    const response = await apiClient.patch(`/admin/users/${id}/suspend`, {
      reason,
      durationDays,
    });
    return response.data.data;
  },

  // 사용자 정지 해제
  unsuspend: async (id: string): Promise<User> => {
    const response = await apiClient.patch(`/admin/users/${id}/unsuspend`);
    return response.data.data;
  },

  // 사용자 상태 변경
  updateStatus: async (id: string, status: UserStatus, reason?: string): Promise<User> => {
    const response = await apiClient.patch(`/admin/users/${id}/status`, {
      status,
      reason,
    });
    return response.data.data;
  },

  // 사용자 탈퇴 처리
  withdraw: async (id: string, reason: string): Promise<void> => {
    await apiClient.delete(`/admin/users/${id}`, { data: { reason } });
  },

  // 휴대폰 인증 수동 처리/해제
  setVerified: async (id: string, isVerified: boolean): Promise<User> => {
    const response = await apiClient.patch(`/admin/users/${id}/verify`, {
      isVerified,
    });
    return response.data.data;
  },

  // 사용자 경기 이력 조회
  getGameHistory: async (id: string, params?: { page?: number; pageSize?: number }) => {
    const response = await apiClient.get(`/admin/users/${id}/games`, { params });
    return response.data.data;
  },

  // 사용자 매칭 이력 조회
  getMatchHistory: async (id: string, params?: { page?: number; pageSize?: number }) => {
    const response = await apiClient.get(`/admin/users/${id}/matches`, { params });
    return response.data.data;
  },
};
