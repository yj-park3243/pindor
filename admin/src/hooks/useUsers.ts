import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { usersApi, type UserListParams } from '@/api/users.api';
import type { User, UserStatus } from '@/types/user';
import type { PaginatedResponse } from '@/types/common';
import type { Game } from '@/types/game';

export const USER_QUERY_KEYS = {
  all: ['users'] as const,
  list: (params?: UserListParams) => ['users', 'list', params] as const,
  detail: (id: string) => ['users', 'detail', id] as const,
  games: (id: string) => ['users', id, 'games'] as const,
  matches: (id: string) => ['users', id, 'matches'] as const,
};

// 사용자 목록 쿼리
export function useUserList(params?: UserListParams) {
  return useQuery<PaginatedResponse<User>>({
    queryKey: USER_QUERY_KEYS.list(params),
    queryFn: () => usersApi.getList(params),
  });
}

// 사용자 상세 쿼리
export function useUserDetail(id: string) {
  return useQuery<User>({
    queryKey: USER_QUERY_KEYS.detail(id),
    queryFn: () => usersApi.getDetail(id),
    enabled: !!id,
  });
}

// 사용자 경기 이력 쿼리
export function useUserGameHistory(id: string, params?: { page?: number; pageSize?: number }) {
  return useQuery<PaginatedResponse<Game>>({
    queryKey: USER_QUERY_KEYS.games(id),
    queryFn: () => usersApi.getGameHistory(id, params),
    enabled: !!id,
  });
}

// 사용자 정지 뮤테이션
export function useSuspendUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, reason, durationDays }: { id: string; reason: string; durationDays?: number }) =>
      usersApi.suspend(id, reason, durationDays),
    onSuccess: (_, { id }) => {
      message.success('사용자가 정지되었습니다.');
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('사용자 정지 처리에 실패했습니다.');
    },
  });
}

// 사용자 정지 해제 뮤테이션
export function useUnsuspendUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => usersApi.unsuspend(id),
    onSuccess: (_, id) => {
      message.success('사용자 정지가 해제되었습니다.');
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('정지 해제에 실패했습니다.');
    },
  });
}

// 사용자 상태 변경 뮤테이션
export function useUpdateUserStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, status, reason }: { id: string; status: UserStatus; reason?: string }) =>
      usersApi.updateStatus(id, status, reason),
    onSuccess: (_, { id }) => {
      message.success('사용자 상태가 변경되었습니다.');
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('상태 변경에 실패했습니다.');
    },
  });
}

// 휴대폰 인증 처리/해제 뮤테이션
export function useSetVerified() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, isVerified }: { id: string; isVerified: boolean }) =>
      usersApi.setVerified(id, isVerified),
    onSuccess: (_, { id, isVerified }) => {
      message.success(
        isVerified
          ? '휴대폰 인증이 처리되었습니다.'
          : '휴대폰 인증이 해제되었습니다.',
      );
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('인증 상태 변경에 실패했습니다.');
    },
  });
}

// 사용자 탈퇴 처리 뮤테이션
export function useWithdrawUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      usersApi.withdraw(id, reason),
    onSuccess: () => {
      message.success('사용자가 탈퇴 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: USER_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('탈퇴 처리에 실패했습니다.');
    },
  });
}
