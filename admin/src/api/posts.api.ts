import apiClient from '@/config/api';
import type { PinPost, Comment, PostListFilter } from '@/types/pin';
import type { PaginatedResponse } from '@/types/common';

export interface PostListParams extends PostListFilter {
  page?: number;
  pageSize?: number;
}

export const postsApi = {
  // 게시글 목록 조회
  getList: async (params?: PostListParams): Promise<PaginatedResponse<PinPost>> => {
    const response = await apiClient.get('/admin/posts', { params });
    return response.data.data;
  },

  // 게시글 상세 조회
  getDetail: async (id: string): Promise<PinPost> => {
    const response = await apiClient.get(`/admin/posts/${id}`);
    return response.data.data;
  },

  // 게시글 삭제
  delete: async (id: string, reason: string): Promise<void> => {
    await apiClient.delete(`/admin/posts/${id}`, { data: { reason } });
  },

  // 게시글 블라인드 처리
  blind: async (id: string, reason: string): Promise<PinPost> => {
    const response = await apiClient.patch(`/admin/posts/${id}/blind`, { reason });
    return response.data.data;
  },

  // 게시글 블라인드 해제
  unblind: async (id: string): Promise<PinPost> => {
    const response = await apiClient.patch(`/admin/posts/${id}/unblind`);
    return response.data.data;
  },

  // 게시글 댓글 목록 조회
  getComments: async (postId: string): Promise<Comment[]> => {
    const response = await apiClient.get(`/admin/posts/${postId}/comments`);
    return response.data.data;
  },

  // 댓글 삭제
  deleteComment: async (postId: string, commentId: string, reason: string): Promise<void> => {
    await apiClient.delete(`/admin/posts/${postId}/comments/${commentId}`, {
      data: { reason },
    });
  },

  // 댓글 블라인드
  blindComment: async (postId: string, commentId: string, reason: string): Promise<Comment> => {
    const response = await apiClient.patch(
      `/admin/posts/${postId}/comments/${commentId}/blind`,
      { reason }
    );
    return response.data.data;
  },
};
