import apiClient from '@/config/api';
import type { Pin, PinStats, PinListFilter } from '@/types/pin';
import type { PaginatedResponse } from '@/types/common';

export interface PinListParams extends PinListFilter {
  page?: number;
  pageSize?: number;
  bounds?: { north: number; south: number; east: number; west: number };
}

export interface PinCreateRequest {
  name: string;
  center: { lat: number; lng: number };
  boundary?: GeoJSON.Polygon;
  level: string;
  parentPinId?: string;
}

export interface PinUpdateRequest extends Partial<PinCreateRequest> {
  isActive?: boolean;
}

export const pinsApi = {
  // 핀 목록 조회
  getList: async (params?: PinListParams): Promise<PaginatedResponse<Pin>> => {
    const response = await apiClient.get('/admin/pins', { params });
    return response.data.data;
  },

  // 핀 상세 조회
  getDetail: async (id: string): Promise<Pin> => {
    const response = await apiClient.get(`/admin/pins/${id}`);
    return response.data.data;
  },

  // 핀 통계 조회
  getStats: async (id: string): Promise<PinStats> => {
    const response = await apiClient.get(`/admin/pins/${id}/stats`);
    return response.data.data;
  },

  // 핀 생성
  create: async (data: PinCreateRequest): Promise<Pin> => {
    const response = await apiClient.post('/admin/pins', data);
    return response.data.data;
  },

  // 핀 수정
  update: async (id: string, data: PinUpdateRequest): Promise<Pin> => {
    const response = await apiClient.patch(`/admin/pins/${id}`, data);
    return response.data.data;
  },

  // 핀 활성화
  activate: async (id: string): Promise<Pin> => {
    const response = await apiClient.patch(`/admin/pins/${id}/activate`);
    return response.data.data;
  },

  // 핀 비활성화
  deactivate: async (id: string): Promise<Pin> => {
    const response = await apiClient.patch(`/admin/pins/${id}/deactivate`);
    return response.data.data;
  },
};
