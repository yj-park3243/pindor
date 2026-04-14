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
  Row,
  Col,
  Tooltip,
  Avatar,
  Popconfirm,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { ProTable } from '@ant-design/pro-components';
import {
  SearchOutlined,
  EyeOutlined,
  StopOutlined,
  DeleteOutlined,
  CheckCircleOutlined,
  TeamOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import { useTeams, useSuspendTeam, useActivateTeam, useDisbandTeam } from '@/hooks/useTeams';
import type { Team, TeamStatus } from '@/types/team';
import { SPORT_TYPE_CONFIG } from '@/config/constants';
import { ConfirmAction } from '@/components/ConfirmAction';

const { Title, Text } = Typography;

// 팀 상태 설정
const TEAM_STATUS_CONFIG: Record<TeamStatus, { label: string; color: string }> = {
  ACTIVE: { label: '활성', color: 'green' },
  INACTIVE: { label: '비활성', color: 'orange' },
  DISBANDED: { label: '해산', color: 'red' },
};

export function TeamListPage() {
  const navigate = useNavigate();
  const [searchText, setSearchText] = useState('');
  const [statusFilter, setStatusFilter] = useState<TeamStatus | undefined>();
  const [sportTypeFilter, setSportTypeFilter] = useState<string | undefined>();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);

  // 액션 모달 상태
  const [suspendTarget, setSuspendTarget] = useState<Team | null>(null);
  const [disbandTarget, setDisbandTarget] = useState<Team | null>(null);

  const { data, isLoading, refetch } = useTeams({
    search: searchText || undefined,
    status: statusFilter,
    sportType: sportTypeFilter,
    page,
    pageSize,
  });

  const suspendMutation = useSuspendTeam();
  const activateMutation = useActivateTeam();
  const disbandMutation = useDisbandTeam();

  const columns: TableColumnsType<Team> = [
    {
      title: '팀',
      key: 'team',
      render: (_, record: Team) => (
        <Space>
          <Avatar
            src={record.logoUrl}
            icon={!record.logoUrl && <TeamOutlined />}
            size={36}
            style={{ background: '#1890ff', flexShrink: 0 }}
          />
          <div>
            <div style={{ fontWeight: 600, lineHeight: 1.4 }}>{record.name}</div>
            <div style={{ fontSize: 12, color: '#999' }}>@{record.slug}</div>
          </div>
        </Space>
      ),
    },
    {
      title: '종목',
      dataIndex: 'sportType',
      key: 'sportType',
      render: (sportType: string) => {
        const config = SPORT_TYPE_CONFIG[sportType as keyof typeof SPORT_TYPE_CONFIG];
        return config ? (
          <Space size={4}>
            <span>{config.icon}</span>
            <span>{config.label}</span>
          </Space>
        ) : (
          <Tag>{sportType}</Tag>
        );
      },
      width: 110,
    },
    {
      title: '멤버수',
      key: 'members',
      render: (_, record: Team) => (
        <Text>
          {record.currentMembers}
          <Text type="secondary">/{record.maxMembers}</Text>
        </Text>
      ),
      width: 80,
      align: 'center',
    },
    {
      title: 'ELO 점수',
      dataIndex: 'teamScore',
      key: 'teamScore',
      render: (score: number) => (
        <Text strong style={{ color: '#1890ff' }}>
          {(score ?? 0).toLocaleString()}
        </Text>
      ),
      sorter: true,
      width: 100,
      align: 'center',
    },
    {
      title: '전적',
      key: 'record',
      render: (_, record: Team) => (
        <Space size={4}>
          <Tag color="green" style={{ margin: 0 }}>{record.wins}승</Tag>
          <Tag color="red" style={{ margin: 0 }}>{record.losses}패</Tag>
          <Tag color="default" style={{ margin: 0 }}>{record.draws}무</Tag>
        </Space>
      ),
      width: 160,
    },
    {
      title: '모집 여부',
      dataIndex: 'isRecruiting',
      key: 'isRecruiting',
      render: (isRecruiting: boolean) => (
        <Tag color={isRecruiting ? 'blue' : 'default'}>
          {isRecruiting ? '모집중' : '모집 종료'}
        </Tag>
      ),
      width: 100,
      align: 'center',
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (status: TeamStatus) => {
        const config = TEAM_STATUS_CONFIG[status];
        return <Tag color={config.color}>{config.label}</Tag>;
      },
      width: 80,
      align: 'center',
    },
    {
      title: '생성일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (date: string) => dayjs(date).format('YYYY-MM-DD'),
      sorter: true,
      width: 110,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record: Team) => (
        <Space>
          <Tooltip title="상세 보기">
            <Button
              type="text"
              icon={<EyeOutlined />}
              onClick={() => navigate(`/teams/${record.id}`)}
            />
          </Tooltip>

          {record.status === 'ACTIVE' && (
            <Tooltip title="정지">
              <Button
                type="text"
                danger
                icon={<StopOutlined />}
                onClick={() => setSuspendTarget(record)}
              />
            </Tooltip>
          )}

          {record.status === 'INACTIVE' && (
            <Popconfirm
              title="팀을 활성화하시겠습니까?"
              onConfirm={() => activateMutation.mutate(record.id)}
              okText="활성화"
              cancelText="취소"
            >
              <Tooltip title="활성화">
                <Button
                  type="text"
                  icon={<CheckCircleOutlined />}
                  style={{ color: '#52c41a' }}
                />
              </Tooltip>
            </Popconfirm>
          )}

          {record.status !== 'DISBANDED' && (
            <Tooltip title="해산">
              <Button
                type="text"
                danger
                icon={<DeleteOutlined />}
                onClick={() => setDisbandTarget(record)}
              />
            </Tooltip>
          )}
        </Space>
      ),
      width: 130,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        팀 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        전체 팀 목록 조회 및 관리
      </Text>

      {/* 검색/필터 영역 */}
      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="팀명, 슬러그로 검색"
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
              options={Object.entries(TEAM_STATUS_CONFIG).map(([value, { label }]) => ({
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
          <Col xs={24} sm={6} lg={2}>
            <Button onClick={() => refetch()}>새로고침</Button>
          </Col>
        </Row>
      </Card>

      {/* 팀 테이블 */}
      <Card style={{ borderRadius: 8 }}>
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary">
            총 {(data?.total ?? 0).toLocaleString()}개 팀
          </Text>
        </div>

        <ProTable<Team>
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
            showTotal: (total) => `총 ${(total ?? 0).toLocaleString()}개 팀`,
            onChange: (p, ps) => {
              setPage(p);
              setPageSize(ps);
            },
          }}
          onRow={(record) => ({
            onDoubleClick: () => navigate(`/teams/${record.id}`),
            style: { cursor: 'pointer' },
          })}
          scroll={{ x: 1000 }}
        />
      </Card>

      {/* 팀 정지 확인 모달 */}
      <ConfirmAction
        open={!!suspendTarget}
        title={`'${suspendTarget?.name}' 팀을 정지하시겠습니까?`}
        description="정지된 팀은 매칭 및 활동이 제한됩니다."
        requireReason
        reasonLabel="정지 사유"
        reasonPlaceholder="정지 사유를 입력해주세요."
        onConfirm={async (reason) => {
          if (suspendTarget && reason) {
            await suspendMutation.mutateAsync({ teamId: suspendTarget.id, reason });
            setSuspendTarget(null);
          }
        }}
        onCancel={() => setSuspendTarget(null)}
        loading={suspendMutation.isPending}
        confirmText="정지"
      />

      {/* 팀 해산 확인 모달 */}
      <ConfirmAction
        open={!!disbandTarget}
        title={`'${disbandTarget?.name}' 팀을 해산하시겠습니까?`}
        description="해산된 팀은 복구할 수 없습니다. 신중하게 처리해주세요."
        requireReason
        reasonLabel="해산 사유"
        reasonPlaceholder="해산 사유를 입력해주세요."
        onConfirm={async (reason) => {
          if (disbandTarget && reason) {
            await disbandMutation.mutateAsync({ teamId: disbandTarget.id, reason });
            setDisbandTarget(null);
          }
        }}
        onCancel={() => setDisbandTarget(null)}
        loading={disbandMutation.isPending}
        confirmText="해산"
      />
    </div>
  );
}
