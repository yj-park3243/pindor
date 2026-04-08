import { useState } from 'react';
import { useSearchParams, useParams } from 'react-router-dom';
import {
  Typography,
  Card,
  Row,
  Col,
  Button,
  Tag,
  Space,
  Table,
  Alert,
  Drawer,
  Form,
  Input,
  Select,
  Divider,
  Descriptions,
  Badge,
  Empty,
} from 'antd';
import type { TableColumnsType } from 'antd';
import {
  CheckCircleOutlined,
  EditOutlined,
  StopOutlined,
  EyeOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import { useDisputeList, useResolveDispute } from '@/hooks/useGames';
import { PhotoViewer } from '@/components/PhotoViewer';
import { SPORT_TYPE_CONFIG, GAME_RESULT_STATUS_CONFIG } from '@/config/constants';
import type { Game } from '@/types/game';
import type { DisputeResolution } from '@/api/games.api';

const { Title, Text } = Typography;
const { TextArea } = Input;

type ResolutionOption = {
  value: DisputeResolution;
  label: string;
  color: string;
  description: string;
};

const RESOLUTION_OPTIONS: ResolutionOption[] = [
  {
    value: 'ORIGINAL',
    label: '원본 유지',
    color: 'blue',
    description: '기존 경기 결과를 그대로 확정합니다.',
  },
  {
    value: 'MODIFIED',
    label: '결과 수정',
    color: 'orange',
    description: '경기 결과를 수정한 후 점수를 재계산합니다.',
  },
  {
    value: 'VOIDED',
    label: '경기 무효',
    color: 'red',
    description: '경기를 무효 처리하고 양측 점수를 원복합니다.',
  },
];

export function GameReviewPage() {
  const [searchParams] = useSearchParams();
  const { id: paramGameId } = useParams<{ id: string }>();
  // 경로 파라미터(/games/:id) 우선, 없으면 쿼리스트링(?gameId=) 폴백
  const initialGameId = paramGameId || searchParams.get('gameId');

  const [page, setPage] = useState(1);
  const [selectedGame, setSelectedGame] = useState<Game | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(!!initialGameId);
  const [form] = Form.useForm();

  const { data, isLoading } = useDisputeList({ page, pageSize: 15 });
  const resolveMutation = useResolveDispute();

  const handleReview = (game: Game) => {
    setSelectedGame(game);
    setDrawerOpen(true);
  };

  const handleResolve = async (values: {
    resolution: DisputeResolution;
    adminNote: string;
  }) => {
    if (!selectedGame) return;
    await resolveMutation.mutateAsync({
      gameId: selectedGame.id,
      data: values,
    });
    setDrawerOpen(false);
    setSelectedGame(null);
    form.resetFields();
  };

  const columns: TableColumnsType<Game> = [
    {
      title: '종목',
      dataIndex: 'sportType',
      key: 'sportType',
      render: (t) => (
        <Space>
          <span>{SPORT_TYPE_CONFIG[t as keyof typeof SPORT_TYPE_CONFIG]?.icon}</span>
          <span>{SPORT_TYPE_CONFIG[t as keyof typeof SPORT_TYPE_CONFIG]?.label}</span>
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
      title: '이의 신청 사유',
      key: 'disputeReason',
      render: (_, record) => (
        <Text ellipsis style={{ maxWidth: 200 }}>
          {record.dispute?.reason || '-'}
        </Text>
      ),
    },
    {
      title: '상태',
      dataIndex: 'resultStatus',
      key: 'resultStatus',
      render: (s) => {
        const cfg = GAME_RESULT_STATUS_CONFIG[s as keyof typeof GAME_RESULT_STATUS_CONFIG];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{s}</Tag>;
      },
      width: 120,
    },
    {
      title: '신청일',
      key: 'disputedAt',
      render: (_, record) =>
        record.dispute?.createdAt
          ? dayjs(record.dispute.createdAt).format('MM-DD HH:mm')
          : '-',
      width: 110,
    },
    {
      title: '증빙 수',
      key: 'proofs',
      render: (_, record) => `${record.proofs?.length || 0}장`,
      width: 80,
    },
    {
      title: '검토',
      key: 'review',
      render: (_, record) => (
        <Button
          type="primary"
          size="small"
          icon={<EyeOutlined />}
          onClick={() => handleReview(record)}
        >
          검토
        </Button>
      ),
      width: 90,
    },
  ];

  const requesterProofs = selectedGame?.proofs?.filter(
    (p) => p.uploadedBy === selectedGame?.requesterProfile?.userId
  ) || [];
  const opponentProofs = selectedGame?.proofs?.filter(
    (p) => p.uploadedBy === selectedGame?.opponentProfile?.userId
  ) || [];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        이의 신청 처리 큐
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        경기 결과 이의 신청 건을 검토하고 처리합니다.
      </Text>

      {data && data.total === 0 ? (
        <Card style={{ borderRadius: 8 }}>
          <Empty
            description="처리 대기중인 이의 신청이 없습니다."
            image={Empty.PRESENTED_IMAGE_SIMPLE}
          />
        </Card>
      ) : (
        <Card style={{ borderRadius: 8 }}>
          <div style={{ marginBottom: 12 }}>
            <Space>
              <Badge status="processing" />
              <Text>처리 대기: {data?.total || 0}건</Text>
            </Space>
          </div>

          <Table
            columns={columns}
            dataSource={data?.items || []}
            loading={isLoading}
            rowKey="id"
            pagination={{
              current: page,
              pageSize: 15,
              total: data?.total || 0,
              onChange: setPage,
            }}
            scroll={{ x: 800 }}
          />
        </Card>
      )}

      {/* 검토 드로어 */}
      <Drawer
        open={drawerOpen}
        onClose={() => {
          setDrawerOpen(false);
          setSelectedGame(null);
          form.resetFields();
        }}
        title="이의 신청 검토"
        width={720}
        extra={
          <Button
            type="primary"
            onClick={() => form.submit()}
            loading={resolveMutation.isPending}
            icon={<CheckCircleOutlined />}
          >
            결정 확정
          </Button>
        }
      >
        {selectedGame && (
          <div>
            {/* 경기 기본 정보 */}
            <Card size="small" style={{ marginBottom: 16, background: '#fafafa' }}>
              <Descriptions column={2} size="small">
                <Descriptions.Item label="종목">
                  {SPORT_TYPE_CONFIG[selectedGame.sportType as keyof typeof SPORT_TYPE_CONFIG]?.label}
                </Descriptions.Item>
                <Descriptions.Item label="장소">
                  {selectedGame.venueName || '-'}
                </Descriptions.Item>
                <Descriptions.Item label="요청자">
                  {selectedGame.requesterProfile?.user?.nickname || '-'}
                </Descriptions.Item>
                <Descriptions.Item label="상대방">
                  {selectedGame.opponentProfile?.user?.nickname || '-'}
                </Descriptions.Item>
                <Descriptions.Item label="이의 신청 사유" span={2}>
                  <Text type="danger">{selectedGame.dispute?.reason || '-'}</Text>
                </Descriptions.Item>
              </Descriptions>
            </Card>

            <Divider>증빙 사진 비교</Divider>

            {/* 증빙 사진 비교 뷰 */}
            <PhotoViewer
              compareMode
              groups={[
                {
                  label: `요청자 (${selectedGame.requesterProfile?.user?.nickname}) 제출`,
                  urls: requesterProofs.map((p) => p.imageUrl),
                },
                {
                  label: `상대방 (${selectedGame.opponentProfile?.user?.nickname}) 제출`,
                  urls: opponentProofs.map((p) => p.imageUrl),
                },
              ]}
              title="증빙 사진"
            />

            {/* 이의 신청자 추가 증빙 */}
            {selectedGame.dispute?.evidenceImageUrls &&
              selectedGame.dispute.evidenceImageUrls.length > 0 && (
                <>
                  <Divider>이의 신청 추가 증빙</Divider>
                  <PhotoViewer urls={selectedGame.dispute.evidenceImageUrls} />
                </>
              )}

            <Divider>처리 결정</Divider>

            <Form form={form} layout="vertical" onFinish={handleResolve}>
              <Form.Item
                name="resolution"
                label="처리 결정"
                rules={[{ required: true, message: '처리 방식을 선택해주세요.' }]}
              >
                <Select placeholder="처리 방식 선택">
                  {RESOLUTION_OPTIONS.map((opt) => (
                    <Select.Option key={opt.value} value={opt.value}>
                      <Space>
                        <Tag color={opt.color} style={{ marginRight: 0 }}>{opt.label}</Tag>
                        <Text type="secondary" style={{ fontSize: 12 }}>{opt.description}</Text>
                      </Space>
                    </Select.Option>
                  ))}
                </Select>
              </Form.Item>

              <Form.Item
                name="adminNote"
                label="처리 메모 (양측에게 공개됩니다)"
                rules={[{ required: true, message: '처리 메모를 입력해주세요.' }]}
              >
                <TextArea
                  rows={4}
                  placeholder="처리 결정 근거와 메모를 입력해주세요."
                  showCount
                  maxLength={1000}
                />
              </Form.Item>

              <Alert
                type="warning"
                message="결정 확정 후에는 변경할 수 없습니다. 신중히 검토해주세요."
                showIcon
                style={{ marginBottom: 12 }}
              />

              {/* 결정 버튼 3종 */}
              <Row gutter={8}>
                <Col span={8}>
                  <Button
                    block
                    icon={<CheckCircleOutlined />}
                    style={{ borderColor: '#1890ff', color: '#1890ff' }}
                    onClick={() => {
                      form.setFieldValue('resolution', 'ORIGINAL');
                    }}
                  >
                    원본 유지
                  </Button>
                </Col>
                <Col span={8}>
                  <Button
                    block
                    icon={<EditOutlined />}
                    style={{ borderColor: '#fa8c16', color: '#fa8c16' }}
                    onClick={() => {
                      form.setFieldValue('resolution', 'MODIFIED');
                    }}
                  >
                    결과 수정
                  </Button>
                </Col>
                <Col span={8}>
                  <Button
                    block
                    danger
                    icon={<StopOutlined />}
                    onClick={() => {
                      form.setFieldValue('resolution', 'VOIDED');
                    }}
                  >
                    경기 무효
                  </Button>
                </Col>
              </Row>
            </Form>
          </div>
        )}
      </Drawer>
    </div>
  );
}
