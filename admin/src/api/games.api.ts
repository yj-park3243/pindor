import apiClient from '@/config/api';
import type { Game, GameListFilter } from '@/types/game';
import type { PaginatedResponse } from '@/types/common';

export interface GameListParams extends GameListFilter {
  page?: number;
  pageSize?: number;
}

export type DisputeResolution = 'ORIGINAL' | 'MODIFIED' | 'VOIDED';

export interface DisputeResolveRequest {
  resolution: DisputeResolution;
  adminNote: string;
  modifiedScoreData?: Record<string, unknown>;
  // 결과 수정(MODIFIED) 시 관리자 지정 승자/점수
  winnerProfileId?: string;
  requesterScore?: number;
  opponentScore?: number;
}

export const gamesApi = {
  // 경기 결과 목록 조회
  getList: async (params?: GameListParams): Promise<PaginatedResponse<Game>> => {
    const response = await apiClient.get('/admin/games', { params });
    return response.data.data;
  },

  // 경기 결과 상세 조회
  getDetail: async (id: string): Promise<Game> => {
    const response = await apiClient.get(`/admin/games/${id}`);
    return response.data.data;
  },

  // 이의 신청 목록 조회
  getDisputeList: async (params?: GameListParams): Promise<PaginatedResponse<Game>> => {
    const response = await apiClient.get('/admin/games/disputes', { params });
    return response.data.data;
  },

  // 이의 신청 처리 (원본 유지 / 결과 수정 / 무효 처리)
  // 서버 `/admin/games/:id/resolve-dispute` (POST)가 action: KEEP_ORIGINAL|MODIFY_RESULT|VOID_GAME
  // 을 받으므로 프론트 ORIGINAL/MODIFIED/VOIDED를 매핑해서 전달.
  resolveDispute: async (gameId: string, data: DisputeResolveRequest): Promise<Game> => {
    const actionMap: Record<DisputeResolution, 'KEEP_ORIGINAL' | 'MODIFY_RESULT' | 'VOID_GAME'> = {
      ORIGINAL: 'KEEP_ORIGINAL',
      MODIFIED: 'MODIFY_RESULT',
      VOIDED: 'VOID_GAME',
    };
    const body: Record<string, unknown> = {
      action: actionMap[data.resolution],
      adminNote: data.adminNote,
    };
    if (data.resolution === 'MODIFIED') {
      body.winnerId = data.winnerProfileId;
      body.requesterScore = data.requesterScore;
      body.opponentScore = data.opponentScore;
    }
    const response = await apiClient.post(`/admin/games/${gameId}/resolve-dispute`, body);
    return response.data.data;
  },

  // 경기 무효 처리
  voidGame: async (gameId: string, reason: string): Promise<Game> => {
    const response = await apiClient.patch(`/admin/games/${gameId}/void`, { reason });
    return response.data.data;
  },
};
