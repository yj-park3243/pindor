import { useState } from 'react';
import {
  Typography,
  Card,
  Row,
  Col,
  Select,
  Divider,
  Statistic,
  Spin,
  Alert,
} from 'antd';
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
  Cell,
} from 'recharts';
import dayjs from 'dayjs';
import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import { useDashboardMetrics } from '@/hooks/useDashboard';

const { Title, Text } = Typography;

// 모의 MAU/DAU 데이터
function generateTrendData(days: number) {
  return Array.from({ length: days }, (_, i) => ({
    date: dayjs().subtract(days - 1 - i, 'day').format(days > 30 ? 'MM-DD' : 'MM/DD'),
    dau: Math.floor(800 + Math.random() * 600 + i * 10),
    mau: Math.floor(3000 + Math.random() * 1000 + i * 30),
    newUsers: Math.floor(20 + Math.random() * 60),
    matches: Math.floor(50 + Math.random() * 100),
  }));
}

const TIER_COLORS: Record<string, string> = {
  BRONZE: '#CD7F32',
  SILVER: '#C0C0C0',
  GOLD: '#FFD700',
  PLATINUM: '#888',
};

export function StatisticsPage() {
  const [period, setPeriod] = useState<'7' | '30' | '90'>('30');
  const { data: metrics, isLoading, error } = useDashboardMetrics();

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Spin size="large" />
      </div>
    );
  }

  if (error) {
    return (
      <Alert
        message="통계 데이터 로드 실패"
        type="error"
        showIcon
      />
    );
  }

  const trendData = generateTrendData(parseInt(period));

  const scoreDistribution = metrics?.charts?.scoreDistribution?.buckets ?? [
    { rangeStart: 800, rangeEnd: 899, count: 320, tier: 'BRONZE' },
    { rangeStart: 900, rangeEnd: 999, count: 450, tier: 'BRONZE' },
    { rangeStart: 1000, rangeEnd: 1099, count: 580, tier: 'BRONZE' },
    { rangeStart: 1100, rangeEnd: 1199, count: 620, tier: 'SILVER' },
    { rangeStart: 1200, rangeEnd: 1299, count: 480, tier: 'SILVER' },
    { rangeStart: 1300, rangeEnd: 1399, count: 280, tier: 'GOLD' },
    { rangeStart: 1400, rangeEnd: 1499, count: 150, tier: 'GOLD' },
    { rangeStart: 1500, rangeEnd: 1649, count: 80, tier: 'GOLD' },
    { rangeStart: 1650, rangeEnd: 1800, count: 40, tier: 'PLATINUM' },
  ];

  const heatmapPoints = metrics?.charts?.regionHeatmap?.points ?? [
    { lat: 37.5665, lng: 126.978, intensity: 100, label: '종로구' },
    { lat: 37.5172, lng: 127.047, intensity: 85, label: '강남구' },
    { lat: 37.5139, lng: 127.0613, intensity: 72, label: '송파구' },
    { lat: 37.4837, lng: 126.9026, intensity: 60, label: '영등포구' },
    { lat: 37.5511, lng: 127.0739, intensity: 55, label: '광진구' },
    { lat: 37.5633, lng: 126.9997, intensity: 48, label: '마포구' },
    { lat: 37.4954, lng: 127.1285, intensity: 42, label: '강동구' },
    { lat: 37.6181, lng: 126.9226, intensity: 35, label: '은평구' },
  ];

  const matchSuccessRate = metrics?.charts?.matchSuccessRate ?? 0.68;

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 }}>
        <div>
          <Title level={4} style={{ margin: 0 }}>
            통계/분석
          </Title>
          <Text type="secondary">서비스 주요 지표 분석</Text>
        </div>
        <Select
          value={period}
          onChange={(v) => setPeriod(v)}
          style={{ width: 120 }}
          options={[
            { value: '7', label: '최근 7일' },
            { value: '30', label: '최근 30일' },
            { value: '90', label: '최근 90일' },
          ]}
        />
      </div>

      {/* 핵심 지표 요약 */}
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ textAlign: 'center', borderRadius: 8 }}>
            <Statistic
              title="매칭 성사율"
              value={(matchSuccessRate * 100).toFixed(1)}
              suffix="%"
              valueStyle={{ color: matchSuccessRate >= 0.6 ? '#52c41a' : '#fa8c16' }}
            />
          </Card>
        </Col>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ textAlign: 'center', borderRadius: 8 }}>
            <Statistic
              title="평균 DAU"
              value={Math.round(trendData.reduce((s, d) => s + d.dau, 0) / trendData.length).toLocaleString()}
              suffix="명"
              valueStyle={{ color: '#1890ff' }}
            />
          </Card>
        </Col>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ textAlign: 'center', borderRadius: 8 }}>
            <Statistic
              title="기간내 총 매칭"
              value={trendData.reduce((s, d) => s + d.matches, 0).toLocaleString()}
              suffix="건"
              valueStyle={{ color: '#fa8c16' }}
            />
          </Card>
        </Col>
        <Col xs={12} sm={6}>
          <Card size="small" style={{ textAlign: 'center', borderRadius: 8 }}>
            <Statistic
              title="신규 가입"
              value={trendData.reduce((s, d) => s + d.newUsers, 0).toLocaleString()}
              suffix="명"
              valueStyle={{ color: '#52c41a' }}
            />
          </Card>
        </Col>
      </Row>

      <Divider />

      {/* DAU / 신규 가입 추이 */}
      <Row gutter={[16, 16]}>
        <Col xs={24}>
          <Card
            title={`DAU / 신규 가입 추이 (최근 ${period}일)`}
            style={{ borderRadius: 8 }}
          >
            <ResponsiveContainer width="100%" height={280}>
              <LineChart data={trendData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                <XAxis
                  dataKey="date"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  interval={period === '7' ? 0 : Math.floor(trendData.length / 7)}
                />
                <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                <Tooltip />
                <Legend />
                <Line
                  type="monotone"
                  dataKey="dau"
                  name="DAU"
                  stroke="#1890ff"
                  strokeWidth={2}
                  dot={false}
                />
                <Line
                  type="monotone"
                  dataKey="newUsers"
                  name="신규 가입"
                  stroke="#52c41a"
                  strokeWidth={2}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </Card>
        </Col>

        {/* 매칭 성사율 추이 */}
        <Col xs={24} lg={12}>
          <Card
            title={`일별 매칭 생성 (최근 ${period}일)`}
            style={{ borderRadius: 8 }}
          >
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={trendData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                <XAxis
                  dataKey="date"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  interval={period === '7' ? 0 : Math.floor(trendData.length / 6)}
                />
                <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                <Tooltip />
                <Bar dataKey="matches" name="매칭 수" fill="#fa8c16" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Card>
        </Col>

        {/* 점수 분포 히스토그램 */}
        <Col xs={24} lg={12}>
          <Card
            title="점수 분포"
            style={{ borderRadius: 8 }}
            extra={
              <div style={{ display: 'flex', gap: 10, fontSize: 11 }}>
                {Object.entries(TIER_COLORS).map(([t, c]) => (
                  <span key={t} style={{ color: t === 'PLATINUM' ? '#888' : c }}>
                    ■ {t}
                  </span>
                ))}
              </div>
            }
          >
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={scoreDistribution}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                <XAxis
                  dataKey="rangeStart"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                />
                <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                <Tooltip
                  formatter={(v: number, _: string, props: { payload?: { rangeStart: number; rangeEnd: number } }) => [
                    v.toLocaleString() + '명',
                    `${props.payload?.rangeStart}~${props.payload?.rangeEnd}점`,
                  ]}
                />
                <Bar dataKey="count" radius={[4, 4, 0, 0]}>
                  {scoreDistribution.map((entry, i) => (
                    <Cell
                      key={i}
                      fill={TIER_COLORS[(entry as { tier?: string }).tier || 'BRONZE'] || '#CD7F32'}
                    />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </Card>
        </Col>

        {/* 지역별 활성도 히트맵 */}
        <Col xs={24}>
          <Card
            title="지역별 활성도 히트맵"
            style={{ borderRadius: 8 }}
          >
            <MapContainer
              center={[37.5665, 126.978]}
              zoom={11}
              style={{ height: 400, width: '100%', borderRadius: 8 }}
            >
              <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              />
              {heatmapPoints.map((point, i) => (
                <CircleMarker
                  key={i}
                  center={[point.lat, point.lng]}
                  radius={Math.max(8, point.intensity / 5)}
                  fillColor="#1890ff"
                  fillOpacity={Math.min(0.8, point.intensity / 100)}
                  color="#1890ff"
                  weight={1}
                >
                  <Popup>
                    <strong>{point.label}</strong>
                    <br />
                    활성도: {point.intensity}
                  </Popup>
                </CircleMarker>
              ))}
            </MapContainer>
          </Card>
        </Col>
      </Row>
    </div>
  );
}
