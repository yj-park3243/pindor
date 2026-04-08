import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
} from 'antd';
import type { TableColumnsType } from 'antd';
import { SearchOutlined, EyeOutlined, StopOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useGameList, useVoidGame } from '@/hooks/useGames';
import { ConfirmAction } from '@/components/ConfirmAction';
import { GAME_RESULT_STATUS_CONFIG, SPORT_TYPE_CONFIG } from '@/config/constants';
import type { Game, GameResultStatus } from '@/types/game';
import type { SportType } from '@/types/user';
import { ROUTES } from '@/config/routes';

const { Title, Text } = Typography;

export function GameListPage() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [resultStatus, setResultStatus] = useState<GameResultStatus | undefined>();
  const [sportType, setSportType] = useState<SportType | undefined>();
  const [page, setPage] = useState(1);
  const [voidTarget, setVoidTarget] = useState<Game | null>(null);

  const { data, isLoading } = useGameList({
    search: search || undefined,
    resultStatus,
    sportType,
    page,
    pageSize: 20,
  });

  const voidMutation = useVoidGame();

  const columns: TableColumnsType<Game> = [
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
      title: '장소',
      dataIndex: 'venueName',
      key: 'venueName',
      render: (v: string | null) => v || <Text type="secondary">미확정</Text>,
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
      title: '경기 상태',
      dataIndex: 'resultStatus',
      key: 'resultStatus',
      render: (s: GameResultStatus) => {
        const cfg = GAME_RESULT_STATUS_CONFIG[s];
        return <Tag color={cfg.color}>{cfg.label}</Tag>;
      },
      width: 120,
      filters: Object.entries(GAME_RESULT_STATUS_CONFIG).map(([value, { label }]) => ({
        text: label,
        value,
      })),
    },
    {
      title: '승자',
      key: 'winner',
      render: (_, record) => record.winner?.user?.nickname || '-',
      width: 120,
    },
    {
      title: '경기 일자',
      dataIndex: 'playedAt',
      key: 'playedAt',
      render: (d: string | null) => d ? dayjs(d).format('YYYY-MM-DD') : '-',
      sorter: true,
      width: 110,
    },
    {
      title: '증빙 수',
      key: 'proofs',
      render: (_, record) => (
        <Tag>{record.proofs?.length || 0}장</Tag>
      ),
      width: 80,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record) => (
        <Space>
          <Tooltip title="상세 / 이의신청 처리">
            <Button
              type="text"
              icon={<EyeOutlined />}
              onClick={() => navigate(`/games/${record.id}`)}
            />
          </Tooltip>
          {record.resultStatus !== 'VOIDED' && (
            <Tooltip title="무효 처리">
              <Button
                type="text"
                danger
                icon={<StopOutlined />}
                onClick={() => setVoidTarget(record)}
              />
            </Tooltip>
          )}
        </Space>
      ),
      width: 100,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        경기 결과 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        경기 결과 인증 현황 조회 및 관리
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="닉네임, 장소로 검색"
              prefix={<SearchOutlined />}
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              allowClear
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="결과 상태"
              style={{ width: '100%' }}
              allowClear
              value={resultStatus}
              onChange={(v) => { setResultStatus(v); setPage(1); }}
              options={Object.entries(GAME_RESULT_STATUS_CONFIG).map(([value, { label }]) => ({
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
          <Col xs={24} sm={6} lg={4}>
            <Button
              type="primary"
              onClick={() => navigate(ROUTES.GAME_REVIEW)}
            >
              이의 신청 처리
            </Button>
          </Col>
        </Row>
      </Card>

      <Card style={{ borderRadius: 8 }}>
        <Table
          columns={columns}
          dataSource={data?.items || []}
          loading={isLoading}
          rowKey="id"
          pagination={{
            current: page,
            pageSize: 20,
            total: data?.total || 0,
            showTotal: (total) => `총 ${total.toLocaleString()}건`,
            onChange: setPage,
          }}
          scroll={{ x: 900 }}
        />
      </Card>

      <ConfirmAction
        open={!!voidTarget}
        title="경기를 무효 처리하시겠습니까?"
        description="무효 처리 시 양측 점수 변동이 취소됩니다."
        requireReason
        reasonLabel="무효 처리 사유"
        onConfirm={async (reason) => {
          if (voidTarget && reason) {
            await voidMutation.mutateAsync({ gameId: voidTarget.id, reason });
            setVoidTarget(null);
          }
        }}
        onCancel={() => setVoidTarget(null)}
        loading={voidMutation.isPending}
        confirmText="무효 처리"
      />
    </div>
  );
}
