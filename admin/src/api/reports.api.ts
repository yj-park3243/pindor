import apiClient from '@/config/api';
import type { Report, ReportListFilter, ReportStatus } from '@/types/report';
import type { PaginatedResponse } from '@/types/common';

export interface ReportListParams extends ReportListFilter {
  page?: number;
  pageSize?: number;
}

export interface ReportResolveRequest {
  status: ReportStatus;
  note?: string;
}

export const reportsApi = {
  // 신고 목록 조회
  getList: async (params?: ReportListParams): Promise<PaginatedResponse<Report>> => {
    const response = await apiClient.get('/admin/reports', { params });
    return response.data.data;
  },

  // 신고 상세 조회
  getDetail: async (id: string): Promise<Report> => {
    const response = await apiClient.get(`/admin/reports/${id}`);
    return response.data.data;
  },

  // 신고 처리
  resolve: async (id: string, data: ReportResolveRequest): Promise<Report> => {
    const response = await apiClient.patch(`/admin/reports/${id}/resolve`, data);
    return response.data.data;
  },
};
