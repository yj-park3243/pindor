import { useState } from 'react';
import {
  Typography,
  Card,
  Row,
  Col,
  Select,
  Table,
  Tag,
  Space,
  Button,
  Alert,
  Tabs,
  Popconfirm,
  Drawer,
  Descriptions,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { WarningOutlined, CheckCircleOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useRankingList, useAnomalyList, useResolveAnomaly, useResetSeason } from '@/hooks/useRankings';
import { usePinList } from '@/hooks/usePins';
import { TierBadge } from '@/components/TierBadge';
import { UserAvatar } from '@/components/UserAvatar';
import { SPORT_TYPE_CONFIG, TIER_CONFIG } from '@/config/constants';
import type { RankingEntry, RankingAnomalyFlag } from '@/types/ranking';
import type { SportType, Tier } from '@/types/user';

const { Title, Text } = Typography;

const ANOMALY_FLAG_CONFIG = {
  FREQUENT_SAME_OPPONENT: { label: '동일 상대 반복', color: 'orange' },
  LARGE_SCORE_GAP: { label: '점수 차 과대', color: 'default' },
  SAME_DEVICE: { label: '동일 기기 다계정', color: 'red' },
  RAPID_SCORE_GAIN: { label: '점수 급상승', color: 'orange' },
} as const;

const SEVERITY_CONFIG = {
  LOW: { label: '낮음', color: 'default' },
  MEDIUM: { label: '중간', color: 'orange' },
  HIGH: { label: '높음', color: 'red' },
} as const;

export function RankingPage() {
  const [pinId, setPinId] = useState<string | undefined>();
  const [sportType, setSportType] = useState<SportType | undefined>();
  const [tier, setTier] = useState<Tier | undefined>();
  const [page, setPage] = useState(1);
  const [anomalyPage, setAnomalyPage] = useState(1);
  const [selectedAnomaly, setSelectedAnomaly] = useState<RankingAnomalyFlag | null>(null);
  const [resolveNote, setResolveNote] = useState('');

  const { data: pins } = usePinList({ pageSize: 100 });
  const { data: rankings, isLoading: rankingsLoading } = useRankingList({
    pinId,
    sportType,
    tier,
    page,
    pageSize: 20,
  });

  const { data: anomalies, isLoading: anomaliesLoading } = useAnomalyList({
    page: anomalyPage,
    pageSize: 15,
    isResolved: false,
  });

  const resolveAnomalyMutation = useResolveAnomaly();
  const resetSeasonMutation = useResetSeason();

  const rankingColumns: TableColumnsType<RankingEntry> = [
    {
      title: '순위',
      dataIndex: 'rank',
      key: 'rank',
      render: (rank: number) => (
        <strong style={{ color: rank <= 3 ? '#fa8c16' : undefined }}>
          {rank}위
        </strong>
      ),
      width: 70,
      sorter: true,
    },
    {
      title: '사용자',
      key: 'user',
      render: (_, record) => (
        <UserAvatar
          src={record.user?.profileImageUrl}
          nickname={record.user?.nickname || '-'}
          size="small"
        />
      ),
    },
    {
      title: '종목',
      dataIndex: 'sportType',
      key: 'sportType',
      render: (t: SportType) => SPORT_TYPE_CONFIG[t]?.label || t,
      width: 80,
    },
    {
      title: '티어',
      dataIndex: 'tier',
      key: 'tier',
      render: (t: Tier) => <TierBadge tier={t} />,
      width: 100,
    },
    {
      title: '점수',
      dataIndex: 'score',
      key: 'score',
      render: (s: number) => <strong style={{ color: '#1890ff' }}>{(s ?? 0).toLocaleString()}</strong>,
      sorter: true,
      width: 100,
    },
    {
      title: '경기 수',
      dataIndex: 'gamesPlayed',
      key: 'gamesPlayed',
      sorter: true,
      width: 90,
    },
    {
      title: '핀',
      dataIndex: 'pinName',
      key: 'pinName',
      width: 130,
    },
    {
      title: '갱신일',
      dataIndex: 'updatedAt',
      key: 'updatedAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      width: 110,
    },
  ];

  const anomalyColumns: TableColumnsType<RankingAnomalyFlag> = [
    {
      title: '사용자',
      key: 'user',
      render: (_, record) => record.nickname,
    },
    {
      title: '플래그 유형',
      dataIndex: 'flagType',
      key: 'flagType',
      render: (t) => {
        const cfg = ANOMALY_FLAG_CONFIG[t as keyof typeof ANOMALY_FLAG_CONFIG];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{t}</Tag>;
      },
      width: 140,
    },
    {
      title: '심각도',
      dataIndex: 'severity',
      key: 'severity',
      render: (s) => {
        const cfg = SEVERITY_CONFIG[s as keyof typeof SEVERITY_CONFIG];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{s}</Tag>;
      },
      width: 90,
    },
    {
      title: '설명',
      dataIndex: 'description',
      key: 'description',
      ellipsis: true,
    },
    {
      title: '감지일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      width: 110,
    },
    {
      title: '처리',
      key: 'action',
      render: (_, record) => (
        <Button
          size="small"
          icon={<CheckCircleOutlined />}
          onClick={() => setSelectedAnomaly(record)}
        >
          처리
        </Button>
      ),
      width: 80,
    },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
        <Title level={4} style={{ margin: 0 }}>
          랭킹 관리
        </Title>
        <Popconfirm
          title="시즌을 리셋하시겠습니까?"
          description="선택한 종목의 시즌 점수가 초기화됩니다."
          onConfirm={() => sportType && resetSeasonMutation.mutate(sportType)}
          okText="리셋"
          cancelText="취소"
          disabled={!sportType}
        >
          <Button
            danger
            disabled={!sportType}
            loading={resetSeasonMutation.isPending}
          >
            시즌 리셋
          </Button>
        </Popconfirm>
      </div>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        핀별 랭킹 현황 및 이상 감지 관리
      </Text>

      <Tabs
        defaultActiveKey="ranking"
        items={[
          {
            key: 'ranking',
            label: '랭킹 현황',
            children: (
              <div>
                <Card style={{ marginBottom: 16, borderRadius: 8 }}>
                  <Row gutter={[12, 12]}>
                    <Col xs={24} sm={12} lg={8}>
                      <Select
                        placeholder="핀 선택"
                        style={{ width: '100%' }}
                        allowClear
                        value={pinId}
                        onChange={(v) => { setPinId(v); setPage(1); }}
                        showSearch
                        optionFilterProp="label"
                        options={pins?.items?.map((p) => ({
                          value: p.id,
                          label: p.name,
                        })) || []}
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
                    <Col xs={12} sm={6} lg={4}>
                      <Select
                        placeholder="티어"
                        style={{ width: '100%' }}
                        allowClear
                        value={tier}
                        onChange={(v) => { setTier(v); setPage(1); }}
                        options={Object.entries(TIER_CONFIG).map(([value, { label }]) => ({
                          value, label,
                        }))}
                      />
                    </Col>
                  </Row>
                </Card>

                <Card style={{ borderRadius: 8 }}>
                  <Table
                    columns={rankingColumns}
                    dataSource={rankings?.items || []}
                    loading={rankingsLoading}
                    rowKey="id"
                    pagination={{
                      current: page,
                      pageSize: 20,
                      total: rankings?.total || 0,
                      showTotal: (total) => `총 ${(total ?? 0).toLocaleString()}명`,
                      onChange: setPage,
                    }}
                    scroll={{ x: 800 }}
                  />
                </Card>
              </div>
            ),
          },
          {
            key: 'anomaly',
            label: (
              <Space>
                이상 감지
                {anomalies && anomalies.total > 0 && (
                  <Tag color="red" style={{ margin: 0 }}>{anomalies.total}</Tag>
                )}
              </Space>
            ),
            children: (
              <div>
                {anomalies && anomalies.total > 0 && (
                  <Alert
                    message={`처리 대기 이상 감지 ${anomalies.total}건`}
                    type="warning"
                    showIcon
                    icon={<WarningOutlined />}
                    style={{ marginBottom: 16 }}
                  />
                )}
                <Card style={{ borderRadius: 8 }}>
                  <Table
                    columns={anomalyColumns}
                    dataSource={anomalies?.items || []}
                    loading={anomaliesLoading}
                    rowKey="id"
                    pagination={{
                      current: anomalyPage,
                      pageSize: 15,
                      total: anomalies?.total || 0,
                      onChange: setAnomalyPage,
                    }}
                    scroll={{ x: 700 }}
                  />
                </Card>
              </div>
            ),
          },
        ]}
      />

      {/* 이상 감지 처리 드로어 */}
      <Drawer
        open={!!selectedAnomaly}
        onClose={() => { setSelectedAnomaly(null); setResolveNote(''); }}
        title="이상 감지 처리"
        width={480}
        extra={
          <Button
            type="primary"
            onClick={async () => {
              if (selectedAnomaly) {
                await resolveAnomalyMutation.mutateAsync({
                  id: selectedAnomaly.id,
                  note: resolveNote,
                });
                setSelectedAnomaly(null);
                setResolveNote('');
              }
            }}
            loading={resolveAnomalyMutation.isPending}
          >
            처리 완료
          </Button>
        }
      >
        {selectedAnomaly && (
          <div>
            <Descriptions column={1} size="small" style={{ marginBottom: 16 }}>
              <Descriptions.Item label="사용자">{selectedAnomaly.nickname}</Descriptions.Item>
              <Descriptions.Item label="플래그 유형">
                {ANOMALY_FLAG_CONFIG[selectedAnomaly.flagType as keyof typeof ANOMALY_FLAG_CONFIG]?.label}
              </Descriptions.Item>
              <Descriptions.Item label="심각도">
                <Tag color={SEVERITY_CONFIG[selectedAnomaly.severity]?.color}>
                  {SEVERITY_CONFIG[selectedAnomaly.severity]?.label}
                </Tag>
              </Descriptions.Item>
              <Descriptions.Item label="설명">{selectedAnomaly.description}</Descriptions.Item>
              <Descriptions.Item label="감지일">
                {dayjs(selectedAnomaly.createdAt).format('YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
            </Descriptions>

            <div>
              <Text strong>처리 메모</Text>
              <textarea
                style={{
                  width: '100%',
                  marginTop: 8,
                  padding: 8,
                  border: '1px solid #d9d9d9',
                  borderRadius: 8,
                  fontSize: 14,
                  minHeight: 80,
                  resize: 'vertical',
                }}
                placeholder="처리 내용을 기록해주세요."
                value={resolveNote}
                onChange={(e) => setResolveNote(e.target.value)}
              />
            </div>
          </div>
        )}
      </Drawer>
    </div>
  );
}
