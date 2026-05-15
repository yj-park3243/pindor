import apiClient from '@/config/api';

export interface VersionCheckLog {
  id: string;
  userId: string | null;
  nickname: string | null;
  email: string | null;
  phoneNumber: string | null;
  platform: string;
  appVersion: string | null;
  latitude: number | null;
  longitude: number | null;
  ipAddress: string | null;
  userAgent: string | null;
  createdAt: string;
}

export interface VersionLogQuery {
  page?: number;
  pageSize?: number;
  platform?: string;
  userId?: string;
  hasLocation?: boolean;
}

export const versionLogsApi = {
  async list(params: VersionLogQuery): Promise<{
    items: VersionCheckLog[];
    total: number;
    page: number;
    pageSize: number;
  }> {
    const response = await apiClient.get('/admin/version-check-logs', { params });
    const body = response.data as {
      data: VersionCheckLog[];
      total: number;
      page: number;
      pageSize: number;
    };
    return {
      items: body.data,
      total: body.total,
      page: body.page,
      pageSize: body.pageSize,
    };
  },
};
