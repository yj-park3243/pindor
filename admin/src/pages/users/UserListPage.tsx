import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Typography,
  Card,
  Space,
  Button,
  Tag,
  Input,
  Select,
  DatePicker,
  Row,
  Col,
  Tooltip,
  Popconfirm,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { ProTable } from '@ant-design/pro-components';
import {
  SearchOutlined,
  EyeOutlined,
  StopOutlined,
  CheckCircleOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import { useUserList, useSuspendUser, useUnsuspendUser } from '@/hooks/useUsers';
import type { User, UserStatus, SportType } from '@/types/user';
import {
  USER_STATUS_CONFIG,
  SPORT_TYPE_CONFIG,
} from '@/config/constants';
import { UserAvatar } from '@/components/UserAvatar';
import { TierBadge } from '@/components/TierBadge';
import { ConfirmAction } from '@/components/ConfirmAction';
import type { Tier } from '@/types/user';

const { Title, Text } = Typography;
const { RangePicker } = DatePicker;

export function UserListPage() {
  const navigate = useNavigate();
  const [searchText, setSearchText] = useState('');
  const [statusFilter, setStatusFilter] = useState<UserStatus | undefined>();
  const [sportTypeFilter, setSportTypeFilter] = useState<SportType | undefined>();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [suspendTarget, setSuspendTarget] = useState<User | null>(null);

  const { data, isLoading, refetch } = useUserList({
    search: searchText || undefined,
    status: statusFilter,
    sportType: sportTypeFilter,
    page,
    pageSize,
  });

  const suspendMutation = useSuspendUser();
  const unsuspendMutation = useUnsuspendUser();

  const columns: TableColumnsType<User> = [
    {
      title: '사용자',
      dataIndex: 'nickname',
      key: 'nickname',
      render: (nickname: string, record: User) => (
        <UserAvatar
          src={record.profileImageUrl}
          nickname={nickname}
          size="small"
        />
      ),
    },
    {
      title: '이메일',
      dataIndex: 'email',
      key: 'email',
      render: (email: string | null) => email || <Text type="secondary">소셜 로그인</Text>,
    },
    {
      title: '스포츠 프로필',
      key: 'sportsProfiles',
      render: (_, record: User) => (
        <Space wrap>
          {record.sportsProfiles?.map((sp) => (
            <span key={sp.id}>
              <TierBadge tier={sp.tier as Tier} showScore score={sp.currentScore} />
              <Text type="secondary" style={{ fontSize: 11, marginLeft: 4 }}>
                {SPORT_TYPE_CONFIG[sp.sportType].label}
              </Text>
            </span>
          )) || <Text type="secondary">없음</Text>}
        </Space>
      ),
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (status: UserStatus) => {
        const config = USER_STATUS_CONFIG[status];
        return <Tag color={config.color}>{config.label}</Tag>;
      },
      filters: Object.entries(USER_STATUS_CONFIG).map(([value, { label }]) => ({
        text: label,
        value,
      })),
      width: 90,
    },
    {
      title: '가입일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (date: string) => dayjs(date).format('YYYY-MM-DD'),
      sorter: true,
      width: 120,
    },
    {
      title: '최근 접속',
      dataIndex: 'lastLoginAt',
      key: 'lastLoginAt',
      render: (date: string | null) =>
        date ? (
          <Tooltip title={dayjs(date).format('YYYY-MM-DD HH:mm:ss')}>
            <span>{dayjs(date).fromNow()}</span>
          </Tooltip>
        ) : (
          <Text type="secondary">없음</Text>
        ),
      width: 120,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record: User) => (
        <Space>
          <Tooltip title="상세 보기">
            <Button
              type="text"
              icon={<EyeOutlined />}
              onClick={() => navigate(`/users/${record.id}`)}
            />
          </Tooltip>

          {record.status === 'ACTIVE' ? (
            <Tooltip title="정지">
              <Button
                type="text"
                danger
                icon={<StopOutlined />}
                onClick={() => setSuspendTarget(record)}
              />
            </Tooltip>
          ) : record.status === 'SUSPENDED' ? (
            <Popconfirm
              title="정지를 해제하시겠습니까?"
              onConfirm={() => unsuspendMutation.mutate(record.id)}
              okText="해제"
              cancelText="취소"
            >
              <Tooltip title="정지 해제">
                <Button type="text" icon={<CheckCircleOutlined />} style={{ color: '#52c41a' }} />
              </Tooltip>
            </Popconfirm>
          ) : null}
        </Space>
      ),
      width: 100,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        사용자 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        전체 사용자 목록 조회 및 관리
      </Text>

      {/* 검색/필터 영역 */}
      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="닉네임, 이메일로 검색"
              prefix={<SearchOutlined />}
              value={searchText}
              onChange={(e) => {
                setSearchText(e.target.value);
                setPage(1);
              }}
              allowClear
            />
          </Col>
          <Col xs={24} sm={6} lg={4}>
            <Select
              placeholder="상태 필터"
              style={{ width: '100%' }}
              allowClear
              value={statusFilter}
              onChange={(val) => {
                setStatusFilter(val);
                setPage(1);
              }}
              options={Object.entries(USER_STATUS_CONFIG).map(([value, { label }]) => ({
                value,
                label,
              }))}
            />
          </Col>
          <Col xs={24} sm={6} lg={4}>
            <Select
              placeholder="종목 필터"
              style={{ width: '100%' }}
              allowClear
              value={sportTypeFilter}
              onChange={(val) => {
                setSportTypeFilter(val);
                setPage(1);
              }}
              options={Object.entries(SPORT_TYPE_CONFIG).map(([value, { label }]) => ({
                value,
                label,
              }))}
            />
          </Col>
          <Col xs={24} sm={12} lg={6}>
            <RangePicker style={{ width: '100%' }} />
          </Col>
          <Col xs={24} sm={6} lg={2}>
            <Button onClick={() => refetch()}>새로고침</Button>
          </Col>
        </Row>
      </Card>

      {/* 사용자 테이블 */}
      <Card style={{ borderRadius: 8 }}>
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary">
            총 {data?.total.toLocaleString() || 0}명
          </Text>
        </div>

        <ProTable<User>
          columns={columns}
          dataSource={data?.items || []}
          loading={isLoading}
          rowKey="id"
          search={false}
          toolBarRender={false}
          pagination={{
            current: page,
            pageSize,
            total: data?.total || 0,
            showSizeChanger: true,
            showQuickJumper: true,
            showTotal: (total) => `총 ${total.toLocaleString()}명`,
            onChange: (p, ps) => {
              setPage(p);
              setPageSize(ps);
            },
          }}
          onRow={(record) => ({
            onDoubleClick: () => navigate(`/users/${record.id}`),
            style: { cursor: 'pointer' },
          })}
          scroll={{ x: 900 }}
        />
      </Card>

      {/* 정지 확인 모달 */}
      <ConfirmAction
        open={!!suspendTarget}
        title={`'${suspendTarget?.nickname}' 사용자를 정지하시겠습니까?`}
        description="정지된 사용자는 서비스 이용이 제한됩니다."
        requireReason
        reasonLabel="정지 사유"
        reasonPlaceholder="정지 사유를 입력해주세요. (예: 허위 경기 결과 입력)"
        onConfirm={async (reason) => {
          if (suspendTarget && reason) {
            await suspendMutation.mutateAsync({
              id: suspendTarget.id,
              reason,
            });
            setSuspendTarget(null);
          }
        }}
        onCancel={() => setSuspendTarget(null)}
        loading={suspendMutation.isPending}
        confirmText="정지"
      />
    </div>
  );
}

