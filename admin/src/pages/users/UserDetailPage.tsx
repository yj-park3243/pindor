import { useParams, useNavigate } from 'react-router-dom';
import {
  Typography,
  Card,
  Row,
  Col,
  Descriptions,
  Tag,
  Spin,
  Alert,
  Button,
  Table,
  Space,
  Tabs,
  Statistic,
  Divider,
} from 'antd';
import { ArrowLeftOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/ko';
import { useUserDetail, useUserGameHistory } from '@/hooks/useUsers';
import { UserAvatar } from '@/components/UserAvatar';
import { TierBadge } from '@/components/TierBadge';
import {
  USER_STATUS_CONFIG,
  SPORT_TYPE_CONFIG,
  GAME_RESULT_STATUS_CONFIG,
} from '@/config/constants';
import type { SportsProfile } from '@/types/user';
import type { Tier } from '@/types/user';

dayjs.extend(relativeTime);
dayjs.locale('ko');

const { Title, Text } = Typography;

export function UserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const { data: user, isLoading, error } = useUserDetail(id!);
  const { data: gameHistory } = useUserGameHistory(id!);

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Spin size="large" />
      </div>
    );
  }

  if (error || !user) {
    return (
      <Alert
        message="사용자를 찾을 수 없습니다."
        type="error"
        showIcon
        action={
          <Button onClick={() => navigate(-1)}>뒤로가기</Button>
        }
      />
    );
  }

  const statusConfig = USER_STATUS_CONFIG[user.status];

  const gameColumns = [
    {
      title: '경기 일자',
      dataIndex: 'playedAt',
      key: 'playedAt',
      render: (date: string | null) => date ? dayjs(date).format('YYYY-MM-DD') : '-',
    },
    {
      title: '종목',
      dataIndex: 'sportType',
      key: 'sportType',
      render: (t: string) => SPORT_TYPE_CONFIG[t as keyof typeof SPORT_TYPE_CONFIG]?.label || t,
    },
    {
      title: '장소',
      dataIndex: 'venueName',
      key: 'venueName',
      render: (v: string | null) => v || '-',
    },
    {
      title: '상태',
      dataIndex: 'resultStatus',
      key: 'resultStatus',
      render: (status: string) => {
        const cfg = GAME_RESULT_STATUS_CONFIG[status as keyof typeof GAME_RESULT_STATUS_CONFIG];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{status}</Tag>;
      },
    },
    {
      title: '결과',
      dataIndex: 'winnerId',
      key: 'winnerId',
      render: (winnerId: string | null, record: { requesterProfile?: { userId: string } }) => {
        if (!winnerId) return '-';
        const isWin = record.requesterProfile?.userId === id || winnerId === id;
        return <Tag color={isWin ? 'green' : 'red'}>{isWin ? '승' : '패'}</Tag>;
      },
    },
  ];

  return (
    <div>
      <Button
        icon={<ArrowLeftOutlined />}
        onClick={() => navigate(-1)}
        style={{ marginBottom: 16 }}
        type="text"
      >
        목록으로
      </Button>

      <Row gutter={[16, 16]}>
        {/* 기본 정보 카드 */}
        <Col xs={24} lg={8}>
          <Card style={{ borderRadius: 8 }}>
            <div style={{ textAlign: 'center', marginBottom: 24 }}>
              <UserAvatar
                src={user.profileImageUrl}
                size={80}
              />
              <Title level={4} style={{ marginTop: 12, marginBottom: 4 }}>
                {user.nickname}
              </Title>
              <Tag color={statusConfig.color}>{statusConfig.label}</Tag>
            </div>

            <Divider />

            <Descriptions column={1} size="small">
              <Descriptions.Item label="이메일">
                {user.email || <Text type="secondary">소셜 로그인</Text>}
              </Descriptions.Item>
              <Descriptions.Item label="전화번호">
                {user.phone || <Text type="secondary">없음</Text>}
              </Descriptions.Item>
              <Descriptions.Item label="가입일">
                {dayjs(user.createdAt).format('YYYY-MM-DD')}
              </Descriptions.Item>
              <Descriptions.Item label="최근 접속">
                {user.lastLoginAt
                  ? dayjs(user.lastLoginAt).fromNow()
                  : <Text type="secondary">없음</Text>}
              </Descriptions.Item>
            </Descriptions>

            {/* 소셜 계정 */}
            {user.socialAccounts && user.socialAccounts.length > 0 && (
              <>
                <Divider />
                <Text strong style={{ display: 'block', marginBottom: 8 }}>
                  연동 소셜 계정
                </Text>
                <Space wrap>
                  {user.socialAccounts?.map((sa) => (
                    <Tag key={sa.id} color="blue">{sa.provider}</Tag>
                  ))}
                </Space>
              </>
            )}
          </Card>
        </Col>

        {/* 스포츠 프로필 + 경기 이력 */}
        <Col xs={24} lg={16}>
          <Tabs
            defaultActiveKey="profiles"
            items={[
              {
                key: 'profiles',
                label: '스포츠 프로필',
                children: (
                  <div>
                    {user.sportsProfiles && user.sportsProfiles.length > 0 ? (
                      user.sportsProfiles.map((sp: SportsProfile) => (
                        <Card
                          key={sp.id}
                          size="small"
                          style={{ marginBottom: 12, borderRadius: 8 }}
                          title={
                            <Space>
                              <span>{SPORT_TYPE_CONFIG[sp.sportType]?.icon}</span>
                              <span>{SPORT_TYPE_CONFIG[sp.sportType]?.label}</span>
                              <TierBadge tier={sp.tier as Tier} />
                            </Space>
                          }
                          extra={
                            sp.isVerified && (
                              <Tag color="green" style={{ fontSize: 11 }}>인증됨</Tag>
                            )
                          }
                        >
                          <Row gutter={16}>
                            <Col span={6}>
                              <Statistic
                                title="현재 점수"
                                value={sp.currentScore}
                                valueStyle={{ fontSize: 20, color: '#1890ff' }}
                              />
                            </Col>
                            <Col span={6}>
                              <Statistic
                                title="경기 수"
                                value={sp.gamesPlayed}
                              />
                            </Col>
                            <Col span={6}>
                              <Statistic
                                title="승"
                                value={sp.wins}
                                valueStyle={{ color: '#52c41a' }}
                              />
                            </Col>
                            <Col span={6}>
                              <Statistic
                                title="패"
                                value={sp.losses}
                                valueStyle={{ color: '#ff4d4f' }}
                              />
                            </Col>
                          </Row>
                          {sp.gHandicap !== null && (
                            <div style={{ marginTop: 12 }}>
                              <Text type="secondary" style={{ fontSize: 12 }}>
                                G핸디: {sp.gHandicap}
                              </Text>
                            </div>
                          )}
                        </Card>
                      ))
                    ) : (
                      <Alert message="스포츠 프로필이 없습니다." type="info" />
                    )}
                  </div>
                ),
              },
              {
                key: 'games',
                label: '경기 이력',
                children: (
                  <Table
                    columns={gameColumns}
                    dataSource={gameHistory?.items || []}
                    rowKey="id"
                    size="small"
                    pagination={{
                      pageSize: 10,
                      showTotal: (total) => `총 ${total}건`,
                    }}
                    locale={{ emptyText: '경기 이력이 없습니다.' }}
                  />
                ),
              },
              {
                key: 'score',
                label: '점수 히스토리',
                children: (
                  <div style={{ padding: 8 }}>
                    <Alert
                      message="점수 히스토리는 스포츠 프로필 관리에서 확인할 수 있습니다."
                      type="info"
                      showIcon
                    />
                  </div>
                ),
              },
            ]}
          />
        </Col>
      </Row>
    </div>
  );
}

