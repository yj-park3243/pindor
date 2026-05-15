import { useState } from 'react';
import { Card, Tag, Select, Space, Typography, Button } from 'antd';
import { ProTable } from '@ant-design/pro-components';
import type { TableColumnsType } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { EnvironmentOutlined, ReloadOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { versionLogsApi, type VersionCheckLog } from '@/api/version-logs.api';

const { Text } = Typography;

export function VersionCheckLogsPage() {
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [platform, setPlatform] = useState<string | undefined>(undefined);
  const [hasLocation, setHasLocation] = useState<boolean | undefined>(undefined);

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['version-check-logs', page, pageSize, platform, hasLocation],
    queryFn: () =>
      versionLogsApi.list({
        page,
        pageSize,
        platform,
        hasLocation,
      }),
  });

  const columns: TableColumnsType<VersionCheckLog> = [
    {
      title: '시간',
      dataIndex: 'createdAt',
      width: 160,
      render: (v: string) => (
        <Text style={{ fontSize: 12 }}>{dayjs(v).format('YYYY-MM-DD HH:mm:ss')}</Text>
      ),
    },
    {
      title: '사용자',
      dataIndex: 'nickname',
      width: 240,
      render: (_v, row) =>
        row.userId ? (
          <Space direction="vertical" size={0}>
            <Text strong>{row.nickname ?? '-'}</Text>
            {row.email && (
              <Text type="secondary" style={{ fontSize: 11 }}>{row.email}</Text>
            )}
            {row.phoneNumber && (
              <Text type="secondary" style={{ fontSize: 11, fontFamily: 'monospace' }}>
                {row.phoneNumber}
              </Text>
            )}
            <Text type="secondary" style={{ fontSize: 10, fontFamily: 'monospace' }}>
              {row.userId.slice(0, 8)}…
            </Text>
          </Space>
        ) : (
          <Tag color="default">익명</Tag>
        ),
    },
    {
      title: '플랫폼',
      dataIndex: 'platform',
      width: 100,
      render: (v: string) => (
        <Tag color={v === 'IOS' ? 'blue' : 'green'}>{v}</Tag>
      ),
    },
    {
      title: '앱 버전',
      dataIndex: 'appVersion',
      width: 100,
      render: (v: string | null) => v ?? <Text type="secondary">-</Text>,
    },
    {
      title: '위치',
      dataIndex: 'latitude',
      width: 220,
      render: (_v, row) => {
        if (row.latitude == null || row.longitude == null) {
          return <Text type="secondary">위치 없음</Text>;
        }
        const lat = row.latitude.toFixed(6);
        const lng = row.longitude.toFixed(6);
        const mapUrl = `https://www.google.com/maps?q=${row.latitude},${row.longitude}`;
        return (
          <Space direction="vertical" size={0}>
            <Text style={{ fontSize: 12, fontFamily: 'monospace' }}>
              {lat}, {lng}
            </Text>
            <a href={mapUrl} target="_blank" rel="noreferrer" style={{ fontSize: 11 }}>
              <EnvironmentOutlined /> 지도에서 보기
            </a>
          </Space>
        );
      },
    },
    {
      title: 'IP',
      dataIndex: 'ipAddress',
      width: 130,
      render: (v: string | null) =>
        v ? (
          <Text style={{ fontSize: 11, fontFamily: 'monospace' }}>{v}</Text>
        ) : (
          <Text type="secondary">-</Text>
        ),
    },
    {
      title: 'User-Agent',
      dataIndex: 'userAgent',
      ellipsis: true,
      render: (v: string | null) =>
        v ? (
          <Text style={{ fontSize: 11, color: '#666' }}>{v}</Text>
        ) : (
          <Text type="secondary">-</Text>
        ),
    },
  ];

  return (
    <Card
      title="버전 체크 로그"
      extra={
        <Space>
          <Select
            placeholder="플랫폼"
            allowClear
            value={platform}
            onChange={(v) => {
              setPlatform(v);
              setPage(1);
            }}
            options={[
              { value: 'IOS', label: 'iOS' },
              { value: 'ANDROID', label: 'Android' },
            ]}
            style={{ width: 120 }}
          />
          <Select
            placeholder="위치 유무"
            allowClear
            value={hasLocation}
            onChange={(v) => {
              setHasLocation(v);
              setPage(1);
            }}
            options={[
              { value: true, label: '위치 있음' },
              { value: false, label: '위치 없음' },
            ]}
            style={{ width: 130 }}
          />
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>
            새로고침
          </Button>
        </Space>
      }
    >
      <ProTable<VersionCheckLog>
        columns={columns}
        dataSource={data?.items ?? []}
        loading={isLoading}
        rowKey="id"
        search={false}
        toolBarRender={false}
        pagination={{
          current: page,
          pageSize,
          total: data?.total ?? 0,
          showSizeChanger: true,
          showQuickJumper: true,
          showTotal: (total) => `총 ${total.toLocaleString()}건`,
          onChange: (p, ps) => {
            setPage(p);
            setPageSize(ps);
          },
        }}
        scroll={{ x: 1100 }}
      />
    </Card>
  );
}
