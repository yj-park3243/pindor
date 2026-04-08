// 공통 API 응답 타입

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  meta?: PaginationMeta;
}

export interface ApiError {
  success: false;
  error: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
}

export interface PaginationMeta {
  cursor?: string;
  hasMore: boolean;
  total?: number;
  page?: number;
  pageSize?: number;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export interface PageParams {
  page?: number;
  pageSize?: number;
  cursor?: string;
}

export interface GeoPoint {
  lat: number;
  lng: number;
}

export type SortOrder = 'ascend' | 'descend';

export interface SortParams {
  sortField?: string;
  sortOrder?: SortOrder;
}
