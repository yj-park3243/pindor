import apiClient from '@/config/api';
import type { Team, TeamMember, TeamMatch, TeamPost } from '@/types/team';
import type { PaginatedResponse } from '@/types/common';

export interface TeamListParams {
  search?: string;
  sportType?: string;
  status?: string;
  page?: number;
  pageSize?: number;
}

export interface TeamMatchListParams {
  status?: string;
  sportType?: string;
  page?: number;
  pageSize?: number;
}

export const teamsApi = {
  // 팀 목록 조회 (검색, 필터, 페이지네이션)
  getTeams: async (params?: TeamListParams): Promise<PaginatedResponse<Team>> => {
    const response = await apiClient.get('/admin/teams', { params });
    return response.data.data;
  },

  // 팀 상세 조회
  getTeam: async (id: string): Promise<Team> => {
    const response = await apiClient.get(`/admin/teams/${id}`);
    return response.data.data;
  },

  // 팀 멤버 목록 조회
  getTeamMembers: async (teamId: string): Promise<TeamMember[]> => {
    const response = await apiClient.get(`/admin/teams/${teamId}/members`);
    return response.data.data;
  },

  // 팀 매칭 이력 조회 (특정 팀)
  getTeamMatches: async (teamId: string): Promise<TeamMatch[]> => {
    const response = await apiClient.get(`/admin/teams/${teamId}/matches`);
    return response.data.data;
  },

  // 전체 팀 매칭 목록 조회 (관리자 전체 뷰)
  getAllTeamMatches: async (params?: TeamMatchListParams): Promise<PaginatedResponse<TeamMatch>> => {
    const response = await apiClient.get('/admin/team-matches', { params });
    return response.data.data;
  },

  // 팀 게시글 목록 조회
  getTeamPosts: async (teamId: string): Promise<TeamPost[]> => {
    const response = await apiClient.get(`/admin/teams/${teamId}/posts`);
    return response.data.data;
  },

  // 팀 정지
  suspendTeam: async (teamId: string, reason: string): Promise<void> => {
    await apiClient.patch(`/admin/teams/${teamId}/suspend`, { reason });
  },

  // 팀 활성화
  activateTeam: async (teamId: string): Promise<void> => {
    await apiClient.patch(`/admin/teams/${teamId}/activate`);
  },

  // 팀 해산
  disbandTeam: async (teamId: string, reason: string): Promise<void> => {
    await apiClient.patch(`/admin/teams/${teamId}/disband`, { reason });
  },

  // 팀 멤버 추방
  removeTeamMember: async (teamId: string, userId: string, reason: string): Promise<void> => {
    await apiClient.delete(`/admin/teams/${teamId}/members/${userId}`, {
      data: { reason },
    });
  },

  // 팀 점수 수동 조정
  updateTeamScore: async (teamId: string, score: number, reason: string): Promise<void> => {
    await apiClient.patch(`/admin/teams/${teamId}/score`, { score, reason });
  },

  // 팀 게시글 삭제
  deleteTeamPost: async (teamId: string, postId: string): Promise<void> => {
    await apiClient.delete(`/admin/teams/${teamId}/posts/${postId}`);
  },
};
