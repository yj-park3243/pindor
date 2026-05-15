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
} from 'antd';
import type { TableColumnsType } from 'antd';
import { EyeOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { inquiriesApi } from '@/api/inquiries.api';
import type { Inquiry, InquiryStatus, InquiryCategory } from '@/api/inquiries.api';

const { Title, Text, Paragraph } = Typography;
const { TextArea } = Input;

const STATUS_CONFIG: Record<InquiryStatus, { label: string; color: string }> = {
  OPEN: { label: '대기', color: 'orange' },
  IN_PROGRESS: { label: '처리중', color: 'blue' },
  RESOLVED: { label: '완료', color: 'green' },
  CLOSED: { label: '종료', color: 'default' },
};

const CATEGORY_LABEL: Record<InquiryCategory, string> = {
  ACCOUNT: '계정',
  MATCH: '매칭',
  SCORE: '점수',
  BUG: '버그',
  SUGGESTION: '건의',
  OTHER: '기타',
};

export function InquiryListPage() {
  const [status, setStatus] = useState<InquiryStatus | undefined>();
  const [category, setCategory] = useState<InquiryCategory | undefined>();
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Inquiry | null>(null);
  const [form] = Form.useForm<{ status: InquiryStatus; adminReply?: string }>();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-inquiries', status, category, page],
    queryFn: () => inquiriesApi.list({ status, category, page, pageSize: 20 }),
    staleTime: 10_000,
    refetchOnWindowFocus: true,
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...body }: { id: string; status?: InquiryStatus; adminReply?: string }) =>
      inquiriesApi.update(id, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-inquiries'] });
      setSelected(null);
      form.resetFields();
    },
  });

  const openDetail = (inquiry: Inquiry) => {
    setSelected(inquiry);
    form.setFieldsValue({
      status: inquiry.status === 'OPEN' ? 'IN_PROGRESS' : inquiry.status,
      adminReply: inquiry.adminReply ?? '',
    });
  };

  const handleSubmit = async () => {
    if (!selected) return;
    const values = await form.validateFields();
    updateMutation.mutate({
      id: selected.id,
      status: values.status,
      adminReply: values.adminReply?.trim() || undefined,
    });
  };

  const columns: TableColumnsType<Inquiry> = [
    {
      title: '카테고리',
      dataIndex: 'category',
      key: 'category',
      width: 90,
      render: (c: InquiryCategory) => <Tag>{CATEGORY_LABEL[c] ?? c}</Tag>,
    },
    {
      title: '제목',
      dataIndex: 'title',
      key: 'title',
      ellipsis: true,
    },
    {
      title: '문의자',
      key: 'user',
      width: 180,
      render: (_, record) => (
        <div>
          <div>{record.user?.nickname ?? '-'}</div>
          <Text type="secondary" style={{ fontSize: 12 }}>{record.user?.email ?? ''}</Text>
        </div>
      ),
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      width: 90,
      render: (s: InquiryStatus) => {
        const cfg = STATUS_CONFIG[s];
        return <Tag color={cfg.color}>{cfg.label}</Tag>;
      },
    },
    {
      title: '접수일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      width: 160,
      render: (v: string) => dayjs(v).format('YYYY-MM-DD HH:mm'),
    },
    {
      title: '액션',
      key: 'action',
      width: 80,
      render: (_, record) => (
        <Button type="link" icon={<EyeOutlined />} onClick={() => openDetail(record)}>
          상세
        </Button>
      ),
    },
  ];

  return (
    <div>
      <Title level={3}>문의 관리</Title>

      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16}>
          <Col span={6}>
            <Select
              allowClear
              placeholder="상태 필터"
              style={{ width: '100%' }}
              value={status}
              onChange={(v) => { setStatus(v); setPage(1); }}
              options={(Object.keys(STATUS_CONFIG) as InquiryStatus[]).map((k) => ({
                value: k,
                label: STATUS_CONFIG[k].label,
              }))}
            />
          </Col>
          <Col span={6}>
            <Select
              allowClear
              placeholder="카테고리 필터"
              style={{ width: '100%' }}
              value={category}
              onChange={(v) => { setCategory(v); setPage(1); }}
              options={(Object.keys(CATEGORY_LABEL) as InquiryCategory[]).map((k) => ({
                value: k,
                label: CATEGORY_LABEL[k],
              }))}
            />
          </Col>
        </Row>
      </Card>

      <Card>
        <Table
          rowKey="id"
          loading={isLoading}
          columns={columns}
          dataSource={data?.items ?? []}
          pagination={{
            current: page,
            pageSize: 20,
            total: data?.total ?? 0,
            onChange: setPage,
            showSizeChanger: false,
          }}
        />
      </Card>

      <Modal
        open={!!selected}
        title="문의 상세"
        onCancel={() => setSelected(null)}
        onOk={handleSubmit}
        okText="저장"
        cancelText="닫기"
        confirmLoading={updateMutation.isPending}
        width={720}
      >
        {selected && (
          <>
            <Descriptions column={2} size="small" bordered>
              <Descriptions.Item label="카테고리">{CATEGORY_LABEL[selected.category]}</Descriptions.Item>
              <Descriptions.Item label="상태">
                <Tag color={STATUS_CONFIG[selected.status].color}>{STATUS_CONFIG[selected.status].label}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="문의자" span={2}>
                {selected.user?.nickname ?? '-'} ({selected.user?.email ?? ''})
              </Descriptions.Item>
              <Descriptions.Item label="제목" span={2}>{selected.title}</Descriptions.Item>
              <Descriptions.Item label="내용" span={2}>
                <Paragraph style={{ whiteSpace: 'pre-wrap', margin: 0 }}>{selected.content}</Paragraph>
              </Descriptions.Item>
              <Descriptions.Item label="접수일">
                {dayjs(selected.createdAt).format('YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
              <Descriptions.Item label="처리일">
                {selected.resolvedAt ? dayjs(selected.resolvedAt).format('YYYY-MM-DD HH:mm:ss') : '-'}
              </Descriptions.Item>
            </Descriptions>

            <Form form={form} layout="vertical" style={{ marginTop: 16 }}>
              <Form.Item
                name="status"
                label="상태"
                rules={[{ required: true, message: '상태를 선택하세요' }]}
              >
                <Select
                  options={(Object.keys(STATUS_CONFIG) as InquiryStatus[]).map((k) => ({
                    value: k,
                    label: STATUS_CONFIG[k].label,
                  }))}
                />
              </Form.Item>
              <Form.Item name="adminReply" label="어드민 답변">
                <TextArea rows={5} placeholder="문의자에게 보낼 답변을 입력하세요" maxLength={5000} showCount />
              </Form.Item>
            </Form>

            <Space style={{ marginTop: 8 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>
                * 현재 답변은 DB에만 저장됩니다. 사용자 알림 발송은 별건.
              </Text>
            </Space>
          </>
        )}
      </Modal>
    </div>
  );
}
