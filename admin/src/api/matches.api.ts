import apiClient from '@/config/api';
import type { Match, MatchListFilter } from '@/types/match';
import type { PaginatedResponse } from '@/types/common';

export interface MatchListParams extends MatchListFilter {
  page?: number;
  pageSize?: number;
}

export const matchesApi = {
  // 매칭 목록 조회
  getList: async (params?: MatchListParams): Promise<PaginatedResponse<Match>> => {
    const response = await apiClient.get('/admin/matches', { params });
    return response.data.data;
  },

  // 매칭 상세 조회
  getDetail: async (id: string): Promise<Match> => {
    const response = await apiClient.get(`/admin/matches/${id}`);
    return response.data.data;
  },

  // 매칭 강제 취소
  forceCancel: async (id: string, reason: string): Promise<Match> => {
    const response = await apiClient.patch(`/admin/matches/${id}/force-cancel`, { reason });
    return response.data.data;
  },

  // 매칭 강제 완료
  forceComplete: async (id: string): Promise<Match> => {
    const response = await apiClient.patch(`/admin/matches/${id}/force-complete`);
    return response.data.data;
  },

  // 매칭 채팅 메시지 조회
  getMessages: async (matchId: string): Promise<ChatMessage[]> => {
    const response = await apiClient.get(`/admin/matches/${matchId}/messages`);
    return response.data.data;
  },

  // 노쇼 신고 목록 조회
  getNoshowReports: async (params?: NoshowReportListParams): Promise<PaginatedResponse<NoshowReport>> => {
    const response = await apiClient.get('/admin/noshow-reports', { params });
    return response.data.data;
  },

  // PENDING 노쇼 신고 카운트 조회
  getNoshowPendingCount: async (): Promise<{ pendingCount: number; overdueCount: number }> => {
    const response = await apiClient.get('/admin/noshow-reports/pending-count');
    return response.data.data;
  },

  // 노쇼 신고 승인
  approveNoshowReport: async (id: string, memo: string): Promise<{ message: string }> => {
    const response = await apiClient.post(`/admin/noshow-reports/${id}/approve`, { memo });
    return response.data.data;
  },

  // 노쇼 신고 기각
  rejectNoshowReport: async (id: string, memo: string, reporterPenalty?: boolean): Promise<{ message: string }> => {
    const response = await apiClient.post(`/admin/noshow-reports/${id}/reject`, { memo, reporterPenalty });
    return response.data.data;
  },

  // 노쇼 신고 자료 부족
  insufficientNoshowReport: async (id: string, memo: string): Promise<{ message: string }> => {
    const response = await apiClient.post(`/admin/noshow-reports/${id}/insufficient`, { memo });
    return response.data.data;
  },

  // 노쇼 신고 일괄 기각
  bulkRejectNoshowReports: async (ids: string[], memo: string): Promise<{ message: string }> => {
    const response = await apiClient.post('/admin/noshow-reports/bulk-reject', { ids, memo });
    return response.data.data;
  },
};

export interface ChatMessage {
  id: string;
  senderId: string;
  senderNickname: string;
  senderProfileImageUrl: string | null;
  messageType: string;
  content: string | null;
  imageUrl: string | null;
  extraData: Record<string, unknown> | null;
  createdAt: string;
}

export interface NoshowReport {
  id: string;
  matchId: string;
  reporterId: string;
  reporterNickname: string;
  reporterProfileImageUrl: string | null;
  reporterMannerAvg: number | null;
  reporterTotalReports: number;
  reporterApprovedReports: number;
  reportedUserId: string;
  reportedNickname: string;
  reportedProfileImageUrl: string | null;
  reportedProfileId: string;
  reportedConfirmedCount: number;
  reportedMannerAvg: number | null;
  status: string;
  evidenceUrls: string[];
  reporterMessage: string | null;
  adminId: string | null;
  adminDecisionAt: string | null;
  adminMemo: string | null;
  appliedScoreChange: number | null;
  appliedBanHours: number | null;
  createdAt: string;
  updatedAt: string;
  match: {
    id: string;
    sportType: string;
    status: string;
    chatRoomId: string;
    requesterNickname: string;
    opponentNickname: string;
    scheduledDate: string | null;
    createdAt: string;
  } | null;
}

export interface NoshowReportListParams {
  status?: string;
  search?: string;
  page?: number;
  pageSize?: number;
}
