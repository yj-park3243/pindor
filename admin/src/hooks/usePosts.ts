import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { postsApi, type PostListParams } from '@/api/posts.api';

export const POST_QUERY_KEYS = {
  all: ['posts'] as const,
  list: (params?: PostListParams) => ['posts', 'list', params] as const,
  detail: (id: string) => ['posts', 'detail', id] as const,
  comments: (postId: string) => ['posts', postId, 'comments'] as const,
};

export function usePostList(params?: PostListParams) {
  return useQuery({
    queryKey: POST_QUERY_KEYS.list(params),
    queryFn: () => postsApi.getList(params),
  });
}

export function usePostDetail(id: string) {
  return useQuery({
    queryKey: POST_QUERY_KEYS.detail(id),
    queryFn: () => postsApi.getDetail(id),
    enabled: !!id,
  });
}

export function usePostComments(postId: string) {
  return useQuery({
    queryKey: POST_QUERY_KEYS.comments(postId),
    queryFn: () => postsApi.getComments(postId),
    enabled: !!postId,
  });
}

export function useDeletePost() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      postsApi.delete(id, reason),
    onSuccess: () => {
      message.success('게시글이 삭제되었습니다.');
      queryClient.invalidateQueries({ queryKey: POST_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('게시글 삭제에 실패했습니다.');
    },
  });
}

export function useBlindPost() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      postsApi.blind(id, reason),
    onSuccess: (_, { id }) => {
      message.success('게시글이 블라인드 처리되었습니다.');
      queryClient.invalidateQueries({ queryKey: POST_QUERY_KEYS.detail(id) });
      queryClient.invalidateQueries({ queryKey: POST_QUERY_KEYS.all });
    },
    onError: () => {
      message.error('블라인드 처리에 실패했습니다.');
    },
  });
}

export function useDeleteComment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ postId, commentId, reason }: { postId: string; commentId: string; reason: string }) =>
      postsApi.deleteComment(postId, commentId, reason),
    onSuccess: (_, { postId }) => {
      message.success('댓글이 삭제되었습니다.');
      queryClient.invalidateQueries({ queryKey: POST_QUERY_KEYS.comments(postId) });
    },
    onError: () => {
      message.error('댓글 삭제에 실패했습니다.');
    },
  });
}
