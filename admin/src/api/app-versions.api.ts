import apiClient from '@/config/api';

export interface AppVersion {
  id: string;
  platform: string; // IOS, ANDROID
  minVersion: string;
  latestVersion: string;
  latestBuild: number;
  forceUpdate: boolean;
  updateMessage: string | null;
  storeUrl: string | null;
  showAd: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface PatchAppVersion {
  minVersion?: string;
  latestVersion?: string;
  latestBuild?: number;
  forceUpdate?: boolean;
  updateMessage?: string | null;
  storeUrl?: string | null;
  showAd?: boolean;
}

export const appVersionsApi = {
  async list(): Promise<AppVersion[]> {
    const res = await apiClient.get('/admin/app-versions');
    return res.data.data as AppVersion[];
  },
  async update(id: string, body: PatchAppVersion): Promise<AppVersion> {
    const res = await apiClient.patch(`/admin/app-versions/${id}`, body);
    return res.data.data as AppVersion;
  },
};
