import { useState } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import {
  Layout,
  Menu,
  Avatar,
  Dropdown,
  Typography,
  Badge,
  Space,
  Button,
} from 'antd';
import {
  DashboardOutlined,
  UserOutlined,
  TeamOutlined,
  SwapOutlined,
  TrophyOutlined,
  PushpinOutlined,
  FileTextOutlined,
  AlertOutlined,
  RiseOutlined,
  BellOutlined,
  BarChartOutlined,
  SettingOutlined,
  MenuFoldOutlined,
  MenuUnfoldOutlined,
  LogoutOutlined,
  ProfileOutlined,
  NotificationOutlined,
  AuditOutlined,
} from '@ant-design/icons';
import type { MenuProps } from 'antd';
import { useAuthStore } from '@/store/auth.store';
import { authApi } from '@/api/auth.api';
import { ROUTES } from '@/config/routes';
import { ADMIN_ROLE_CONFIG } from '@/config/constants';

const { Header, Sider, Content } = Layout;
const { Text } = Typography;

// 메뉴 아이템 정의
function buildMenuItems(role: string): MenuProps['items'] {
  const isModerator = role === 'MODERATOR';

  const items: MenuProps['items'] = [
    {
      key: ROUTES.DASHBOARD,
      icon: <DashboardOutlined />,
      label: '대시보드',
    },
    {
      key: 'users-group',
      icon: <TeamOutlined />,
      label: '사용자 관리',
      children: [
        { key: ROUTES.USERS, icon: <UserOutlined />, label: '사용자 목록' },
        { key: ROUTES.PROFILES, icon: <ProfileOutlined />, label: '스포츠 프로필' },
      ],
    },
    {
      key: 'match-group',
      icon: <SwapOutlined />,
      label: '매칭/경기',
      children: [
        { key: ROUTES.MATCHES, icon: <SwapOutlined />, label: '매칭 관리' },
        { key: ROUTES.GAMES, icon: <TrophyOutlined />, label: '경기 결과' },
        { key: ROUTES.GAME_REVIEW, icon: <AlertOutlined />, label: '이의 신청 처리' },
      ],
    },
    {
      key: 'team-group',
      icon: <TeamOutlined />,
      label: '팀 관리',
      children: [
        { key: ROUTES.TEAMS, icon: <TeamOutlined />, label: '팀 목록' },
        { key: ROUTES.TEAM_MATCHES, icon: <SwapOutlined />, label: '팀 매칭' },
      ],
    },
    {
      key: 'community-group',
      icon: <PushpinOutlined />,
      label: '커뮤니티',
      children: [
        { key: ROUTES.PINS, icon: <PushpinOutlined />, label: '핀 관리' },
        { key: ROUTES.POSTS, icon: <FileTextOutlined />, label: '게시판 관리' },
        { key: ROUTES.REPORTS, icon: <AlertOutlined />, label: '신고 처리' },
        { key: ROUTES.DISPUTES, icon: <AuditOutlined />, label: '의의 제기' },
      ],
    },
    {
      key: ROUTES.RANKINGS,
      icon: <RiseOutlined />,
      label: '랭킹 관리',
    },
    {
      key: ROUTES.NOTICES,
      icon: <NotificationOutlined />,
      label: '공지사항',
    },
    {
      key: ROUTES.NOTIFICATIONS,
      icon: <BellOutlined />,
      label: '알림 발송',
    },
    {
      key: ROUTES.STATISTICS,
      icon: <BarChartOutlined />,
      label: '통계/분석',
    },
  ];

  if (!isModerator) {
    items.push({
      key: 'settings-group',
      icon: <SettingOutlined />,
      label: '설정',
      children: [
        { key: ROUTES.SETTINGS_ACCOUNTS, icon: <UserOutlined />, label: '어드민 계정' },
        { key: ROUTES.SETTINGS_SYSTEM, icon: <SettingOutlined />, label: '시스템 설정' },
      ],
    });
  }

  return items;
}

export function AdminLayout() {
  const [collapsed, setCollapsed] = useState(false);
  const navigate = useNavigate();
  const location = useLocation();
  const { admin, logout } = useAuthStore();

  const handleLogout = async () => {
    try {
      await authApi.logout();
    } catch {
      // 로그아웃 API 실패해도 로컬 로그아웃 진행
    }
    logout();
    navigate(ROUTES.LOGIN);
  };

  const profileMenu: MenuProps = {
    items: [
      {
        key: 'profile',
        icon: <UserOutlined />,
        label: '내 계정',
      },
      { type: 'divider' },
      {
        key: 'logout',
        icon: <LogoutOutlined />,
        label: '로그아웃',
        danger: true,
        onClick: handleLogout,
      },
    ],
  };

  const menuItems = buildMenuItems(admin?.role || 'MODERATOR');

  // 현재 경로에 맞는 메뉴 키 찾기
  const selectedKey = location.pathname;
  const openKeys = menuItems
    ?.filter(
      (item) =>
        item &&
        'children' in item &&
        Array.isArray((item as { children?: { key?: string }[] }).children) &&
        (item as { children?: { key?: string }[] }).children!.some(
          (child) => child.key === selectedKey
        )
    )
    .map((item) => item?.key as string) || [];

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider
        trigger={null}
        collapsible
        collapsed={collapsed}
        width={240}
        style={{
          background: '#001529',
          position: 'fixed',
          left: 0,
          top: 0,
          bottom: 0,
          zIndex: 100,
          overflowY: 'auto',
        }}
      >
        {/* 로고 영역 */}
        <div
          style={{
            height: 64,
            display: 'flex',
            alignItems: 'center',
            justifyContent: collapsed ? 'center' : 'flex-start',
            padding: collapsed ? 0 : '0 24px',
            borderBottom: '1px solid rgba(255,255,255,0.1)',
          }}
        >
          <span style={{ fontSize: 20 }}>⛳</span>
          {!collapsed && (
            <Text
              strong
              style={{
                color: '#fff',
                marginLeft: 12,
                fontSize: 16,
                whiteSpace: 'nowrap',
              }}
            >
              PINDOR Admin
            </Text>
          )}
        </div>

        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[selectedKey]}
          defaultOpenKeys={openKeys}
          items={menuItems}
          onClick={({ key }) => navigate(key)}
          style={{ borderRight: 0, marginTop: 8 }}
        />
      </Sider>

      <Layout style={{ marginLeft: collapsed ? 80 : 240, transition: 'margin 0.2s' }}>
        <Header
          style={{
            background: '#fff',
            padding: '0 24px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            boxShadow: '0 1px 4px rgba(0,0,0,0.1)',
            position: 'sticky',
            top: 0,
            zIndex: 99,
          }}
        >
          <Button
            type="text"
            icon={collapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
            onClick={() => setCollapsed(!collapsed)}
            style={{ fontSize: 16 }}
          />

          <Space size={16}>
            <Badge count={0} size="small">
              <Button type="text" icon={<BellOutlined />} style={{ fontSize: 18 }} />
            </Badge>

            <Dropdown menu={profileMenu} placement="bottomRight" trigger={['click']}>
              <Space style={{ cursor: 'pointer' }}>
                <Avatar
                  size="small"
                  icon={<UserOutlined />}
                  style={{ background: '#1890ff' }}
                />
                <div style={{ lineHeight: 1.2 }}>
                  <div style={{ fontSize: 13, fontWeight: 600 }}>{admin?.name}</div>
                  <div style={{ fontSize: 11, color: '#999' }}>
                    {admin?.role ? ADMIN_ROLE_CONFIG[admin.role].label : ''}
                  </div>
                </div>
              </Space>
            </Dropdown>
          </Space>
        </Header>

        <Content
          style={{
            padding: 24,
            minHeight: 'calc(100vh - 64px)',
            background: '#f5f5f5',
          }}
        >
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  );
}
