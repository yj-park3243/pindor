import { useState } from 'react';
import {
  Typography,
  Card,
  Input,
  Select,
  Row,
  Col,
  Button,
  Tag,
  Space,
  Table,
  Tooltip,
  Badge,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { SearchOutlined, CloseCircleOutlined, CheckCircleOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useMatchList, useForceCancel, useForceComplete } from '@/hooks/useMatches';
import { ConfirmAction } from '@/components/ConfirmAction';
import { MATCH_STATUS_CONFIG, SPORT_TYPE_CONFIG } from '@/config/constants';
import type { Match, MatchStatus } from '@/types/match';
import type { SportType } from '@/types/user';

const { Title, Text } = Typography;

export function MatchListPage() {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<MatchStatus | undefined>();
  const [sportType, setSportType] = useState<SportType | undefined>();
  const [page, setPage] = useState(1);
  const [cancelTarget, setCancelTarget] = useState<Match | null>(null);

  const { data, isLoading } = useMatchList({
    search: search || undefined,
    status,
    sportType,
    page,
    pageSize: 20,
  });

  const forceCancelMutation = useForceCancel();
  const forceCompleteMutation = useForceComplete();

  const columns: TableColumnsType<Match> = [
    {
      title: '매칭 ID',
      dataIndex: 'id',
      key: 'id',
      render: (id: string) => (
        <Text copyable={{ text: id }} style={{ fontSize: 12, fontFamily: 'monospace' }}>
          {id.slice(0, 8)}...
        </Text>
      ),
      width: 130,
    },
    {
      title: '종목',
      dataIndex: 'sportType',
      key: 'sportType',
      render: (t: SportType) => (
        <Space>
          <span>{SPORT_TYPE_CONFIG[t]?.icon}</span>
          <span>{SPORT_TYPE_CONFIG[t]?.label}</span>
        </Space>
      ),
      width: 90,
    },
    {
      title: '요청자',
      key: 'requester',
      render: (_, record) => record.requesterProfile?.user?.nickname || '-',
    },
    {
      title: '상대방',
      key: 'opponent',
      render: (_, record) => record.opponentProfile?.user?.nickname || '-',
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (s: MatchStatus) => {
        const cfg = MATCH_STATUS_CONFIG[s];
        return <Badge status="processing" text={<Tag color={cfg.color}>{cfg.label}</Tag>} />;
      },
      width: 110,
    },
    {
      title: '예정일',
      dataIndex: 'scheduledDate',
      key: 'scheduledDate',
      render: (d: string | null) => d ? dayjs(d).format('YYYY-MM-DD') : '-',
      width: 110,
    },
    {
      title: '생성일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('YYYY-MM-DD HH:mm'),
      sorter: true,
      width: 140,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record) => (
        <Space>
          {['CHAT', 'CONFIRMED'].includes(record.status) && (
            <>
              <Tooltip title="강제 취소">
                <Button
                  type="text"
                  danger
                  icon={<CloseCircleOutlined />}
                  onClick={() => setCancelTarget(record)}
                />
              </Tooltip>
              <Tooltip title="강제 완료">
                <Button
                  type="text"
                  icon={<CheckCircleOutlined />}
                  style={{ color: '#52c41a' }}
                  onClick={() => forceCompleteMutation.mutate(record.id)}
                  loading={forceCompleteMutation.isPending}
                />
              </Tooltip>
            </>
          )}
        </Space>
      ),
      width: 100,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        매칭 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        활성 매칭 현황 모니터링 및 강제 처리
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="사용자 닉네임으로 검색"
              prefix={<SearchOutlined />}
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              allowClear
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="상태"
              style={{ width: '100%' }}
              allowClear
              value={status}
              onChange={(v) => { setStatus(v); setPage(1); }}
              options={Object.entries(MATCH_STATUS_CONFIG).map(([value, { label }]) => ({
                value, label,
              }))}
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="종목"
              style={{ width: '100%' }}
              allowClear
              value={sportType}
              onChange={(v) => { setSportType(v); setPage(1); }}
              options={Object.entries(SPORT_TYPE_CONFIG).map(([value, { label }]) => ({
                value, label,
              }))}
            />
          </Col>
        </Row>
      </Card>

      <Card style={{ borderRadius: 8 }}>
        <div style={{ marginBottom: 12 }}>
          <Space>
            <Text type="secondary">총 {(data?.total ?? 0).toLocaleString()}건</Text>
            {['CHAT', 'CONFIRMED'].includes(status || '') && (
              <Tag color="blue">활성 매칭만 표시 중</Tag>
            )}
          </Space>
        </div>

        <Table
          columns={columns}
          dataSource={data?.items || []}
          loading={isLoading}
          rowKey="id"
          pagination={{
            current: page,
            pageSize: 20,
            total: data?.total || 0,
            showTotal: (total) => `총 ${(total ?? 0).toLocaleString()}건`,
            onChange: setPage,
          }}
          scroll={{ x: 900 }}
        />
      </Card>

      <ConfirmAction
        open={!!cancelTarget}
        title="매칭을 강제 취소하시겠습니까?"
        description="강제 취소된 매칭은 복구할 수 없으며, 양측 사용자에게 알림이 발송됩니다."
        requireReason
        reasonLabel="강제 취소 사유"
        onConfirm={async (reason) => {
          if (cancelTarget && reason) {
            await forceCancelMutation.mutateAsync({ id: cancelTarget.id, reason });
            setCancelTarget(null);
          }
        }}
        onCancel={() => setCancelTarget(null)}
        loading={forceCancelMutation.isPending}
        confirmText="강제 취소"
      />
    </div>
  );
}
