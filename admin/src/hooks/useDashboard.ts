import { useQuery } from '@tanstack/react-query';
import { dashboardApi } from '@/api/dashboard.api';

export const DASHBOARD_QUERY_KEYS = {
  metrics: ['dashboard', 'metrics'] as const,
  realtime: ['dashboard', 'realtime'] as const,
};

// 전체 대시보드 지표 (30초마다 자동 갱신)
export function useDashboardMetrics() {
  return useQuery({
    queryKey: DASHBOARD_QUERY_KEYS.metrics,
    queryFn: dashboardApi.getMetrics,
    refetchInterval: 30_000, // 30초
    staleTime: 10_000,
  });
}

// 실시간 현황만 (10초마다 자동 갱신)
export function useRealtimeMetrics() {
  return useQuery({
    queryKey: DASHBOARD_QUERY_KEYS.realtime,
    queryFn: dashboardApi.getRealtime,
    refetchInterval: 10_000, // 10초
    staleTime: 5_000,
  });
}
