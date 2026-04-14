import { useState } from 'react';
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
} from 'antd';
import type { TableColumnsType } from 'antd';
import { CheckOutlined, EyeOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { disputesApi } from '@/api/disputes.api';
import type { Dispute, DisputeStatus } from '@/api/disputes.api';

const { Title, Text } = Typography;
const { TextArea } = Input;

const STATUS_CONFIG: Record<DisputeStatus, { label: string; color: string }> = {
  PENDING: { label: '대기', color: 'orange' },
  IN_PROGRESS: { label: '처리중', color: 'blue' },
  RESOLVED: { label: '완료', color: 'green' },
};

export function DisputeListPage() {
  const [status, setStatus] = useState<DisputeStatus | undefined>();
  const [page, setPage] = useState(1);
  const [selectedDispute, setSelectedDispute] = useState<Dispute | null>(null);
  const [form] = Form.useForm();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-disputes', status, page],
    queryFn: () => disputesApi.list({ status, page, pageSize: 20 }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...body }: { id: string; status: 'IN_PROGRESS' | 'RESOLVED'; adminReply?: string }) =>
      disputesApi.update(id, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-disputes'] });
      setSelectedDispute(null);
      form.resetFields();
    },
  });

  const handleUpdate = async (values: { status: 'IN_PROGRESS' | 'RESOLVED'; adminReply?: string }) => {
    if (!selectedDispute) return;
    await updateMutation.mutateAsync({ id: selectedDispute.id, ...values });
  };

  const columns: TableColumnsType<Dispute> = [
    {
      title: '제목',
      dataIndex: 'title',
      key: 'title',
      render: (title: string) => (
        <Text ellipsis style={{ maxWidth: 200 }}>
          {title}
        </Text>
      ),
    },
    {
      title: '신고자',
      key: 'reporter',
      render: (_, record) => record.reporter?.nickname || '-',
      width: 120,
    },
    {
      title: '매칭 ID',
      dataIndex: 'matchId',
      key: 'matchId',
      render: (id: string) => (
        <Text
          copyable
          style={{ fontSize: 11, fontFamily: 'monospace', color: '#666' }}
        >
          {id.slice(0, 8)}…
        </Text>
      ),
      width: 130,
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
      title: '등록일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      sorter: true,
      width: 110,
    },
    {
      title: '액션',
      key: 'action',
      render: (_, record) => (
        <Button
          size="small"
          type={record.status === 'PENDING' ? 'primary' : 'default'}
          icon={record.status === 'PENDING' ? <CheckOutlined /> : <EyeOutlined />}
          onClick={() => {
            setSelectedDispute(record);
            form.setFieldsValue({
              status: record.status === 'PENDING' ? 'IN_PROGRESS' : record.status,
              adminReply: record.adminReply ?? '',
            });
          }}
          disabled={record.status === 'RESOLVED'}
        >
          {record.status === 'PENDING' ? '처리' : record.status === 'IN_PROGRESS' ? '처리중' : '완료'}
        </Button>
      ),
      width: 90,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        의의 제기 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        경기 결과 의의 제기 목록 조회 및 처리
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
            message={`처리 대기 의의 제기 ${data?.items?.filter((d) => d.status === 'PENDING')?.length ?? 0}건이 있습니다.`}
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
          scroll={{ x: 800 }}
        />
      </Card>

      {/* 처리 모달 */}
      <Modal
        open={!!selectedDispute}
        onCancel={() => {
          setSelectedDispute(null);
          form.resetFields();
        }}
        title="의의 제기 처리"
        width={600}
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
            저장
          </Button>,
        ]}
      >
        {selectedDispute && (
          <div>
            <Descriptions column={1} size="small" style={{ marginBottom: 16 }}>
              <Descriptions.Item label="제목">
                {selectedDispute.title}
              </Descriptions.Item>
              <Descriptions.Item label="신고자">
                {selectedDispute.reporter?.nickname || '-'}
                {selectedDispute.phoneNumber && (
                  <Text type="secondary" style={{ marginLeft: 8, fontSize: 12 }}>
                    ({selectedDispute.phoneNumber})
                  </Text>
                )}
              </Descriptions.Item>
              <Descriptions.Item label="매칭 ID">
                <Text
                  copyable
                  style={{ fontSize: 12, fontFamily: 'monospace' }}
                >
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

            <Form form={form} layout="vertical" onFinish={handleUpdate}>
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
                        처리가 완료되었습니다
                      </Text>
                    </Space>
                  </Select.Option>
                </Select>
              </Form.Item>

              <Form.Item name="adminReply" label="관리자 답변">
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
