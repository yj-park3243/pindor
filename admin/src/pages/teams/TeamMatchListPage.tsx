import { useState } from 'react';
import {
  Typography,
  Card,
  Select,
  Row,
  Col,
  Tag,
  Space,
  Table,
} from 'antd';
import type { TableColumnsType } from 'antd';
import dayjs from 'dayjs';
import { useTeamMatchesList } from '@/hooks/useTeams';
import { SPORT_TYPE_CONFIG } from '@/config/constants';
import type { TeamMatch } from '@/types/team';
import type { SportType } from '@/types/user';

const { Title, Text } = Typography;

// 팀 매칭 상태 설정
const TEAM_MATCH_STATUS_CONFIG: Record<string, { label: string; color: string }> = {
  SCHEDULED: { label: '예정', color: 'blue' },
  IN_PROGRESS: { label: '진행중', color: 'processing' },
  COMPLETED: { label: '완료', color: 'green' },
  CANCELLED: { label: '취소', color: 'red' },
  DISPUTED: { label: '이의신청', color: 'orange' },
};

// 팀 매칭 결과 설정
const TEAM_MATCH_RESULT_CONFIG: Record<string, { label: string; color: string }> = {
  HOME_WIN: { label: '홈팀 승', color: 'green' },
  AWAY_WIN: { label: '어웨이팀 승', color: 'blue' },
  DRAW: { label: '무승부', color: 'default' },
  VOIDED: { label: '무효', color: 'red' },
};

export function TeamMatchListPage() {
  const [status, setStatus] = useState<string | undefined>();
  const [sportType, setSportType] = useState<SportType | undefined>();
  const [page, setPage] = useState(1);

  const { data, isLoading } = useTeamMatchesList({
    status,
    sportType,
    page,
    pageSize: 20,
  });

  const columns: TableColumnsType<TeamMatch> = [
    {
      title: '홈팀',
      key: 'homeTeam',
      render: (_, record) => record.homeTeam?.name || record.homeTeamId,
    },
    {
      title: '어웨이팀',
      key: 'awayTeam',
      render: (_, record) => record.awayTeam?.name || record.awayTeamId,
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
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (s: string) => {
        const cfg = TEAM_MATCH_STATUS_CONFIG[s];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{s}</Tag>;
      },
      width: 110,
    },
    {
      title: '결과',
      dataIndex: 'resultStatus',
      key: 'resultStatus',
      render: (r: string) => {
        const cfg = TEAM_MATCH_RESULT_CONFIG[r];
        if (!cfg) return <Text type="secondary">-</Text>;
        return <Tag color={cfg.color}>{cfg.label}</Tag>;
      },
      width: 120,
    },
    {
      title: '스코어',
      key: 'score',
      render: (_, record) => {
        const home = record.homeScore ?? '-';
        const away = record.awayScore ?? '-';
        return (
          <Text>
            {home} : {away}
          </Text>
        );
      },
      width: 90,
    },
    {
      title: '날짜',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('YYYY-MM-DD'),
      sorter: true,
      width: 110,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        팀 매칭 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        팀 간 매칭 현황 조회 및 관리
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]}>
          <Col xs={12} sm={8} lg={5}>
            <Select
              placeholder="상태 필터"
              style={{ width: '100%' }}
              allowClear
              value={status}
              onChange={(v) => {
                setStatus(v);
                setPage(1);
              }}
              options={Object.entries(TEAM_MATCH_STATUS_CONFIG).map(([value, { label }]) => ({
                value,
                label,
              }))}
            />
          </Col>
          <Col xs={12} sm={8} lg={5}>
            <Select
              placeholder="종목 필터"
              style={{ width: '100%' }}
              allowClear
              value={sportType}
              onChange={(v) => {
                setSportType(v);
                setPage(1);
              }}
              options={Object.entries(SPORT_TYPE_CONFIG).map(([value, { label }]) => ({
                value,
                label,
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
            pageSize: 20,
            total: data?.total || 0,
            showTotal: (total) => `총 ${total.toLocaleString()}건`,
            onChange: setPage,
          }}
          scroll={{ x: 800 }}
        />
      </Card>
    </div>
  );
}
