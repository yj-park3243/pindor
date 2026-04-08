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
  Modal,
  Form,
  InputNumber,
  Table,
  Alert,
  Tooltip,
} from 'antd';
import type { TableColumnsType } from 'antd';
import {
  SearchOutlined,
  EditOutlined,
  HistoryOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { profilesApi } from '@/api/profiles.api';
import { TierBadge } from '@/components/TierBadge';
import { UserAvatar } from '@/components/UserAvatar';
import { SPORT_TYPE_CONFIG, TIER_CONFIG } from '@/config/constants';
import type { SportsProfile } from '@/types/user';
import type { Tier, SportType } from '@/types/user';
import { message } from 'antd';

const { Title, Text } = Typography;
const { TextArea } = Input;

interface ScoreAdjustFormValues {
  adjustment: number;
  reason: string;
}

export function ProfileListPage() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [sportType, setSportType] = useState<SportType | undefined>();
  const [tier, setTier] = useState<Tier | undefined>();
  const [page, setPage] = useState(1);
  const [pageSize] = useState(20);
  const [adjustTarget, setAdjustTarget] = useState<SportsProfile | null>(null);
  const [historyTarget, setHistoryTarget] = useState<SportsProfile | null>(null);
  const [adjustForm] = Form.useForm<ScoreAdjustFormValues>();

  const { data, isLoading } = useQuery({
    queryKey: ['profiles', 'list', { search, sportType, tier, page, pageSize }],
    queryFn: () => profilesApi.getList({ search, sportType, tier, page, pageSize }),
  });

  const { data: scoreHistory, isLoading: historyLoading } = useQuery({
    queryKey: ['profiles', historyTarget?.id, 'score-history'],
    queryFn: () => profilesApi.getScoreHistory(historyTarget!.id),
    enabled: !!historyTarget,
  });

  const adjustMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: ScoreAdjustFormValues }) =>
      profilesApi.adjustScore(id, data),
    onSuccess: () => {
      message.success('점수가 조정되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      setAdjustTarget(null);
      adjustForm.resetFields();
    },
    onError: () => {
      message.error('점수 조정에 실패했습니다.');
    },
  });

  const columns: TableColumnsType<SportsProfile> = [
    {
      title: '사용자',
      key: 'user',
      render: (_, record) => (
        <UserAvatar
          src={undefined}
          nickname={record.displayName}
          tier={record.tier as Tier}
          showTier
        />
      ),
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
      width: 100,
    },
    {
      title: '티어',
      dataIndex: 'tier',
      key: 'tier',
      render: (tier: Tier) => <TierBadge tier={tier} />,
      width: 100,
    },
    {
      title: '현재 점수',
      dataIndex: 'currentScore',
      key: 'currentScore',
      render: (score: number) => (
        <strong style={{ color: '#1890ff' }}>{score.toLocaleString()}</strong>
      ),
      sorter: true,
      width: 110,
    },
    {
      title: '경기 수',
      dataIndex: 'gamesPlayed',
      key: 'gamesPlayed',
      sorter: true,
      width: 90,
    },
    {
      title: '승/패',
      key: 'record',
      render: (_, record) => (
        <Space>
          <Tag color="green">{record.wins}승</Tag>
          <Tag color="red">{record.losses}패</Tag>
        </Space>
      ),
      width: 110,
    },
    {
      title: 'G핸디',
      dataIndex: 'gHandicap',
      key: 'gHandicap',
      render: (v: number | null) => v !== null ? v.toFixed(1) : '-',
      width: 80,
    },
    {
      title: '인증',
      dataIndex: 'isVerified',
      key: 'isVerified',
      render: (v: boolean) => (
        <Tag color={v ? 'green' : 'default'}>{v ? '인증' : '미인증'}</Tag>
      ),
      width: 80,
    },
    {
      title: '생성일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('YYYY-MM-DD'),
      width: 110,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record) => (
        <Space>
          <Tooltip title="점수 수동 조정">
            <Button
              type="text"
              icon={<EditOutlined />}
              onClick={() => setAdjustTarget(record)}
            />
          </Tooltip>
          <Tooltip title="점수 히스토리">
            <Button
              type="text"
              icon={<HistoryOutlined />}
              onClick={() => setHistoryTarget(record)}
            />
          </Tooltip>
        </Space>
      ),
      width: 100,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        스포츠 프로필 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        사용자 스포츠 프로필 목록 및 점수 수동 조정
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="닉네임, 프로필명으로 검색"
              prefix={<SearchOutlined />}
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              allowClear
            />
          </Col>
          <Col xs={24} sm={6} lg={4}>
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
          columns={columns}
          dataSource={data?.items || []}
          loading={isLoading}
          rowKey="id"
          pagination={{
            current: page,
            pageSize,
            total: data?.total || 0,
            showTotal: (total) => `총 ${total.toLocaleString()}개`,
            onChange: setPage,
          }}
          scroll={{ x: 1000 }}
        />
      </Card>

      {/* 점수 수동 조정 모달 */}
      <Modal
        open={!!adjustTarget}
        title={`점수 수동 조정 — ${adjustTarget?.displayName}`}
        onOk={() => adjustForm.submit()}
        onCancel={() => { setAdjustTarget(null); adjustForm.resetFields(); }}
        okText="조정 적용"
        cancelText="취소"
        confirmLoading={adjustMutation.isPending}
        destroyOnHide
      >
        {adjustTarget && (
          <>
            <Alert
              message={`현재 점수: ${adjustTarget.currentScore.toLocaleString()}점 (${TIER_CONFIG[adjustTarget.tier as Tier]?.label} 티어)`}
              type="info"
              showIcon
              style={{ marginBottom: 16 }}
            />
            <Form
              form={adjustForm}
              layout="vertical"
              onFinish={(values) =>
                adjustMutation.mutate({ id: adjustTarget.id, data: values })
              }
            >
              <Form.Item
                name="adjustment"
                label="조정 점수 (양수: 증가, 음수: 감소)"
                rules={[
                  { required: true, message: '조정 점수를 입력해주세요.' },
                  {
                    validator: (_, v) =>
                      v !== 0
                        ? Promise.resolve()
                        : Promise.reject(new Error('0점은 입력할 수 없습니다.')),
                  },
                ]}
              >
                <InputNumber
                  style={{ width: '100%' }}
                  min={-500}
                  max={500}
                  placeholder="-100 ~ 100"
                  addonAfter="점"
                />
              </Form.Item>
              <Form.Item
                name="reason"
                label="조정 사유 (필수)"
                rules={[{ required: true, message: '사유를 반드시 입력해야 합니다.' }]}
              >
                <TextArea
                  rows={3}
                  placeholder="점수 조정 사유를 상세히 입력해주세요."
                  showCount
                  maxLength={500}
                />
              </Form.Item>
            </Form>
          </>
        )}
      </Modal>

      {/* 점수 히스토리 모달 */}
      <Modal
        open={!!historyTarget}
        title={`점수 히스토리 — ${historyTarget?.displayName}`}
        onCancel={() => setHistoryTarget(null)}
        footer={null}
        width={700}
      >
        <Table
          dataSource={scoreHistory?.items || []}
          loading={historyLoading}
          rowKey="id"
          size="small"
          columns={[
            {
              title: '날짜',
              dataIndex: 'createdAt',
              render: (d: string) => dayjs(d).format('YYYY-MM-DD HH:mm'),
            },
            {
              title: '이전 점수',
              dataIndex: 'previousScore',
              render: (v: number) => v.toLocaleString(),
            },
            {
              title: '변동',
              dataIndex: 'change',
              render: (v: number) => (
                <span style={{ color: v > 0 ? '#52c41a' : '#ff4d4f' }}>
                  {v > 0 ? '+' : ''}{v}
                </span>
              ),
            },
            {
              title: '새 점수',
              dataIndex: 'newScore',
              render: (v: number) => <strong>{v.toLocaleString()}</strong>,
            },
            {
              title: '사유',
              dataIndex: 'reason',
              ellipsis: true,
            },
          ]}
          pagination={{ pageSize: 10 }}
          locale={{ emptyText: '점수 히스토리가 없습니다.' }}
        />
      </Modal>
    </div>
  );
}
