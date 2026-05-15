import apiClient from '@/config/api';
import type { PaginatedResponse } from '@/types/common';

export type DisputeStatus = 'PENDING' | 'IN_PROGRESS' | 'RESOLVED';

export interface DisputeMatchSide {
  profileId: string;
  userId: string;
  nickname: string;
  claimedResult: 'WIN' | 'LOSS' | 'DRAW' | null;
  score: number | null;
}

export interface DisputeMatchInfo {
  id: string;
  sportType: string;
  status: string;
  requester: DisputeMatchSide;
  opponent: DisputeMatchSide;
  game: {
    id: string;
    resultStatus: string;
    winnerProfileId: string | null;
  } | null;
}

export interface Dispute {
  id: string;
  matchId: string;
  reporterId: string;
  title: string;
  content: string;
  imageUrls: string[];
  phoneNumber: string | null;
  status: DisputeStatus;
  adminReply: string | null;
  resolvedBy: string | null;
  createdAt: string;
  updatedAt: string;
  reporter?: {
    id: string;
    nickname: string;
    email: string;
  };
  match?: DisputeMatchInfo | null;
}

export interface DisputeListParams {
  status?: DisputeStatus;
  page?: number;
  pageSize?: number;
}

export interface DisputeResolution {
  action: 'KEEP_ORIGINAL' | 'MODIFY_RESULT' | 'VOID_GAME';
  winnerProfileId?: string;
  requesterScore?: number;
  opponentScore?: number;
}

export interface DisputeUpdateRequest {
  status: 'IN_PROGRESS' | 'RESOLVED';
  adminReply?: string;
  resolution?: DisputeResolution;
}

export const disputesApi = {
  // 이의 제기 목록 조회
  // 서버 응답: { success, data: Dispute[], meta: { page, pageSize, total, totalPages } }
  // UI는 { items, total, page, pageSize } 형태를 기대하므로 normalize.
  list: async (params?: DisputeListParams): Promise<PaginatedResponse<Dispute>> => {
    const response = await apiClient.get('/admin/disputes', { params });
    const items = (response.data?.data ?? []) as Dispute[];
    const meta = response.data?.meta ?? {};
    return {
      items,
      total: meta.total ?? items.length,
      page: meta.page ?? 1,
      pageSize: meta.pageSize ?? items.length,
      totalPages: meta.totalPages ?? 1,
    } as PaginatedResponse<Dispute>;
  },

  // 이의 제기 상태 업데이트
  update: async (id: string, data: DisputeUpdateRequest): Promise<Dispute> => {
    const response = await apiClient.patch(`/admin/disputes/${id}`, data);
    return response.data.data;
  },
};
