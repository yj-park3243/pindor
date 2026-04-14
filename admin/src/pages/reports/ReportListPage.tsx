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
  Drawer,
  Descriptions,
  Form,
  Input,
  Alert,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { CheckOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useReportList, useResolveReport } from '@/hooks/useReports';
import {
  REPORT_STATUS_CONFIG,
  REPORT_TARGET_TYPE_CONFIG,
} from '@/config/constants';
import type { Report, ReportStatus, ReportTargetType } from '@/types/report';

const { Title, Text } = Typography;
const { TextArea } = Input;

export function ReportListPage() {
  const [status, setStatus] = useState<ReportStatus | undefined>();
  const [targetType, setTargetType] = useState<ReportTargetType | undefined>();
  const [page, setPage] = useState(1);
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);
  const [form] = Form.useForm();

  const { data, isLoading } = useReportList({
    status,
    targetType,
    page,
    pageSize: 20,
  });

  const resolveMutation = useResolveReport();

  const handleResolve = async (values: { status: ReportStatus; note: string }) => {
    if (!selectedReport) return;
    await resolveMutation.mutateAsync({
      id: selectedReport.id,
      data: values,
    });
    setSelectedReport(null);
    form.resetFields();
  };

  const columns: TableColumnsType<Report> = [
    {
      title: '신고 유형',
      dataIndex: 'targetType',
      key: 'targetType',
      render: (t: ReportTargetType) => (
        <Tag>{REPORT_TARGET_TYPE_CONFIG[t]?.label || t}</Tag>
      ),
      width: 100,
    },
    {
      title: '신고자',
      key: 'reporter',
      render: (_, record) => record.reporter?.nickname || '-',
      width: 120,
    },
    {
      title: '신고 사유',
      dataIndex: 'reason',
      key: 'reason',
      render: (reason: string, record: Report) => (
        <div>
          <Tag color="orange" style={{ marginBottom: 4 }}>{reason}</Tag>
          {record.description && (
            <Text type="secondary" style={{ fontSize: 12, display: 'block' }} ellipsis>
              {record.description}
            </Text>
          )}
        </div>
      ),
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (s: ReportStatus) => {
        const cfg = REPORT_STATUS_CONFIG[s];
        return <Tag color={cfg.color}>{cfg.label}</Tag>;
      },
      width: 90,
      filters: Object.entries(REPORT_STATUS_CONFIG).map(([value, { label }]) => ({
        text: label,
        value,
      })),
    },
    {
      title: '접수일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      sorter: true,
      width: 110,
    },
    {
      title: '처리',
      key: 'action',
      render: (_, record) => (
        <Button
          size="small"
          type={record.status === 'PENDING' ? 'primary' : 'default'}
          icon={<CheckOutlined />}
          onClick={() => setSelectedReport(record)}
          disabled={record.status === 'DISMISSED' || record.status === 'RESOLVED'}
        >
          {record.status === 'PENDING' ? '처리' : '상세'}
        </Button>
      ),
      width: 90,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        신고 처리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        사용자 신고 접수 목록 조회 및 처리
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="상태"
              style={{ width: '100%' }}
              allowClear
              value={status}
              onChange={(v) => { setStatus(v); setPage(1); }}
              options={Object.entries(REPORT_STATUS_CONFIG).map(([value, { label }]) => ({
                value, label,
              }))}
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="신고 유형"
              style={{ width: '100%' }}
              allowClear
              value={targetType}
              onChange={(v) => { setTargetType(v); setPage(1); }}
              options={Object.entries(REPORT_TARGET_TYPE_CONFIG).map(([value, { label }]) => ({
                value, label,
              }))}
            />
          </Col>
        </Row>
      </Card>

      <Card style={{ borderRadius: 8 }}>
        {(data?.items?.filter((r) => r.status === 'PENDING')?.length ?? 0) > 0 && (
          <Alert
            message={`처리 대기 신고 ${data?.items?.filter((r) => r.status === 'PENDING')?.length ?? 0}건이 있습니다.`}
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

      {/* 처리 드로어 */}
      <Drawer
        open={!!selectedReport}
        onClose={() => { setSelectedReport(null); form.resetFields(); }}
        title="신고 처리"
        width={480}
        extra={
          <Button
            type="primary"
            onClick={() => form.submit()}
            loading={resolveMutation.isPending}
            icon={<CheckOutlined />}
          >
            처리 완료
          </Button>
        }
      >
        {selectedReport && (
          <div>
            <Descriptions column={1} size="small" style={{ marginBottom: 16 }}>
              <Descriptions.Item label="신고 유형">
                {REPORT_TARGET_TYPE_CONFIG[selectedReport.targetType]?.label}
              </Descriptions.Item>
              <Descriptions.Item label="신고자">
                {selectedReport.reporter?.nickname}
              </Descriptions.Item>
              <Descriptions.Item label="대상 ID">
                <Text copyable style={{ fontSize: 12, fontFamily: 'monospace' }}>
                  {selectedReport.targetId}
                </Text>
              </Descriptions.Item>
              <Descriptions.Item label="신고 사유">
                <Tag color="orange">{selectedReport.reason}</Tag>
              </Descriptions.Item>
              <Descriptions.Item label="상세 설명">
                {selectedReport.description || '-'}
              </Descriptions.Item>
              <Descriptions.Item label="접수일">
                {dayjs(selectedReport.createdAt).format('YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
            </Descriptions>

            <Form form={form} layout="vertical" onFinish={handleResolve}>
              <Form.Item
                name="status"
                label="처리 결정"
                rules={[{ required: true, message: '처리 결정을 선택해주세요.' }]}
              >
                <Select>
                  <Select.Option value="RESOLVED">
                    <Space>
                      <Tag color="green">처리 완료</Tag>
                      <Text type="secondary" style={{ fontSize: 12 }}>신고 내용이 확인되어 조치를 취함</Text>
                    </Space>
                  </Select.Option>
                  <Select.Option value="DISMISSED">
                    <Space>
                      <Tag color="default">기각</Tag>
                      <Text type="secondary" style={{ fontSize: 12 }}>신고 내용이 근거가 없어 기각</Text>
                    </Space>
                  </Select.Option>
                </Select>
              </Form.Item>

              <Form.Item name="note" label="처리 메모">
                <TextArea
                  rows={3}
                  placeholder="처리 내용을 간략히 기록해주세요."
                  showCount
                  maxLength={500}
                />
              </Form.Item>
            </Form>
          </div>
        )}
      </Drawer>
    </div>
  );
}
