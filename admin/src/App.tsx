import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuthStore } from '@/store/auth.store';
import { AdminLayout } from '@/layouts/AdminLayout';
import { ROUTES } from '@/config/routes';

// 페이지 임포트
import { LoginPage } from '@/pages/login/LoginPage';
import { DashboardPage } from '@/pages/dashboard/DashboardPage';
import { UserListPage } from '@/pages/users/UserListPage';
import { UserDetailPage } from '@/pages/users/UserDetailPage';
import { ProfileListPage } from '@/pages/profiles/ProfileListPage';
import { MatchListPage } from '@/pages/matches/MatchListPage';
import { GameListPage } from '@/pages/games/GameListPage';
import { GameReviewPage } from '@/pages/games/GameReviewPage';
import { PinListPage } from '@/pages/pins/PinListPage';
import { PostListPage } from '@/pages/posts/PostListPage';
import { ReportListPage } from '@/pages/reports/ReportListPage';
import { RankingPage } from '@/pages/rankings/RankingPage';
import { NotificationSendPage } from '@/pages/notifications/NotificationSendPage';
import { StatisticsPage } from '@/pages/statistics/StatisticsPage';
import { AdminAccountPage } from '@/pages/settings/AdminAccountPage';
import { SystemSettingsPage } from '@/pages/settings/SystemSettingsPage';
import { TeamListPage } from '@/pages/teams/TeamListPage';
import { TeamDetailPage } from '@/pages/teams/TeamDetailPage';
import { TeamMatchListPage } from '@/pages/teams/TeamMatchListPage';
import { NoticeListPage } from '@/pages/notices/NoticeListPage';
import { DisputeListPage } from '@/pages/disputes/DisputeListPage';

// 인증 가드 컴포넌트
function RequireAuth({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  if (!isAuthenticated) {
    return <Navigate to={ROUTES.LOGIN} replace />;
  }
  return <>{children}</>;
}

// 역할 기반 접근 제어 컴포넌트
function RequireRole({ children, roles }: { children: React.ReactNode; roles: string[] }) {
  const role = useAuthStore((s) => s.admin?.role);
  if (!role || !roles.includes(role)) {
    return <Navigate to={ROUTES.DASHBOARD} replace />;
  }
  return <>{children}</>;
}

// 로그인 상태에서 로그인 페이지 접근 시 대시보드로 리다이렉트
function RedirectIfAuth({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  if (isAuthenticated) {
    return <Navigate to={ROUTES.DASHBOARD} replace />;
  }
  return <>{children}</>;
}

export function App() {
  return (
    <Routes>
      {/* 로그인 페이지 */}
      <Route
        path={ROUTES.LOGIN}
        element={
          <RedirectIfAuth>
            <LoginPage />
          </RedirectIfAuth>
        }
      />

      {/* 어드민 레이아웃 (인증 필요) */}
      <Route
        path="/"
        element={
          <RequireAuth>
            <AdminLayout />
          </RequireAuth>
        }
      >
        {/* 루트 접근 시 대시보드로 이동 */}
        <Route index element={<Navigate to={ROUTES.DASHBOARD} replace />} />

        {/* 대시보드 */}
        <Route path={ROUTES.DASHBOARD} element={<DashboardPage />} />

        {/* 사용자 관리 */}
        <Route path={ROUTES.USERS} element={<UserListPage />} />
        <Route path={ROUTES.USER_DETAIL} element={<UserDetailPage />} />

        {/* 스포츠 프로필 */}
        <Route path={ROUTES.PROFILES} element={<ProfileListPage />} />

        {/* 매칭 관리 */}
        <Route path={ROUTES.MATCHES} element={<MatchListPage />} />

        {/* 경기 결과 관리 */}
        <Route path={ROUTES.GAMES} element={<GameListPage />} />
        <Route path={ROUTES.GAME_DETAIL} element={<GameReviewPage />} />
        <Route path={ROUTES.GAME_REVIEW} element={<GameReviewPage />} />

        {/* 핀 관리 */}
        <Route path={ROUTES.PINS} element={<PinListPage />} />

        {/* 게시판 관리 */}
        <Route path={ROUTES.POSTS} element={<PostListPage />} />

        {/* 신고 처리 */}
        <Route path={ROUTES.REPORTS} element={<ReportListPage />} />

        {/* 랭킹 관리 */}
        <Route path={ROUTES.RANKINGS} element={<RankingPage />} />

        {/* 알림 발송 */}
        <Route path={ROUTES.NOTIFICATIONS} element={<NotificationSendPage />} />

        {/* 통계 */}
        <Route path={ROUTES.STATISTICS} element={<StatisticsPage />} />

        {/* 팀 관리 */}
        <Route path={ROUTES.TEAMS} element={<TeamListPage />} />
        <Route path={ROUTES.TEAM_DETAIL} element={<TeamDetailPage />} />
        <Route path={ROUTES.TEAM_MATCHES} element={<TeamMatchListPage />} />

        {/* 공지사항 관리 */}
        <Route path={ROUTES.NOTICES} element={<NoticeListPage />} />

        {/* 의의 제기 관리 */}
        <Route path={ROUTES.DISPUTES} element={<DisputeListPage />} />

        {/* 설정 — SUPER_ADMIN, ADMIN만 접근 가능 */}
        <Route
          path={ROUTES.SETTINGS_ACCOUNTS}
          element={
            <RequireRole roles={['SUPER_ADMIN', 'ADMIN']}>
              <AdminAccountPage />
            </RequireRole>
          }
        />
        <Route
          path={ROUTES.SETTINGS_SYSTEM}
          element={
            <RequireRole roles={['SUPER_ADMIN', 'ADMIN']}>
              <SystemSettingsPage />
            </RequireRole>
          }
        />

        {/* 404 처리 */}
        <Route path="*" element={<Navigate to={ROUTES.DASHBOARD} replace />} />
      </Route>

      {/* 루트 접근 시 리다이렉트 */}
      <Route path="*" element={<Navigate to={ROUTES.LOGIN} replace />} />
    </Routes>
  );
}
