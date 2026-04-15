import apiClient from '@/config/api';
import type { AdminUser } from '@/store/auth.store';

export interface AdminLoginRequest {
  username: string;
  password: string;
  mfaCode?: string;
}

export interface AdminLoginResponse {
  admin: AdminUser;
  accessToken: string;
  refreshToken: string;
}

export const authApi = {
  // 어드민 로그인
  login: async (data: AdminLoginRequest): Promise<AdminLoginResponse> => {
    const response = await apiClient.post('/admin/auth/login', data);
    return response.data.data;
  },

  // 어드민 로그아웃
  logout: async (): Promise<void> => {
    await apiClient.post('/admin/auth/logout');
  },

  // 토큰 갱신
  refresh: async (refreshToken: string): Promise<{ accessToken: string; refreshToken: string }> => {
    const response = await apiClient.post('/admin/auth/refresh', { refreshToken });
    return response.data.data;
  },

  // 내 정보 조회
  getMe: async (): Promise<AdminUser> => {
    const response = await apiClient.get('/admin/auth/me');
    return response.data.data;
  },
};
