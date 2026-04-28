import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { matchesApi, type MatchListParams, type NoshowReportListParams } from '@/api/matches.api';

export const MATCH_QUERY_KEYS = {
  all: ['matches'] as const,
  list: (params?: MatchListParams) => ['matches', 'list', params] as const,
  detail: (id: string) => ['matches', 'detail', id] as const,
  messages: (id: string) => ['matches', 'messages', id] as const,
  noshowReports: (params?: NoshowReportListParams) => ['noshow-reports', params] as const,
};

export function useMatchList(params?: MatchListParams) {
  return useQuery({
    queryKey: MATCH_QUERY_KEYS.list(params),
    queryFn: () => matchesApi.getList(params),
  });
}

export function useMatchDetail(id: string) {
  return useQuery({
    queryKey: MATCH_QUERY_KEYS.detail(id),
    queryFn: () => matchesApi.getDetail(id),
    enabled: !!id,
  });
}

export function useForceCancel() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      matchesApi.forceCancel(id, reason),
    onSuccess: () => {
      message.success('매칭이 강제 취소되었습니다.');
      queryClient.invalidateQueries({ queryKey: MATCH_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('강제 취소에 실패했습니다.');
    },
  });
}

export function useChatMessages(matchId: string | null) {
  return useQuery({
    queryKey: MATCH_QUERY_KEYS.messages(matchId ?? ''),
    queryFn: () => matchesApi.getMessages(matchId!),
    enabled: !!matchId,
  });
}

export function useNoshowReports(params?: NoshowReportListParams) {
  return useQuery({
    queryKey: MATCH_QUERY_KEYS.noshowReports(params),
    queryFn: () => matchesApi.getNoshowReports(params),
  });
}

export function useNoshowPendingCount() {
  return useQuery({
    queryKey: ['noshow-reports', 'pending-count'],
    queryFn: () => matchesApi.getNoshowPendingCount(),
    refetchInterval: 60 * 1000, // 1분마다 갱신
  });
}

export function useApproveNoshowReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, memo }: { id: string; memo: string }) =>
      matchesApi.approveNoshowReport(id, memo),
    onSuccess: () => {
      message.success('노쇼 신고가 승인되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['noshow-reports'] });
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.error?.message ?? '승인 처리에 실패했습니다.';
      message.error(msg);
    },
  });
}

export function useRejectNoshowReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, memo, reporterPenalty }: { id: string; memo: string; reporterPenalty?: boolean }) =>
      matchesApi.rejectNoshowReport(id, memo, reporterPenalty),
    onSuccess: () => {
      message.success('노쇼 신고가 기각되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['noshow-reports'] });
    },
    onError: () => {
      message.error('기각 처리에 실패했습니다.');
    },
  });
}

export function useInsufficientNoshowReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, memo }: { id: string; memo: string }) =>
      matchesApi.insufficientNoshowReport(id, memo),
    onSuccess: () => {
      message.success('자료 요청이 발송되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['noshow-reports'] });
    },
    onError: () => {
      message.error('자료 요청에 실패했습니다.');
    },
  });
}

export function useBulkRejectNoshowReports() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ ids, memo }: { ids: string[]; memo: string }) =>
      matchesApi.bulkRejectNoshowReports(ids, memo),
    onSuccess: (data) => {
      message.success(data.message);
      queryClient.invalidateQueries({ queryKey: ['noshow-reports'] });
    },
    onError: () => {
      message.error('일괄 기각에 실패했습니다.');
    },
  });
}

export function useForceComplete() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => matchesApi.forceComplete(id),
    onSuccess: () => {
      message.success('매칭이 강제 완료 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: MATCH_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('강제 완료에 실패했습니다.');
    },
  });
}
