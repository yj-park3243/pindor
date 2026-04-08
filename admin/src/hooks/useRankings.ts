import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { rankingsApi, type RankingListParams } from '@/api/rankings.api';

export const RANKING_QUERY_KEYS = {
  all: ['rankings'] as const,
  list: (params?: RankingListParams) => ['rankings', 'list', params] as const,
  pin: (pinId: string, params?: RankingListParams) => ['rankings', 'pin', pinId, params] as const,
  anomalies: (params?: object) => ['rankings', 'anomalies', params] as const,
};

export function useRankingList(params?: RankingListParams) {
  return useQuery({
    queryKey: RANKING_QUERY_KEYS.list(params),
    queryFn: () => rankingsApi.getList(params),
  });
}

export function usePinRanking(pinId: string, params?: RankingListParams) {
  return useQuery({
    queryKey: RANKING_QUERY_KEYS.pin(pinId, params),
    queryFn: () => rankingsApi.getPinRanking(pinId, params),
    enabled: !!pinId,
  });
}

export function useAnomalyList(params?: { page?: number; pageSize?: number; isResolved?: boolean }) {
  return useQuery({
    queryKey: RANKING_QUERY_KEYS.anomalies(params),
    queryFn: () => rankingsApi.getAnomalyList(params),
  });
}

export function useResolveAnomaly() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, note }: { id: string; note: string }) =>
      rankingsApi.resolveAnomaly(id, note),
    onSuccess: () => {
      message.success('이상 감지가 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: RANKING_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('처리에 실패했습니다.');
    },
  });
}

export function useResetSeason() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (sportType: string) => rankingsApi.resetSeason(sportType),
    onSuccess: () => {
      message.success('시즌이 리셋되었습니다.');
      queryClient.invalidateQueries({ queryKey: RANKING_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('시즌 리셋에 실패했습니다.');
    },
  });
}
