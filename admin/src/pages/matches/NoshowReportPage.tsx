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
  Image,
  Modal,
  Descriptions,
  Checkbox,
  Alert,
  Form,
  Statistic,
} from 'antd';
import type { TableColumnsType } from 'antd';
import {
  SearchOutlined,
  MessageOutlined,
  EyeOutlined,
  CheckCircleOutlined,
  CloseCircleOutlined,
  FileSearchOutlined,
  DeleteOutlined,
  WarningOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import {
  useNoshowReports,
  useApproveNoshowReport,
  useRejectNoshowReport,
  useInsufficientNoshowReport,
  useBulkRejectNoshowReports,
} from '@/hooks/useMatches';
import { ChatDrawer } from '@/components/ChatDrawer';
import { SPORT_TYPE_CONFIG } from '@/config/constants';
import type { NoshowReport } from '@/api/matches.api';

const { Title, Text } = Typography;

const STATUS_CONFIG: Record<string, { color: string; label: string }> = {
  PENDING: { color: 'orange', label: '검토 대기' },
  APPROVED: { color: 'green', label: '승인' },
  REJECTED: { color: 'red', label: '기각' },
  INSUFFICIENT: { color: 'blue', label: '자료 부족' },
};

type ActionType = 'approve' | 'reject' | 'insufficient' | 'bulk-reject';

export function NoshowReportPage() {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<string | undefined>('PENDING');
  const [page, setPage] = useState(1);
  const [chatMatchId, setChatMatchId] = useState<string | null>(null);
  const [detailReport, setDetailReport] = useState<NoshowReport | null>(null);
  const [actionModal, setActionModal] = useState<{
    type: ActionType;
    report?: NoshowReport;
  } | null>(null);
  const [selectedRowKeys, setSelectedRowKeys] = useState<string[]>([]);
  const [form] = Form.useForm();

  const { data, isLoading } = useNoshowReports({
    search: search || undefined,
    status,
    page,
    pageSize: 20,
  });

  const approveMutation = useApproveNoshowReport();
  const rejectMutation = useRejectNoshowReport();
  const insufficientMutation = useInsufficientNoshowReport();
  const bulkRejectMutation = useBulkRejectNoshowReports();

  const handleAction = async () => {
    if (!actionModal) return;
    const values = await form.validateFields();

    if (actionModal.type === 'approve' && actionModal.report) {
      await approveMutation.mutateAsync({ id: actionModal.report.id, memo: values.memo });
    } else if (actionModal.type === 'reject' && actionModal.report) {
      await rejectMutation.mutateAsync({
        id: actionModal.report.id,
        memo: values.memo,
        reporterPenalty: values.reporterPenalty ?? false,
      });
    } else if (actionModal.type === 'insufficient' && actionModal.report) {
      await insufficientMutation.mutateAsync({ id: actionModal.report.id, memo: values.memo });
    } else if (actionModal.type === 'bulk-reject') {
      await bulkRejectMutation.mutateAsync({ ids: selectedRowKeys, memo: values.memo });
      setSelectedRowKeys([]);
    }

    setActionModal(null);
    form.resetFields();
    setDetailReport(null);
  };

  const isPending = (r: NoshowReport) => r.status === 'PENDING' || r.status === 'INSUFFICIENT';

  const columns: TableColumnsType<NoshowReport> = [
    {
      title: '',
      key: 'select',
      width: 40,
      render: (_, record) =>
        isPending(record) ? (
          <Checkbox
            checked={selectedRowKeys.includes(record.id)}
            onChange={(e) => {
              setSelectedRowKeys((prev) =>
                e.target.checked ? [...prev, record.id] : prev.filter((k) => k !== record.id),
              );
            }}
          />
        ) : null,
    },
    {
      title: '신고자',
      key: 'reporter',
      render: (_, record) => (
        <div>
          <Text strong>{record.reporterNickname || '-'}</Text>
          {record.reporterMannerAvg != null && (
            <div>
              <Text type="secondary" style={{ fontSize: 11 }}>
                매너 {record.reporterMannerAvg.toFixed(1)} | 신고 {record.reporterTotalReports}건 (승인 {record.reporterApprovedReports}건)
              </Text>
            </div>
          )}
        </div>
      ),
      width: 160,
    },
    {
      title: '노쇼 대상',
      key: 'target',
      render: (_, record) => (
        <div>
          <Text type="danger" strong>{record.reportedNickname || '-'}</Text>
          <div>
            <Text type="secondary" style={{ fontSize: 11 }}>
              확정 {record.reportedConfirmedCount}회
              {record.reportedMannerAvg != null && ` | 매너 ${record.reportedMannerAvg.toFixed(1)}`}
            </Text>
          </div>
        </div>
      ),
      width: 160,
    },
    {
      title: '종목',
      key: 'sportType',
      render: (_, record) => {
        if (!record.match) return '-';
        const cfg = SPORT_TYPE_CONFIG[record.match.sportType as keyof typeof SPORT_TYPE_CONFIG];
        return cfg ? (
          <Space>
            <span>{cfg.icon}</span>
            <span>{cfg.label}</span>
          </Space>
        ) : record.match.sportType;
      },
      width: 100,
    },
    {
      title: '증거',
      key: 'images',
      render: (_, record) => (
        <Text>{record.evidenceUrls?.length ?? 0}장</Text>
      ),
      width: 60,
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (s: string) => {
        const cfg = STATUS_CONFIG[s];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{s}</Tag>;
      },
      width: 90,
    },
    {
      title: '신고일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => {
        const isOverdue = dayjs().diff(dayjs(d), 'hour') > 24;
        return (
          <span style={{ color: isOverdue && status === 'PENDING' ? '#ff4d4f' : undefined }}>
            {dayjs(d).format('MM-DD HH:mm')}
            {isOverdue && status === 'PENDING' && ' ⚠'}
          </span>
        );
      },
      width: 110,
    },
    {
      title: '',
      key: 'actions',
      render: (_, record) => (
        <Space size={4}>
          <Button
            size="small"
            icon={<EyeOutlined />}
            onClick={() => setDetailReport(record)}
          >
            상세
          </Button>
          {record.match?.chatRoomId && (
            <Button
              size="small"
              icon={<MessageOutlined />}
              onClick={() => setChatMatchId(record.match!.id)}
            >
              채팅
            </Button>
          )}
          {isPending(record) && (
            <>
              <Button
                size="small"
                type="primary"
                icon={<CheckCircleOutlined />}
                onClick={() => {
                  setActionModal({ type: 'approve', report: record });
                  form.resetFields();
                }}
              >
                승인
              </Button>
              <Button
                size="small"
                danger
                icon={<CloseCircleOutlined />}
                onClick={() => {
                  setActionModal({ type: 'reject', report: record });
                  form.resetFields();
                }}
              >
                기각
              </Button>
              {record.status === 'PENDING' && (
                <Button
                  size="small"
                  icon={<FileSearchOutlined />}
                  onClick={() => {
                    setActionModal({ type: 'insufficient', report: record });
                    form.resetFields();
                  }}
                >
                  자료요청
                </Button>
              )}
            </>
          )}
        </Space>
      ),
      width: 300,
    },
  ];

  const actionModalTitle: Record<ActionType, string> = {
    approve: '노쇼 신고 승인',
    reject: '노쇼 신고 기각',
    insufficient: '자료 부족 처리',
    'bulk-reject': `${selectedRowKeys.length}건 일괄 기각`,
  };

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        노쇼 신고 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        매칭 노쇼 신고를 검토하고 승인/기각/자료 요청 처리합니다.
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]} align="middle">
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="닉네임으로 검색"
              prefix={<SearchOutlined />}
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              allowClear
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="처리 상태"
              style={{ width: '100%' }}
              allowClear
              value={status}
              onChange={(v) => { setStatus(v); setPage(1); }}
              options={Object.entries(STATUS_CONFIG).map(([value, { label }]) => ({ value, label }))}
            />
          </Col>
          {selectedRowKeys.length > 0 && (
            <Col>
              <Button
                danger
                icon={<DeleteOutlined />}
                onClick={() => {
                  setActionModal({ type: 'bulk-reject' });
                  form.resetFields();
                }}
              >
                선택 {selectedRowKeys.length}건 일괄 기각
              </Button>
            </Col>
          )}
        </Row>
      </Card>

      <Card style={{ borderRadius: 8 }}>
        <div style={{ marginBottom: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Text type="secondary">총 {(data?.total ?? 0).toLocaleString()}건</Text>
          {selectedRowKeys.length > 0 && (
            <Text type="warning">{selectedRowKeys.length}건 선택됨</Text>
          )}
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
          scroll={{ x: 1100 }}
        />
      </Card>

      <ChatDrawer
        matchId={chatMatchId}
        onClose={() => setChatMatchId(null)}
        title="매칭 채팅 내역"
      />

      {/* 상세 모달 */}
      <Modal
        open={!!detailReport}
        onCancel={() => setDetailReport(null)}
        title="노쇼 신고 상세"
        width={700}
        footer={
          detailReport && isPending(detailReport) ? (
            <Space>
              {detailReport.status === 'PENDING' && (
                <Button
                  icon={<FileSearchOutlined />}
                  onClick={() => {
                    setActionModal({ type: 'insufficient', report: detailReport });
                    form.resetFields();
                  }}
                >
                  자료 요청
                </Button>
              )}
              <Button
                danger
                icon={<CloseCircleOutlined />}
                onClick={() => {
                  setActionModal({ type: 'reject', report: detailReport });
                  form.resetFields();
                }}
              >
                기각
              </Button>
              <Button
                type="primary"
                icon={<CheckCircleOutlined />}
                onClick={() => {
                  setActionModal({ type: 'approve', report: detailReport });
                  form.resetFields();
                }}
              >
                승인
              </Button>
            </Space>
          ) : null
        }
      >
        {detailReport && (
          <div>
            {detailReport.reportedConfirmedCount >= 1 && (
              <Alert
                type="warning"
                icon={<WarningOutlined />}
                message={`노쇼 누적 ${detailReport.reportedConfirmedCount}회 — 승인 시 ${detailReport.reportedConfirmedCount + 1 >= 2 ? '영구 정지 (SUPER_ADMIN 승인 필요)' : '7일 정지'}`}
                style={{ marginBottom: 16 }}
                showIcon
              />
            )}

            <Row gutter={16} style={{ marginBottom: 16 }}>
              <Col span={12}>
                <Card size="small" title="신고자 정보">
                  <Statistic title="닉네임" value={detailReport.reporterNickname} valueStyle={{ fontSize: 14 }} />
                  <Statistic title="총 신고 횟수" value={detailReport.reporterTotalReports} valueStyle={{ fontSize: 14 }} />
                  <Statistic title="승인된 신고" value={detailReport.reporterApprovedReports} valueStyle={{ fontSize: 14 }} />
                  {detailReport.reporterMannerAvg != null && (
                    <Statistic title="매너 평균" value={detailReport.reporterMannerAvg.toFixed(2)} valueStyle={{ fontSize: 14 }} />
                  )}
                </Card>
              </Col>
              <Col span={12}>
                <Card size="small" title="신고 대상 정보">
                  <Statistic title="닉네임" value={detailReport.reportedNickname} valueStyle={{ fontSize: 14 }} />
                  <Statistic title="노쇼 확정 횟수" value={detailReport.reportedConfirmedCount} valueStyle={{ fontSize: 14, color: detailReport.reportedConfirmedCount > 0 ? '#ff4d4f' : undefined }} />
                  {detailReport.reportedMannerAvg != null && (
                    <Statistic title="매너 평균" value={detailReport.reportedMannerAvg.toFixed(2)} valueStyle={{ fontSize: 14 }} />
                  )}
                </Card>
              </Col>
            </Row>

            <Descriptions column={1} size="small" bordered style={{ marginBottom: 16 }}>
              {detailReport.match && (
                <>
                  <Descriptions.Item label="종목">
                    {(() => {
                      const cfg = SPORT_TYPE_CONFIG[detailReport.match.sportType as keyof typeof SPORT_TYPE_CONFIG];
                      return cfg ? `${cfg.icon} ${cfg.label}` : detailReport.match.sportType;
                    })()}
                  </Descriptions.Item>
                  <Descriptions.Item label="요청자 vs 상대">
                    {detailReport.match.requesterNickname} vs {detailReport.match.opponentNickname}
                  </Descriptions.Item>
                  <Descriptions.Item label="예정일">
                    {detailReport.match.scheduledDate
                      ? dayjs(detailReport.match.scheduledDate).format('YYYY-MM-DD')
                      : '-'}
                  </Descriptions.Item>
                </>
              )}
              <Descriptions.Item label="처리 상태">
                {(() => {
                  const cfg = STATUS_CONFIG[detailReport.status];
                  return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{detailReport.status}</Tag>;
                })()}
              </Descriptions.Item>
              <Descriptions.Item label="신고일">
                {dayjs(detailReport.createdAt).format('YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
              {detailReport.reporterMessage && (
                <Descriptions.Item label="신고 메시지">
                  {detailReport.reporterMessage}
                </Descriptions.Item>
              )}
              {detailReport.adminMemo && (
                <Descriptions.Item label="어드민 메모">
                  {detailReport.adminMemo}
                </Descriptions.Item>
              )}
            </Descriptions>

            {detailReport.evidenceUrls && detailReport.evidenceUrls.length > 0 && (
              <div>
                <Text strong style={{ display: 'block', marginBottom: 8 }}>
                  증거 사진 ({detailReport.evidenceUrls.length}장)
                </Text>
                <Space wrap>
                  <Image.PreviewGroup>
                    {detailReport.evidenceUrls.map((url, i) => (
                      <Image
                        key={i}
                        src={url}
                        width={100}
                        height={100}
                        style={{ objectFit: 'cover', borderRadius: 6 }}
                      />
                    ))}
                  </Image.PreviewGroup>
                </Space>
              </div>
            )}

            {detailReport.match?.chatRoomId && (
              <div style={{ marginTop: 16 }}>
                <Button
                  icon={<MessageOutlined />}
                  onClick={() => {
                    setChatMatchId(detailReport.match!.id);
                  }}
                >
                  채팅 내역 보기
                </Button>
              </div>
            )}
          </div>
        )}
      </Modal>

      {/* 액션 모달 (승인/기각/자료요청/일괄기각) */}
      <Modal
        open={!!actionModal}
        onCancel={() => {
          setActionModal(null);
          form.resetFields();
        }}
        title={actionModal ? actionModalTitle[actionModal.type] : ''}
        onOk={handleAction}
        okText={actionModal?.type === 'approve' ? '승인' : actionModal?.type === 'reject' || actionModal?.type === 'bulk-reject' ? '기각' : '요청'}
        okButtonProps={{
          danger: actionModal?.type === 'reject' || actionModal?.type === 'bulk-reject',
          loading:
            approveMutation.isPending ||
            rejectMutation.isPending ||
            insufficientMutation.isPending ||
            bulkRejectMutation.isPending,
        }}
        cancelText="취소"
      >
        {actionModal?.type === 'approve' && actionModal.report && (
          <Alert
            type="warning"
            message={`승인 시 "${actionModal.report.reportedNickname}"에게 패널티가 적용됩니다.`}
            style={{ marginBottom: 16 }}
          />
        )}
        {actionModal?.type === 'bulk-reject' && (
          <Alert
            type="warning"
            message={`선택된 ${selectedRowKeys.length}건을 모두 기각합니다.`}
            style={{ marginBottom: 16 }}
          />
        )}
        <Form form={form} layout="vertical">
          <Form.Item
            name="memo"
            label="처리 메모 (필수)"
            rules={[{ required: true, message: '메모를 입력해주세요.' }]}
          >
            <Input.TextArea rows={3} placeholder="처리 사유를 입력하세요..." />
          </Form.Item>
          {actionModal?.type === 'reject' && (
            <Form.Item name="reporterPenalty" valuePropName="checked" initialValue={false}>
              <Checkbox>
                악의적 신고로 판단 — 신고자에게 -10점 + 7일 신고 자격 차단 적용
              </Checkbox>
            </Form.Item>
          )}
        </Form>
      </Modal>
    </div>
  );
}
