import apiClient from '@/config/api';
import type { DashboardMetrics } from '@/types/dashboard';

export const dashboardApi = {
  // 대시보드 전체 지표 조회
  getMetrics: async (): Promise<DashboardMetrics> => {
    const response = await apiClient.get('/admin/dashboard/metrics');
    return response.data.data;
  },

  // 실시간 현황만 조회 (폴링용)
  getRealtime: async (): Promise<DashboardMetrics['realtime']> => {
    const response = await apiClient.get('/admin/dashboard/realtime');
    return response.data.data;
  },
};
