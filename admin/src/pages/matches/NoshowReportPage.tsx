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
} from 'antd';
import type { TableColumnsType } from 'antd';
import {
  SearchOutlined,
  MessageOutlined,
  EyeOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import { useNoshowReports } from '@/hooks/useMatches';
import { ChatDrawer } from '@/components/ChatDrawer';
import { REPORT_STATUS_CONFIG, SPORT_TYPE_CONFIG } from '@/config/constants';
import type { NoshowReport } from '@/api/matches.api';

const { Title, Text } = Typography;

export function NoshowReportPage() {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<string | undefined>();
  const [page, setPage] = useState(1);
  const [chatMatchId, setChatMatchId] = useState<string | null>(null);
  const [detailReport, setDetailReport] = useState<NoshowReport | null>(null);

  const { data, isLoading } = useNoshowReports({
    search: search || undefined,
    status,
    page,
    pageSize: 20,
  });

  const columns: TableColumnsType<NoshowReport> = [
    {
      title: '신고자',
      key: 'reporter',
      render: (_, record) => (
        <Text strong>{record.reporterNickname || '-'}</Text>
      ),
      width: 120,
    },
    {
      title: '노쇼 대상',
      key: 'target',
      render: (_, record) => (
        <Text type="danger" strong>{record.targetNickname || '-'}</Text>
      ),
      width: 120,
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
      title: '매칭 상태',
      key: 'matchStatus',
      render: (_, record) => {
        if (!record.match) return '-';
        return <Tag>{record.match.status}</Tag>;
      },
      width: 90,
    },
    {
      title: '증거 사진',
      key: 'images',
      render: (_, record) => (
        <Text>{record.imageUrls?.length ?? 0}장</Text>
      ),
      width: 80,
    },
    {
      title: '신고 상태',
      dataIndex: 'status',
      key: 'status',
      render: (s: string) => {
        const cfg = REPORT_STATUS_CONFIG[s as keyof typeof REPORT_STATUS_CONFIG];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{s}</Tag>;
      },
      width: 90,
    },
    {
      title: '신고일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      width: 100,
    },
    {
      title: '',
      key: 'actions',
      render: (_, record) => (
        <Space>
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
        </Space>
      ),
      width: 160,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        노쇼 신고
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        매칭 노쇼 신고 내역 및 증거 자료를 확인합니다.
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
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
              options={Object.entries(REPORT_STATUS_CONFIG).map(([value, { label }]) => ({
                value,
                label,
              }))}
            />
          </Col>
        </Row>
      </Card>

      <Card style={{ borderRadius: 8 }}>
        <div style={{ marginBottom: 12 }}>
          <Text type="secondary">총 {(data?.total ?? 0).toLocaleString()}건</Text>
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
          scroll={{ x: 900 }}
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
        width={640}
        footer={null}
      >
        {detailReport && (
          <div>
            <Descriptions column={1} size="small" bordered style={{ marginBottom: 16 }}>
              <Descriptions.Item label="신고자">
                {detailReport.reporterNickname}
              </Descriptions.Item>
              <Descriptions.Item label="노쇼 대상">
                <Text type="danger" strong>{detailReport.targetNickname}</Text>
              </Descriptions.Item>
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
                  <Descriptions.Item label="매칭 상태">
                    <Tag>{detailReport.match.status}</Tag>
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
                  const cfg = REPORT_STATUS_CONFIG[detailReport.status as keyof typeof REPORT_STATUS_CONFIG];
                  return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{detailReport.status}</Tag>;
                })()}
              </Descriptions.Item>
              <Descriptions.Item label="신고일">
                {dayjs(detailReport.createdAt).format('YYYY-MM-DD HH:mm:ss')}
              </Descriptions.Item>
              <Descriptions.Item label="설명">
                {detailReport.description || '-'}
              </Descriptions.Item>
            </Descriptions>

            {detailReport.imageUrls && detailReport.imageUrls.length > 0 && (
              <div>
                <Text strong style={{ display: 'block', marginBottom: 8 }}>
                  증거 사진 ({detailReport.imageUrls.length}장)
                </Text>
                <Space wrap>
                  <Image.PreviewGroup>
                    {detailReport.imageUrls.map((url, i) => (
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
                  type="primary"
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
    </div>
  );
}
