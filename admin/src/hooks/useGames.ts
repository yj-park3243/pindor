import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { gamesApi, type GameListParams, type DisputeResolveRequest } from '@/api/games.api';

export const GAME_QUERY_KEYS = {
  all: ['games'] as const,
  list: (params?: GameListParams) => ['games', 'list', params] as const,
  detail: (id: string) => ['games', 'detail', id] as const,
  disputes: (params?: GameListParams) => ['games', 'disputes', params] as const,
};

export function useGameList(params?: GameListParams) {
  return useQuery({
    queryKey: GAME_QUERY_KEYS.list(params),
    queryFn: () => gamesApi.getList(params),
  });
}

export function useGameDetail(id: string) {
  return useQuery({
    queryKey: GAME_QUERY_KEYS.detail(id),
    queryFn: () => gamesApi.getDetail(id),
    enabled: !!id,
  });
}

export function useDisputeList(params?: GameListParams) {
  return useQuery({
    queryKey: GAME_QUERY_KEYS.disputes(params),
    queryFn: () => gamesApi.getDisputeList(params),
  });
}

export function useResolveDispute() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ gameId, data }: { gameId: string; data: DisputeResolveRequest }) =>
      gamesApi.resolveDispute(gameId, data),
    onSuccess: (_, { gameId }) => {
      message.success('이의 신청이 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: GAME_QUERY_KEYS.detail(gameId) });
      queryClient.invalidateQueries({ queryKey: GAME_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('이의 신청 처리에 실패했습니다.');
    },
  });
}

export function useVoidGame() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ gameId, reason }: { gameId: string; reason: string }) =>
      gamesApi.voidGame(gameId, reason),
    onSuccess: () => {
      message.success('경기가 무효 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: GAME_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('무효 처리에 실패했습니다.');
    },
  });
}
