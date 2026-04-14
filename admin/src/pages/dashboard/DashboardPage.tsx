import { Row, Col, Card, Typography, Spin, Alert, Divider } from 'antd';
import {
  UserOutlined,
  SwapOutlined,
  TrophyOutlined,
  FileSearchOutlined,
} from '@ant-design/icons';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
  Cell,
} from 'recharts';
import dayjs from 'dayjs';
import { useDashboardMetrics } from '@/hooks/useDashboard';
import { StatCard } from '@/components/StatCard';

const { Title, Text } = Typography;

// 모의 히스토그램 데이터 (실제 API 응답으로 대체됨)
const SCORE_HISTOGRAM_COLORS = ['#CD7F32', '#CD7F32', '#C0C0C0', '#C0C0C0', '#FFD700', '#FFD700', '#E5E4E2'];

export function DashboardPage() {
  const { data: metrics, isLoading, error } = useDashboardMetrics();

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Spin size="large" tip="대시보드 로딩 중..." />
      </div>
    );
  }

  if (error) {
    return (
      <Alert
        message="데이터 로드 실패"
        description="대시보드 데이터를 불러오지 못했습니다. 잠시 후 다시 시도해주세요."
        type="error"
        showIcon
      />
    );
  }

  // 실제 API 데이터 사용, 데이터 없을 시 0 또는 빈 배열로 초기화 (가짜 수치 없음)
  const realtimeData = metrics?.realtime ?? {
    activeUsers: 0,
    activeMatchRequests: 0,
    ongoingMatches: 0,
    pendingResultVerifications: 0,
  };

  const todayData = metrics?.today ?? {
    newSignups: 0,
    matchesCreated: 0,
    matchesCompleted: 0,
    reportsReceived: 0,
  };

  const dauTrend = metrics?.charts?.dauTrend ?? [];

  const scoreDistribution = metrics?.charts?.scoreDistribution?.buckets ?? [];

  const matchSuccessRate = metrics?.charts?.matchSuccessRate ?? 0;

  return (
    <div>
      <Title level={4} style={{ marginBottom: 8 }}>
        대시보드
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 24 }}>
        마지막 갱신: {dayjs().format('YYYY-MM-DD HH:mm:ss')} (30초마다 자동 갱신)
      </Text>

      {/* 실시간 현황 카드 */}
      <Title level={5} style={{ marginBottom: 12 }}>
        실시간 현황
      </Title>
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="현재 접속자"
            value={realtimeData.activeUsers}
            prefix={<UserOutlined />}
            color="#1890ff"
            suffix="명"
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="활성 매칭 요청"
            value={realtimeData.activeMatchRequests}
            prefix={<SwapOutlined />}
            color="#52c41a"
            suffix="건"
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="진행중 매칭"
            value={realtimeData.ongoingMatches}
            prefix={<TrophyOutlined />}
            color="#fa8c16"
            suffix="건"
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="결과 인증 대기"
            value={realtimeData.pendingResultVerifications}
            prefix={<FileSearchOutlined />}
            color="#f5222d"
            suffix="건"
          />
        </Col>
      </Row>

      {/* 오늘의 지표 */}
      <Title level={5} style={{ marginBottom: 12 }}>
        오늘의 지표
      </Title>
      <Row gutter={[16, 16]} style={{ marginBottom: 24 }}>
        <Col xs={24} sm={12} lg={6}>
          <Card size="small" style={{ borderRadius: 8, textAlign: 'center' }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: '#1890ff' }}>
              +{todayData.newSignups}
            </div>
            <div style={{ color: '#666', fontSize: 13 }}>신규 가입</div>
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card size="small" style={{ borderRadius: 8, textAlign: 'center' }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: '#52c41a' }}>
              {todayData.matchesCreated}
            </div>
            <div style={{ color: '#666', fontSize: 13 }}>매칭 생성</div>
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card size="small" style={{ borderRadius: 8, textAlign: 'center' }}>
            <div style={{ fontSize: 28, fontWeight: 700, color: '#fa8c16' }}>
              {todayData.matchesCompleted}
            </div>
            <div style={{ color: '#666', fontSize: 13 }}>경기 완료</div>
          </Card>
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <Card size="small" style={{ borderRadius: 8, textAlign: 'center' }}>
            <div
              style={{
                fontSize: 28,
                fontWeight: 700,
                color: todayData.reportsReceived > 5 ? '#f5222d' : '#666',
              }}
            >
              {todayData.reportsReceived}
            </div>
            <div style={{ color: '#666', fontSize: 13 }}>신고 접수</div>
          </Card>
        </Col>
      </Row>

      <Divider />

      {/* 차트 영역 */}
      <Row gutter={[16, 16]}>
        {/* DAU 추이 차트 */}
        <Col xs={24} lg={16}>
          <Card
            title="DAU 추이 (최근 30일)"
            style={{ borderRadius: 8 }}
            extra={
              <Text type="secondary" style={{ fontSize: 12 }}>
                일별 활성 사용자
              </Text>
            }
          >
            <ResponsiveContainer width="100%" height={280}>
              <LineChart data={dauTrend}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                <XAxis
                  dataKey="date"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  interval={6}
                />
                <YAxis
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  tickFormatter={(v) => v.toLocaleString()}
                />
                <Tooltip
                  formatter={(val: number) => [val.toLocaleString() + '명', 'DAU']}
                  labelFormatter={(label) => `${label}`}
                />
                <Line
                  type="monotone"
                  dataKey="value"
                  stroke="#1890ff"
                  strokeWidth={2}
                  dot={false}
                  activeDot={{ r: 5 }}
                />
              </LineChart>
            </ResponsiveContainer>
          </Card>
        </Col>

        {/* 매칭 성사율 */}
        <Col xs={24} lg={8}>
          <Card title="매칭 성사율" style={{ borderRadius: 8, height: '100%' }}>
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                padding: '40px 0',
              }}
            >
              <div
                style={{
                  width: 140,
                  height: 140,
                  borderRadius: '50%',
                  border: `12px solid ${matchSuccessRate >= 0.6 ? '#52c41a' : '#fa8c16'}`,
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  background: '#fafafa',
                }}
              >
                <span
                  style={{
                    fontSize: 32,
                    fontWeight: 700,
                    color: matchSuccessRate >= 0.6 ? '#52c41a' : '#fa8c16',
                  }}
                >
                  {(matchSuccessRate * 100).toFixed(1)}%
                </span>
              </div>
              <Text
                type="secondary"
                style={{ marginTop: 16, textAlign: 'center', fontSize: 13 }}
              >
                목표: 60% 이상
                <br />
                {matchSuccessRate >= 0.6 ? '목표 달성' : '목표 미달성'}
              </Text>
            </div>
          </Card>
        </Col>

        {/* 점수 분포 히스토그램 */}
        <Col xs={24}>
          <Card
            title="점수 분포 히스토그램"
            style={{ borderRadius: 8 }}
            extra={
              <div style={{ display: 'flex', gap: 12, fontSize: 12 }}>
                <span style={{ color: '#CD7F32' }}>■ 브론즈</span>
                <span style={{ color: '#C0C0C0' }}>■ 실버</span>
                <span style={{ color: '#FFD700' }}>■ 골드</span>
                <span style={{ color: '#888' }}>■ 플래티넘</span>
              </div>
            }
          >
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={scoreDistribution} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                <XAxis
                  dataKey="rangeStart"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  tickFormatter={(v) => `${v}`}
                />
                <YAxis
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  tickFormatter={(v) => v.toLocaleString()}
                />
                <Tooltip
                  formatter={(val: number, _: string, props: { payload?: { rangeStart: number; rangeEnd: number } }) => [
                    val.toLocaleString() + '명',
                    `${props.payload?.rangeStart}~${props.payload?.rangeEnd}점`,
                  ]}
                />
                <Bar dataKey="count" radius={[4, 4, 0, 0]}>
                  {scoreDistribution.map((_, index) => (
                    <Cell
                      key={index}
                      fill={SCORE_HISTOGRAM_COLORS[Math.min(index, SCORE_HISTOGRAM_COLORS.length - 1)]}
                    />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </Card>
        </Col>
      </Row>
    </div>
  );
}
