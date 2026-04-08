import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { pinsApi, type PinListParams, type PinCreateRequest, type PinUpdateRequest } from '@/api/pins.api';

export const PIN_QUERY_KEYS = {
  all: ['pins'] as const,
  list: (params?: PinListParams) => ['pins', 'list', params] as const,
  detail: (id: string) => ['pins', 'detail', id] as const,
  stats: (id: string) => ['pins', id, 'stats'] as const,
};

export function usePinList(params?: PinListParams) {
  return useQuery({
    queryKey: PIN_QUERY_KEYS.list(params),
    queryFn: () => pinsApi.getList(params),
  });
}

export function usePinDetail(id: string) {
  return useQuery({
    queryKey: PIN_QUERY_KEYS.detail(id),
    queryFn: () => pinsApi.getDetail(id),
    enabled: !!id,
  });
}

export function usePinStats(id: string) {
  return useQuery({
    queryKey: PIN_QUERY_KEYS.stats(id),
    queryFn: () => pinsApi.getStats(id),
    enabled: !!id,
  });
}

export function useCreatePin() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: PinCreateRequest) => pinsApi.create(data),
    onSuccess: () => {
      message.success('핀이 생성되었습니다.');
      queryClient.invalidateQueries({ queryKey: PIN_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('핀 생성에 실패했습니다.');
    },
  });
}

export function useUpdatePin() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: PinUpdateRequest }) =>
      pinsApi.update(id, data),
    onSuccess: (_, { id }) => {
      message.success('핀이 수정되었습니다.');
      queryClient.invalidateQueries({ queryKey: PIN_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: PIN_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('핀 수정에 실패했습니다.');
    },
  });
}

export function useTogglePinActive() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      isActive ? pinsApi.deactivate(id) : pinsApi.activate(id),
    onSuccess: (_, { id, isActive }) => {
      message.success(isActive ? '핀이 비활성화되었습니다.' : '핀이 활성화되었습니다.');
      queryClient.invalidateQueries({ queryKey: PIN_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: PIN_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('핀 상태 변경에 실패했습니다.');
    },
  });
}
