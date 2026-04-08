import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export type AdminRole = 'SUPER_ADMIN' | 'ADMIN' | 'MODERATOR';

export interface AdminUser {
  id: string;
  email: string;
  name: string;
  role: AdminRole;
  createdAt: string;
}

interface AuthState {
  isAuthenticated: boolean;
  admin: AdminUser | null;
  accessToken: string | null;
  refreshToken: string | null;

  // 로그인
  login: (admin: AdminUser, accessToken: string, refreshToken: string) => void;
  // 로그아웃
  logout: () => void;
  // 토큰 갱신
  setTokens: (accessToken: string, refreshToken: string) => void;
  // 역할 확인 유틸리티
  hasRole: (roles: AdminRole[]) => boolean;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      isAuthenticated: false,
      admin: null,
      accessToken: null,
      refreshToken: null,

      login: (admin, accessToken, refreshToken) => {
        set({
          isAuthenticated: true,
          admin,
          accessToken,
          refreshToken,
        });
      },

      logout: () => {
        set({
          isAuthenticated: false,
          admin: null,
          accessToken: null,
          refreshToken: null,
        });
      },

      setTokens: (accessToken, refreshToken) => {
        set({ accessToken, refreshToken });
      },

      hasRole: (roles) => {
        const { admin } = get();
        if (!admin) return false;
        return roles.includes(admin.role);
      },
    }),
    {
      name: 'admin-auth',
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        admin: state.admin,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
      }),
    }
  )
);
