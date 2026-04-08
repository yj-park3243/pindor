import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { teamsApi, type TeamListParams, type TeamMatchListParams } from '@/api/teams.api';
import type { PaginatedResponse } from '@/types/common';
import type { TeamMatch } from '@/types/team';

export const TEAM_QUERY_KEYS = {
  all: ['teams'] as const,
  list: (params?: TeamListParams) => ['teams', 'list', params] as const,
  detail: (id: string) => ['teams', 'detail', id] as const,
  members: (teamId: string) => ['teams', teamId, 'members'] as const,
  matches: (teamId: string) => ['teams', teamId, 'matches'] as const,
  allMatches: (params?: TeamMatchListParams) => ['team-matches', 'list', params] as const,
  posts: (teamId: string) => ['teams', teamId, 'posts'] as const,
};

// 팀 목록 쿼리
export function useTeams(params?: TeamListParams) {
  return useQuery({
    queryKey: TEAM_QUERY_KEYS.list(params),
    queryFn: () => teamsApi.getTeams(params),
  });
}

// 팀 상세 쿼리
export function useTeam(id: string) {
  return useQuery({
    queryKey: TEAM_QUERY_KEYS.detail(id),
    queryFn: () => teamsApi.getTeam(id),
    enabled: !!id,
  });
}

// 팀 멤버 쿼리
export function useTeamMembers(teamId: string) {
  return useQuery({
    queryKey: TEAM_QUERY_KEYS.members(teamId),
    queryFn: () => teamsApi.getTeamMembers(teamId),
    enabled: !!teamId,
  });
}

// 팀 매칭 이력 쿼리 (특정 팀)
export function useTeamMatches(teamId: string) {
  return useQuery({
    queryKey: TEAM_QUERY_KEYS.matches(teamId),
    queryFn: () => teamsApi.getTeamMatches(teamId),
    enabled: !!teamId,
  });
}

// 전체 팀 매칭 목록 쿼리 (관리자 전체 뷰)
export function useTeamMatchesList(params?: TeamMatchListParams) {
  return useQuery<PaginatedResponse<TeamMatch>>({
    queryKey: TEAM_QUERY_KEYS.allMatches(params),
    queryFn: () => teamsApi.getAllTeamMatches(params),
  });
}

// 팀 게시글 쿼리
export function useTeamPosts(teamId: string) {
  return useQuery({
    queryKey: TEAM_QUERY_KEYS.posts(teamId),
    queryFn: () => teamsApi.getTeamPosts(teamId),
    enabled: !!teamId,
  });
}

// 팀 정지 뮤테이션
export function useSuspendTeam() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ teamId, reason }: { teamId: string; reason: string }) =>
      teamsApi.suspendTeam(teamId, reason),
    onSuccess: (_, { teamId }) => {
      message.success('팀이 정지되었습니다.');
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.detail(teamId) });
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('팀 정지 처리에 실패했습니다.');
    },
  });
}

// 팀 활성화 뮤테이션
export function useActivateTeam() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (teamId: string) => teamsApi.activateTeam(teamId),
    onSuccess: (_, teamId) => {
      message.success('팀이 활성화되었습니다.');
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.detail(teamId) });
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('팀 활성화에 실패했습니다.');
    },
  });
}

// 팀 해산 뮤테이션
export function useDisbandTeam() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ teamId, reason }: { teamId: string; reason: string }) =>
      teamsApi.disbandTeam(teamId, reason),
    onSuccess: (_, { teamId }) => {
      message.success('팀이 해산되었습니다.');
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.detail(teamId) });
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('팀 해산 처리에 실패했습니다.');
    },
  });
}

// 팀 멤버 추방 뮤테이션
export function useRemoveTeamMember() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      teamId,
      userId,
      reason,
    }: {
      teamId: string;
      userId: string;
      reason: string;
    }) => teamsApi.removeTeamMember(teamId, userId, reason),
    onSuccess: (_, { teamId }) => {
      message.success('멤버가 추방되었습니다.');
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.members(teamId) });
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.detail(teamId) });
    },
    onError: () => {
      message.error('멤버 추방에 실패했습니다.');
    },
  });
}

// 팀 점수 수동 조정 뮤테이션
export function useUpdateTeamScore() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      teamId,
      score,
      reason,
    }: {
      teamId: string;
      score: number;
      reason: string;
    }) => teamsApi.updateTeamScore(teamId, score, reason),
    onSuccess: (_, { teamId }) => {
      message.success('팀 점수가 조정되었습니다.');
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.detail(teamId) });
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('점수 조정에 실패했습니다.');
    },
  });
}

// 팀 게시글 삭제 뮤테이션
export function useDeleteTeamPost() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ teamId, postId }: { teamId: string; postId: string }) =>
      teamsApi.deleteTeamPost(teamId, postId),
    onSuccess: (_, { teamId }) => {
      message.success('게시글이 삭제되었습니다.');
      queryClient.invalidateQueries({ queryKey: TEAM_QUERY_KEYS.posts(teamId) });
    },
    onError: () => {
      message.error('게시글 삭제에 실패했습니다.');
    },
  });
}
