import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { reportsApi, type ReportListParams, type ReportResolveRequest } from '@/api/reports.api';

export const REPORT_QUERY_KEYS = {
  all: ['reports'] as const,
  list: (params?: ReportListParams) => ['reports', 'list', params] as const,
  detail: (id: string) => ['reports', 'detail', id] as const,
};

export function useReportList(params?: ReportListParams) {
  return useQuery({
    queryKey: REPORT_QUERY_KEYS.list(params),
    queryFn: () => reportsApi.getList(params),
  });
}

export function useReportDetail(id: string) {
  return useQuery({
    queryKey: REPORT_QUERY_KEYS.detail(id),
    queryFn: () => reportsApi.getDetail(id),
    enabled: !!id,
  });
}

export function useResolveReport() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: ReportResolveRequest }) =>
      reportsApi.resolve(id, data),
    onSuccess: (_, { id }) => {
      message.success('신고가 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: REPORT_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: REPORT_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('신고 처리에 실패했습니다.');
    },
  });
}
