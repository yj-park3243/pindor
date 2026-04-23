import { useState, useEffect } from 'react';
import {
  Typography,
  Card,
  Select,
  Row,
  Col,
  Button,
  Tag,
  Space,
  Table,
  Modal,
  Descriptions,
  Form,
  Input,
  Alert,
  Image,
  Radio,
  InputNumber,
  Divider,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { CheckOutlined, EyeOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { disputesApi } from '@/api/disputes.api';
import type { Dispute, DisputeStatus, DisputeResolution } from '@/api/disputes.api';

const { Title, Text } = Typography;
const { TextArea } = Input;

const STATUS_CONFIG: Record<DisputeStatus, { label: string; color: string }> = {
  PENDING: { label: '대기', color: 'orange' },
  IN_PROGRESS: { label: '처리중', color: 'blue' },
  RESOLVED: { label: '완료', color: 'green' },
};

type ResolutionAction = DisputeResolution['action'];

export function DisputeListPage() {
  const [status, setStatus] = useState<DisputeStatus | undefined>();
  const [page, setPage] = useState(1);
  const [selectedDispute, setSelectedDispute] = useState<Dispute | null>(null);
  const [form] = Form.useForm<{
    status: 'IN_PROGRESS' | 'RESOLVED';
    adminReply?: string;
    action: ResolutionAction;
    winnerProfileId?: string;
    requesterScore?: number;
    opponentScore?: number;
  }>();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-disputes', status, page],
    queryFn: () => disputesApi.list({ status, page, pageSize: 20 }),
    // 캐시 유지 시간 짧게 — 새로고침 시 stale 데이터 보이지 않도록
    staleTime: 10_000,
    refetchOnWindowFocus: true,
  });

  const updateMutation = useMutation({
    mutationFn: ({
      id,
      ...body
    }: { id: string } & {
      status: 'IN_PROGRESS' | 'RESOLVED';
      adminReply?: string;
      resolution?: DisputeResolution;
    }) => disputesApi.update(id, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-disputes'] });
      setSelectedDispute(null);
      form.resetFields();
    },
  });

  const watchedStatus = Form.useWatch('status', form);
  const watchedAction = Form.useWatch('action', form);

  useEffect(() => {
    if (!selectedDispute) return;
    form.setFieldsValue({
      status:
        selectedDispute.status === 'PENDING'
          ? 'IN_PROGRESS'
          : (selectedDispute.status as 'IN_PROGRESS' | 'RESOLVED'),
      adminReply: selectedDispute.adminReply ?? '',
      action: 'KEEP_ORIGINAL',
    });
  }, [selectedDispute, form]);

  const handleUpdate = async (values: {
    status: 'IN_PROGRESS' | 'RESOLVED';
    adminReply?: string;
    action: ResolutionAction;
    winnerProfileId?: string;
    requesterScore?: number;
    opponentScore?: number;
  }) => {
    if (!selectedDispute) return;
    const payload: {
      status: 'IN_PROGRESS' | 'RESOLVED';
      adminReply?: string;
      resolution?: DisputeResolution;
    } = {
      status: values.status,
      adminReply: values.adminReply,
    };
    if (values.status === 'RESOLVED' && selectedDispute.match) {
      payload.resolution = {
        action: values.action,
        ...(values.action === 'MODIFY_RESULT' && {
          winnerProfileId: values.winnerProfileId,
          requesterScore: values.requesterScore,
          opponentScore: values.opponentScore,
        }),
      };
    }
    await updateMutation.mutateAsync({ id: selectedDispute.id, ...payload });
  };

  const columns: TableColumnsType<Dispute> = [
    {
      title: '종목',
      key: 'sportType',
      render: (_, record) =>
        record.match?.sportType ? <Tag>{record.match.sportType}</Tag> : '-',
      width: 100,
    },
    {
      title: '요청자',
      key: 'requester',
      render: (_, record) => record.reporter?.nickname || '-',
      width: 140,
    },
    {
      title: '상대방',
      key: 'opponent',
      render: (_, record) => {
        if (!record.match || !record.reporter) return '-';
        // 신고자가 requester면 opponent가 상대방, 반대도 마찬가지
        const rep = record.reporter.id;
        const isReq = record.match.requester.userId === rep;
        const counterpart = isReq
          ? record.match.opponent.nickname
          : record.match.requester.nickname;
        return counterpart || '-';
      },
      width: 140,
    },
    {
      title: '이의 신청 사유',
      dataIndex: 'title',
      key: 'title',
      render: (title: string) => (
        <Text ellipsis style={{ maxWidth: 260 }}>
          {title}
        </Text>
      ),
      ellipsis: true,
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (s: DisputeStatus) => {
        const cfg = STATUS_CONFIG[s];
        return <Tag color={cfg.color}>{cfg.label}</Tag>;
      },
      width: 90,
    },
    {
      title: '신청일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      width: 110,
    },
    {
      title: '증빙 수',
      key: 'imageCount',
      render: (_, record) => `${record.imageUrls?.length ?? 0}장`,
      width: 80,
    },
    {
      title: '검토',
      key: 'action',
      render: (_, record) => (
        <Button
          size="small"
          type={record.status === 'PENDING' ? 'primary' : 'default'}
          icon={<EyeOutlined />}
          onClick={() => setSelectedDispute(record)}
          disabled={record.status === 'RESOLVED'}
        >
          검토
        </Button>
      ),
      width: 80,
    },
  ];

  const matchInfo = selectedDispute?.match ?? null;

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        이의 신청 처리 큐
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        경기 결과 이의 신청 건을 검토하고 처리합니다.
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="상태"
              style={{ width: '100%' }}
              allowClear
              value={status}
              onChange={(v) => {
                setStatus(v);
                setPage(1);
              }}
              options={Object.entries(STATUS_CONFIG).map(([value, { label }]) => ({
                value,
                label,
              }))}
            />
          </Col>
        </Row>
      </Card>

      <Card style={{ borderRadius: 8 }}>
        {(data?.items?.filter((d) => d.status === 'PENDING')?.length ?? 0) > 0 && (
          <Alert
            message={`처리 대기: ${data?.items?.filter((d) => d.status === 'PENDING')?.length ?? 0}건`}
            type="warning"
            showIcon
            style={{ marginBottom: 12 }}
          />
        )}
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
          scroll={{ x: 1100 }}
        />
      </Card>

      {/* 처리 모달 */}
      <Modal
        open={!!selectedDispute}
        onCancel={() => {
          setSelectedDispute(null);
          form.resetFields();
        }}
        title="이의 신청 검토"
        width={720}
        footer={[
          <Button
            key="cancel"
            onClick={() => {
              setSelectedDispute(null);
              form.resetFields();
            }}
          >
            취소
          </Button>,
          <Button
            key="submit"
            type="primary"
            loading={updateMutation.isPending}
            icon={<CheckOutlined />}
            onClick={() => form.submit()}
            disabled={selectedDispute?.status === 'RESOLVED'}
          >
            {watchedStatus === 'RESOLVED' ? '완료 처리' : '저장'}
          </Button>,
        ]}
      >
        {selectedDispute && (
          <div>
            <Descriptions column={1} size="small" style={{ marginBottom: 16 }} bordered>
              <Descriptions.Item label="제목">
                {selectedDispute.title}
              </Descriptions.Item>
              <Descriptions.Item label="신고자 (요청자)">
                {selectedDispute.reporter?.nickname || '-'}
                {selectedDispute.phoneNumber && (
                  <Text type="secondary" style={{ marginLeft: 8, fontSize: 12 }}>
                    ({selectedDispute.phoneNumber})
                  </Text>
                )}
              </Descriptions.Item>
              {matchInfo && (
                <>
                  <Descriptions.Item label="종목">
                    <Tag>{matchInfo.sportType}</Tag>
                  </Descriptions.Item>
                  <Descriptions.Item label="매칭 참가자">
                    <Space direction="vertical" size={4} style={{ width: '100%' }}>
                      <Space>
                        <Tag color="blue">요청자</Tag>
                        <Text strong>{matchInfo.requester.nickname}</Text>
                        {matchInfo.requester.claimedResult && (
                          <Text type="secondary">
                            주장: {matchInfo.requester.claimedResult}
                            {matchInfo.requester.score != null &&
                              ` / ${matchInfo.requester.score}점`}
                          </Text>
                        )}
                      </Space>
                      <Space>
                        <Tag color="magenta">상대방</Tag>
                        <Text strong>{matchInfo.opponent.nickname}</Text>
                        {matchInfo.opponent.claimedResult && (
                          <Text type="secondary">
                            주장: {matchInfo.opponent.claimedResult}
                            {matchInfo.opponent.score != null &&
                              ` / ${matchInfo.opponent.score}점`}
                          </Text>
                        )}
                      </Space>
                      {matchInfo.game?.winnerProfileId && (
                        <Space>
                          <Tag color="green">현재 승자</Tag>
                          <Text>
                            {matchInfo.game.winnerProfileId ===
                            matchInfo.requester.profileId
                              ? matchInfo.requester.nickname
                              : matchInfo.opponent.nickname}
                          </Text>
                        </Space>
                      )}
                    </Space>
                  </Descriptions.Item>
                </>
              )}
              <Descriptions.Item label="매칭 ID">
                <Text copyable style={{ fontSize: 12, fontFamily: 'monospace' }}>
                  {selectedDispute.matchId}
                </Text>
              </Descriptions.Item>
              <Descriptions.Item label="내용">
                <Text style={{ whiteSpace: 'pre-wrap' }}>
                  {selectedDispute.content}
                </Text>
              </Descriptions.Item>
              <Descriptions.Item label="등록일">
                {dayjs(selectedDispute.createdAt).format('YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
            </Descriptions>

            {selectedDispute.imageUrls && selectedDispute.imageUrls.length > 0 && (
              <div style={{ marginBottom: 16 }}>
                <Text strong style={{ display: 'block', marginBottom: 8 }}>
                  첨부 이미지
                </Text>
                <Space>
                  <Image.PreviewGroup>
                    {selectedDispute.imageUrls.map((url, i) => (
                      <Image
                        key={i}
                        src={url}
                        width={80}
                        height={80}
                        style={{ objectFit: 'cover', borderRadius: 6 }}
                      />
                    ))}
                  </Image.PreviewGroup>
                </Space>
              </div>
            )}

            <Form
              form={form}
              layout="vertical"
              onFinish={handleUpdate}
              initialValues={{ action: 'KEEP_ORIGINAL' }}
            >
              <Form.Item
                name="status"
                label="처리 상태"
                rules={[{ required: true, message: '처리 상태를 선택해주세요.' }]}
              >
                <Select disabled={selectedDispute.status === 'RESOLVED'}>
                  <Select.Option value="IN_PROGRESS">
                    <Space>
                      <Tag color="blue">처리중</Tag>
                      <Text type="secondary" style={{ fontSize: 12 }}>
                        검토 중입니다
                      </Text>
                    </Space>
                  </Select.Option>
                  <Select.Option value="RESOLVED">
                    <Space>
                      <Tag color="green">완료</Tag>
                      <Text type="secondary" style={{ fontSize: 12 }}>
                        게임 결과도 확정됩니다
                      </Text>
                    </Space>
                  </Select.Option>
                </Select>
              </Form.Item>

              {watchedStatus === 'RESOLVED' && matchInfo && (
                <>
                  <Divider style={{ margin: '12px 0' }}>게임 결과 확정</Divider>

                  <Form.Item
                    name="action"
                    label="처리 방식"
                    rules={[{ required: true }]}
                  >
                    <Radio.Group>
                      <Space direction="vertical">
                        <Radio value="KEEP_ORIGINAL">
                          기존 결과 유지 (VERIFIED)
                        </Radio>
                        <Radio value="MODIFY_RESULT">
                          승자를 관리자가 지정 (점수 반영)
                        </Radio>
                        <Radio value="VOID_GAME">
                          경기 무효 처리 (양측 점수 변동 없음)
                        </Radio>
                      </Space>
                    </Radio.Group>
                  </Form.Item>

                  {watchedAction === 'MODIFY_RESULT' && (
                    <>
                      <Form.Item
                        name="winnerProfileId"
                        label="승자 선택"
                        rules={[{ required: true, message: '승자를 선택해주세요.' }]}
                      >
                        <Radio.Group>
                          <Space direction="vertical">
                            <Radio value={matchInfo.requester.profileId}>
                              요청자 승 — {matchInfo.requester.nickname}
                            </Radio>
                            <Radio value={matchInfo.opponent.profileId}>
                              상대방 승 — {matchInfo.opponent.nickname}
                            </Radio>
                          </Space>
                        </Radio.Group>
                      </Form.Item>

                      <Row gutter={12}>
                        <Col span={12}>
                          <Form.Item
                            name="requesterScore"
                            label={`${matchInfo.requester.nickname} 점수`}
                          >
                            <InputNumber
                              min={0}
                              style={{ width: '100%' }}
                              placeholder="예: 3"
                            />
                          </Form.Item>
                        </Col>
                        <Col span={12}>
                          <Form.Item
                            name="opponentScore"
                            label={`${matchInfo.opponent.nickname} 점수`}
                          >
                            <InputNumber
                              min={0}
                              style={{ width: '100%' }}
                              placeholder="예: 1"
                            />
                          </Form.Item>
                        </Col>
                      </Row>
                    </>
                  )}
                </>
              )}

              <Form.Item name="adminReply" label="관리자 답변 (신청자에게 노출)">
                <TextArea
                  rows={4}
                  placeholder="사용자에게 전달할 답변을 입력해주세요."
                  showCount
                  maxLength={1000}
                  disabled={selectedDispute.status === 'RESOLVED'}
                />
              </Form.Item>
            </Form>
          </div>
        )}
      </Modal>
    </div>
  );
}
