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
