import { useState } from 'react';
import {
  Typography,
  Card,
  Form,
  Input,
  Select,
  Button,
  Alert,
  Row,
  Col,
  Divider,
  Table,
  Tag,
  Space,
  Result,
} from 'antd';
import { SendOutlined, HistoryOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useMutation, useQuery } from '@tanstack/react-query';
import { notificationsApi } from '@/api/notifications.api';
import { NOTIFICATION_SEGMENT_CONFIG } from '@/config/constants';
import type { NotificationSendRequest, NotificationTargetSegment } from '@/types/notification';

const { Title, Text } = Typography;
const { TextArea } = Input;

interface SendFormValues {
  title: string;
  body: string;
  targetSegment: NotificationTargetSegment;
}

export function NotificationSendPage() {
  const [form] = Form.useForm<SendFormValues>();
  const [sentResult, setSentResult] = useState<{ sentCount: number } | null>(null);
  const [previewMode, setPreviewMode] = useState(false);
  const [formValues, setFormValues] = useState<Partial<SendFormValues>>({});

  const { data: logs, isLoading: logsLoading } = useQuery({
    queryKey: ['notifications', 'logs'],
    queryFn: () => notificationsApi.getLogs({ page: 1, pageSize: 10 }),
  });

  const sendMutation = useMutation({
    mutationFn: (data: NotificationSendRequest) => notificationsApi.send(data),
    onSuccess: (result) => {
      setSentResult(result);
      form.resetFields();
    },
  });

  const handleSend = async (values: SendFormValues) => {
    await sendMutation.mutateAsync(values);
  };

  const handleValuesChange = (_: unknown, allValues: Partial<SendFormValues>) => {
    setFormValues(allValues);
  };

  if (sentResult) {
    return (
      <Result
        status="success"
        title={`알림 발송 완료`}
        subTitle={`총 ${sentResult.sentCount.toLocaleString()}명에게 알림을 발송했습니다.`}
        extra={[
          <Button
            key="new"
            type="primary"
            onClick={() => setSentResult(null)}
          >
            새 알림 발송
          </Button>,
        ]}
      />
    );
  }

  const logColumns = [
    {
      title: '제목',
      dataIndex: 'title',
      key: 'title',
      ellipsis: true,
    },
    {
      title: '대상',
      dataIndex: 'targetSegment',
      key: 'targetSegment',
      render: (s: NotificationTargetSegment) => (
        <Tag>{NOTIFICATION_SEGMENT_CONFIG[s]?.label || s}</Tag>
      ),
      width: 160,
    },
    {
      title: '발송 수',
      dataIndex: 'sentCount',
      key: 'sentCount',
      render: (v: number) => v.toLocaleString() + '명',
      width: 90,
    },
    {
      title: '발송자',
      dataIndex: 'sentBy',
      key: 'sentBy',
      width: 100,
    },
    {
      title: '발송일',
      dataIndex: 'sentAt',
      key: 'sentAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      width: 110,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        알림 발송
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        공지 푸시 알림을 특정 사용자 그룹에 발송합니다.
      </Text>

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={14}>
          <Card title="알림 작성" style={{ borderRadius: 8 }}>
            <Form
              form={form}
              layout="vertical"
              onFinish={handleSend}
              onValuesChange={handleValuesChange}
            >
              <Form.Item
                name="targetSegment"
                label="발송 대상"
                rules={[{ required: true, message: '발송 대상을 선택해주세요.' }]}
                extra="선택한 세그먼트에 해당하는 사용자 전체에게 발송됩니다."
              >
                <Select placeholder="발송 대상 선택">
                  {Object.entries(NOTIFICATION_SEGMENT_CONFIG).map(([value, { label }]) => (
                    <Select.Option key={value} value={value}>
                      {label}
                    </Select.Option>
                  ))}
                </Select>
              </Form.Item>

              <Form.Item
                name="title"
                label="알림 제목"
                rules={[
                  { required: true, message: '제목을 입력해주세요.' },
                  { max: 50, message: '50자 이내로 입력해주세요.' },
                ]}
              >
                <Input
                  placeholder="예: SportMatch 공지사항"
                  showCount
                  maxLength={50}
                />
              </Form.Item>

              <Form.Item
                name="body"
                label="알림 내용"
                rules={[
                  { required: true, message: '내용을 입력해주세요.' },
                  { max: 200, message: '200자 이내로 입력해주세요.' },
                ]}
              >
                <TextArea
                  placeholder="알림 내용을 입력해주세요."
                  rows={4}
                  showCount
                  maxLength={200}
                />
              </Form.Item>

              <Alert
                type="warning"
                message="발송 전 주의사항"
                description={
                  <ul style={{ margin: 0, paddingLeft: 20, fontSize: 13 }}>
                    <li>한 번 발송된 알림은 취소할 수 없습니다.</li>
                    <li>과도한 알림 발송은 사용자 이탈을 야기할 수 있습니다.</li>
                    <li>발송 전 미리보기를 통해 내용을 확인해주세요.</li>
                  </ul>
                }
                showIcon
                style={{ marginBottom: 16 }}
              />

              <Space>
                <Button
                  onClick={() => setPreviewMode(!previewMode)}
                >
                  {previewMode ? '미리보기 닫기' : '미리보기'}
                </Button>
                <Button
                  type="primary"
                  htmlType="submit"
                  icon={<SendOutlined />}
                  loading={sendMutation.isPending}
                >
                  발송
                </Button>
              </Space>
            </Form>
          </Card>
        </Col>

        <Col xs={24} lg={10}>
          {/* 알림 미리보기 */}
          {previewMode && (
            <Card
              title="알림 미리보기"
              style={{ borderRadius: 8, marginBottom: 16 }}
            >
              <div
                style={{
                  background: '#f0f0f0',
                  borderRadius: 12,
                  padding: 16,
                  maxWidth: 360,
                  margin: '0 auto',
                }}
              >
                <div
                  style={{
                    background: '#fff',
                    borderRadius: 10,
                    padding: 12,
                    boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
                  }}
                >
                  <div style={{ display: 'flex', gap: 8, marginBottom: 6 }}>
                    <span style={{ fontSize: 20 }}>⛳</span>
                    <div>
                      <div style={{ fontWeight: 700, fontSize: 14 }}>SportMatch</div>
                      <div style={{ fontSize: 12, color: '#999' }}>지금</div>
                    </div>
                  </div>
                  <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 4 }}>
                    {formValues.title || '알림 제목'}
                  </div>
                  <div style={{ fontSize: 13, color: '#555', lineHeight: 1.5 }}>
                    {formValues.body || '알림 내용이 여기에 표시됩니다.'}
                  </div>
                </div>
              </div>
              <Text type="secondary" style={{ fontSize: 12, display: 'block', textAlign: 'center', marginTop: 12 }}>
                실제 기기에서 표시되는 모습과 다를 수 있습니다.
              </Text>
            </Card>
          )}

          {/* 발송 이력 */}
          <Card
            title={
              <Space>
                <HistoryOutlined />
                최근 발송 이력
              </Space>
            }
            style={{ borderRadius: 8 }}
          >
            <Table
              columns={logColumns}
              dataSource={logs?.items || []}
              loading={logsLoading}
              rowKey="id"
              pagination={false}
              size="small"
              locale={{ emptyText: '발송 이력이 없습니다.' }}
              scroll={{ x: 400 }}
            />
          </Card>
        </Col>
      </Row>

      <Divider />
    </div>
  );
}
