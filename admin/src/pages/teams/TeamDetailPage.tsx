import { useState } from 'react';
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
  Avatar,
  Form,
  InputNumber,
  Input,
  Modal,
  Popconfirm,
  Divider,
  Tooltip,
} from 'antd';
import {
  ArrowLeftOutlined,
  TeamOutlined,
  StopOutlined,
  CheckCircleOutlined,
  DeleteOutlined,
  UserDeleteOutlined,
  EditOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/ko';
import {
  useTeam,
  useTeamMembers,
  useTeamMatches,
  useTeamPosts,
  useSuspendTeam,
  useActivateTeam,
  useDisbandTeam,
  useRemoveTeamMember,
  useUpdateTeamScore,
  useDeleteTeamPost,
} from '@/hooks/useTeams';
import { SPORT_TYPE_CONFIG } from '@/config/constants';
import { ConfirmAction } from '@/components/ConfirmAction';
import { UserAvatar } from '@/components/UserAvatar';
import type { TeamMember, TeamMatch, TeamPost, TeamStatus, TeamMemberRole } from '@/types/team';

dayjs.extend(relativeTime);
dayjs.locale('ko');

const { Title, Text } = Typography;
const { TextArea } = Input;

// 상태/역할 설정
const TEAM_STATUS_CONFIG: Record<TeamStatus, { label: string; color: string }> = {
  ACTIVE: { label: '활성', color: 'green' },
  INACTIVE: { label: '비활성', color: 'orange' },
  DISBANDED: { label: '해산', color: 'red' },
};

const TEAM_MEMBER_ROLE_CONFIG: Record<TeamMemberRole, { label: string; color: string }> = {
  CAPTAIN: { label: '주장', color: 'gold' },
  VICE_CAPTAIN: { label: '부주장', color: 'blue' },
  MEMBER: { label: '일반', color: 'default' },
};

const TEAM_MEMBER_STATUS_CONFIG = {
  ACTIVE: { label: '활성', color: 'green' },
  INACTIVE: { label: '비활성', color: 'orange' },
  BANNED: { label: '추방', color: 'red' },
} as const;

export function TeamDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  // 액션 모달 상태
  const [suspendOpen, setSuspendOpen] = useState(false);
  const [disbandOpen, setDisbandOpen] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<TeamMember | null>(null);
  const [scoreModalOpen, setScoreModalOpen] = useState(false);
  const [scoreForm] = Form.useForm<{ score: number; reason: string }>();

  // 데이터 쿼리
  const { data: team, isLoading, error } = useTeam(id!);
  const { data: members = [] } = useTeamMembers(id!);
  const { data: matches = [] } = useTeamMatches(id!);
  const { data: posts = [] } = useTeamPosts(id!);

  // 뮤테이션
  const suspendMutation = useSuspendTeam();
  const activateMutation = useActivateTeam();
  const disbandMutation = useDisbandTeam();
  const removeMemberMutation = useRemoveTeamMember();
  const updateScoreMutation = useUpdateTeamScore();
  const deletePostMutation = useDeleteTeamPost();

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Spin size="large" />
      </div>
    );
  }

  if (error || !team) {
    return (
      <Alert
        message="팀을 찾을 수 없습니다."
        type="error"
        showIcon
        action={<Button onClick={() => navigate(-1)}>뒤로가기</Button>}
      />
    );
  }

  const statusConfig = TEAM_STATUS_CONFIG[team.status];
  const sportConfig = SPORT_TYPE_CONFIG[team.sportType as keyof typeof SPORT_TYPE_CONFIG];

  // 멤버 컬럼
  const memberColumns = [
    {
      title: '멤버',
      key: 'user',
      render: (_: unknown, record: TeamMember) => (
        <UserAvatar
          src={record.user?.profileImageUrl}
          nickname={record.user?.nickname || record.userId}
          size="small"
        />
      ),
    },
    {
      title: '역할',
      dataIndex: 'role',
      key: 'role',
      render: (role: TeamMemberRole) => {
        const config = TEAM_MEMBER_ROLE_CONFIG[role];
        return <Tag color={config.color}>{config.label}</Tag>;
      },
      width: 90,
    },
    {
      title: '포지션',
      dataIndex: 'position',
      key: 'position',
      render: (position: string | null) => position || <Text type="secondary">-</Text>,
      width: 100,
    },
    {
      title: '상태',
      dataIndex: 'status',
      key: 'status',
      render: (status: keyof typeof TEAM_MEMBER_STATUS_CONFIG) => {
        const config = TEAM_MEMBER_STATUS_CONFIG[status];
        return <Tag color={config.color}>{config.label}</Tag>;
      },
      width: 80,
    },
    {
      title: '가입일',
      dataIndex: 'joinedAt',
      key: 'joinedAt',
      render: (date: string) => dayjs(date).format('YYYY-MM-DD'),
      width: 110,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_: unknown, record: TeamMember) => (
        record.role !== 'CAPTAIN' && record.status === 'ACTIVE' ? (
          <Tooltip title="추방">
            <Button
              type="text"
              danger
              icon={<UserDeleteOutlined />}
              onClick={() => setRemoveTarget(record)}
            />
          </Tooltip>
        ) : null
      ),
      width: 80,
    },
  ];

  // 매칭 컬럼
  const matchColumns = [
    {
      title: '홈 팀',
      key: 'homeTeam',
      render: (_: unknown, record: TeamMatch) => (
        <Text>
          {record.homeTeam?.name || record.homeTeamId}
          {record.homeTeamId === id && <Tag color="blue" style={{ marginLeft: 6 }}>우리팀</Tag>}
        </Text>
      ),
    },
    {
      title: '원정 팀',
      key: 'awayTeam',
      render: (_: unknown, record: TeamMatch) => (
        <Text>
          {record.awayTeam?.name || record.awayTeamId}
          {record.awayTeamId === id && <Tag color="blue" style={{ marginLeft: 6 }}>우리팀</Tag>}
        </Text>
      ),
    },
    {
      title: '종목',
      dataIndex: 'sportType',
      key: 'sportType',
      render: (sportType: string) => {
        const cfg = SPORT_TYPE_CONFIG[sportType as keyof typeof SPORT_TYPE_CONFIG];
        return cfg ? `${cfg.icon} ${cfg.label}` : sportType;
      },
      width: 110,
    },
    {
      title: '스코어',
      key: 'score',
      render: (_: unknown, record: TeamMatch) =>
        record.homeScore !== undefined && record.awayScore !== undefined ? (
          <Text strong>
            {record.homeScore} : {record.awayScore}
          </Text>
        ) : (
          <Text type="secondary">-</Text>
        ),
      width: 90,
      align: 'center' as const,
    },
    {
      title: '결과',
      dataIndex: 'resultStatus',
      key: 'resultStatus',
      render: (status: string) => <Tag>{status}</Tag>,
      width: 90,
    },
    {
      title: '날짜',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (date: string) => dayjs(date).format('YYYY-MM-DD'),
      width: 110,
    },
  ];

  // 게시글 컬럼
  const postColumns = [
    {
      title: '카테고리',
      dataIndex: 'category',
      key: 'category',
      render: (category: string) => <Tag>{category}</Tag>,
      width: 90,
    },
    {
      title: '제목',
      dataIndex: 'title',
      key: 'title',
      render: (title: string, record: TeamPost) => (
        <Space>
          {record.isPinned && <Tag color="gold" style={{ fontSize: 11 }}>공지</Tag>}
          <Text>{title}</Text>
        </Space>
      ),
    },
    {
      title: '조회수',
      dataIndex: 'viewCount',
      key: 'viewCount',
      width: 80,
      align: 'center' as const,
    },
    {
      title: '작성일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (date: string) => dayjs(date).format('YYYY-MM-DD'),
      width: 110,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_: unknown, record: TeamPost) => (
        <Popconfirm
          title="게시글을 삭제하시겠습니까?"
          description="삭제된 게시글은 복구할 수 없습니다."
          onConfirm={() => deletePostMutation.mutate({ teamId: id!, postId: record.id })}
          okText="삭제"
          cancelText="취소"
          okButtonProps={{ danger: true }}
        >
          <Tooltip title="삭제">
            <Button type="text" danger icon={<DeleteOutlined />} />
          </Tooltip>
        </Popconfirm>
      ),
      width: 70,
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
        {/* 팀 프로필 카드 */}
        <Col xs={24} lg={7}>
          <Card style={{ borderRadius: 8 }}>
            {/* 팀 아이콘 + 이름 */}
            <div style={{ textAlign: 'center', marginBottom: 24 }}>
              <Avatar
                src={team.logoUrl}
                icon={!team.logoUrl && <TeamOutlined />}
                size={80}
                style={{ background: '#1890ff' }}
              />
              <Title level={4} style={{ marginTop: 12, marginBottom: 4 }}>
                {team.name}
              </Title>
              <Text type="secondary" style={{ display: 'block', marginBottom: 8 }}>
                @{team.slug}
              </Text>
              <Tag color={statusConfig.color}>{statusConfig.label}</Tag>
              {team.isRecruiting && (
                <Tag color="blue" style={{ marginLeft: 4 }}>모집중</Tag>
              )}
            </div>

            <Divider />

            {/* 팀 통계 */}
            <Row gutter={8} style={{ marginBottom: 16 }}>
              <Col span={8}>
                <Statistic
                  title="ELO 점수"
                  value={team.teamScore}
                  valueStyle={{ fontSize: 18, color: '#1890ff' }}
                />
              </Col>
              <Col span={8}>
                <Statistic
                  title="멤버"
                  value={team.currentMembers}
                  suffix={`/${team.maxMembers}`}
                  valueStyle={{ fontSize: 18 }}
                />
              </Col>
              <Col span={8}>
                <Statistic
                  title="전적"
                  value={team.wins}
                  suffix={`W`}
                  valueStyle={{ fontSize: 18, color: '#52c41a' }}
                />
              </Col>
            </Row>

            <div style={{ marginBottom: 16 }}>
              <Space>
                <Tag color="green">{team.wins}승</Tag>
                <Tag color="red">{team.losses}패</Tag>
                <Tag color="default">{team.draws}무</Tag>
              </Space>
            </div>

            <Descriptions column={1} size="small">
              <Descriptions.Item label="종목">
                {sportConfig ? `${sportConfig.icon} ${sportConfig.label}` : team.sportType}
              </Descriptions.Item>
              <Descriptions.Item label="활동 지역">
                {team.activityRegion || <Text type="secondary">미설정</Text>}
              </Descriptions.Item>
              <Descriptions.Item label="생성일">
                {dayjs(team.createdAt).format('YYYY-MM-DD')}
              </Descriptions.Item>
            </Descriptions>

            {team.description && (
              <>
                <Divider />
                <Text type="secondary" style={{ fontSize: 13 }}>{team.description}</Text>
              </>
            )}

            <Divider />

            {/* 어드민 액션 버튼 */}
            <Space direction="vertical" style={{ width: '100%' }}>
              <Button
                icon={<EditOutlined />}
                style={{ width: '100%' }}
                onClick={() => setScoreModalOpen(true)}
              >
                점수 수동 조정
              </Button>

              {team.status === 'ACTIVE' && (
                <Button
                  danger
                  icon={<StopOutlined />}
                  style={{ width: '100%' }}
                  onClick={() => setSuspendOpen(true)}
                >
                  팀 정지
                </Button>
              )}

              {team.status === 'INACTIVE' && (
                <Button
                  icon={<CheckCircleOutlined />}
                  style={{ width: '100%', color: '#52c41a', borderColor: '#52c41a' }}
                  onClick={() => activateMutation.mutate(team.id)}
                  loading={activateMutation.isPending}
                >
                  팀 활성화
                </Button>
              )}

              {team.status !== 'DISBANDED' && (
                <Button
                  danger
                  icon={<DeleteOutlined />}
                  style={{ width: '100%' }}
                  onClick={() => setDisbandOpen(true)}
                >
                  팀 해산
                </Button>
              )}
            </Space>
          </Card>
        </Col>

        {/* 탭 영역 */}
        <Col xs={24} lg={17}>
          <Card style={{ borderRadius: 8 }}>
            <Tabs
              defaultActiveKey="members"
              items={[
                {
                  key: 'members',
                  label: `멤버 목록 (${members.length})`,
                  children: (
                    <Table
                      columns={memberColumns}
                      dataSource={members}
                      rowKey="id"
                      size="small"
                      pagination={{
                        pageSize: 10,
                        showTotal: (total) => `총 ${total}명`,
                      }}
                      locale={{ emptyText: '멤버가 없습니다.' }}
                      scroll={{ x: 600 }}
                    />
                  ),
                },
                {
                  key: 'matches',
                  label: `매칭 이력 (${matches.length})`,
                  children: (
                    <Table
                      columns={matchColumns}
                      dataSource={matches}
                      rowKey="id"
                      size="small"
                      pagination={{
                        pageSize: 10,
                        showTotal: (total) => `총 ${total}건`,
                      }}
                      locale={{ emptyText: '매칭 이력이 없습니다.' }}
                      scroll={{ x: 700 }}
                    />
                  ),
                },
                {
                  key: 'posts',
                  label: `게시글 (${posts.length})`,
                  children: (
                    <Table
                      columns={postColumns}
                      dataSource={posts}
                      rowKey="id"
                      size="small"
                      pagination={{
                        pageSize: 10,
                        showTotal: (total) => `총 ${total}건`,
                      }}
                      locale={{ emptyText: '게시글이 없습니다.' }}
                      scroll={{ x: 600 }}
                    />
                  ),
                },
              ]}
            />
          </Card>
        </Col>
      </Row>

      {/* 팀 정지 모달 */}
      <ConfirmAction
        open={suspendOpen}
        title={`'${team.name}' 팀을 정지하시겠습니까?`}
        description="정지된 팀은 매칭 및 활동이 제한됩니다."
        requireReason
        reasonLabel="정지 사유"
        reasonPlaceholder="정지 사유를 입력해주세요."
        onConfirm={async (reason) => {
          if (reason) {
            await suspendMutation.mutateAsync({ teamId: team.id, reason });
            setSuspendOpen(false);
          }
        }}
        onCancel={() => setSuspendOpen(false)}
        loading={suspendMutation.isPending}
        confirmText="정지"
      />

      {/* 팀 해산 모달 */}
      <ConfirmAction
        open={disbandOpen}
        title={`'${team.name}' 팀을 해산하시겠습니까?`}
        description="해산된 팀은 복구할 수 없습니다. 신중하게 처리해주세요."
        requireReason
        reasonLabel="해산 사유"
        reasonPlaceholder="해산 사유를 입력해주세요."
        onConfirm={async (reason) => {
          if (reason) {
            await disbandMutation.mutateAsync({ teamId: team.id, reason });
            setDisbandOpen(false);
          }
        }}
        onCancel={() => setDisbandOpen(false)}
        loading={disbandMutation.isPending}
        confirmText="해산"
      />

      {/* 멤버 추방 모달 */}
      <ConfirmAction
        open={!!removeTarget}
        title={`'${removeTarget?.user?.nickname || removeTarget?.userId}' 멤버를 추방하시겠습니까?`}
        description="추방된 멤버는 팀에서 제거됩니다."
        requireReason
        reasonLabel="추방 사유"
        reasonPlaceholder="추방 사유를 입력해주세요."
        onConfirm={async (reason) => {
          if (removeTarget && reason) {
            await removeMemberMutation.mutateAsync({
              teamId: id!,
              userId: removeTarget.userId,
              reason,
            });
            setRemoveTarget(null);
          }
        }}
        onCancel={() => setRemoveTarget(null)}
        loading={removeMemberMutation.isPending}
        confirmText="추방"
      />

      {/* 점수 조정 모달 */}
      <Modal
        open={scoreModalOpen}
        title="팀 점수 수동 조정"
        onOk={async () => {
          try {
            const values = await scoreForm.validateFields();
            await updateScoreMutation.mutateAsync({
              teamId: team.id,
              score: values.score,
              reason: values.reason,
            });
            scoreForm.resetFields();
            setScoreModalOpen(false);
          } catch {
            // validation error
          }
        }}
        onCancel={() => {
          scoreForm.resetFields();
          setScoreModalOpen(false);
        }}
        okText="조정"
        cancelText="취소"
        okButtonProps={{ loading: updateScoreMutation.isPending }}
      >
        <Form form={scoreForm} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item
            name="score"
            label="조정할 점수"
            rules={[
              { required: true, message: '점수를 입력해주세요.' },
              { type: 'number', min: 0, message: '0 이상의 점수를 입력해주세요.' },
            ]}
            extra={`현재 점수: ${(team?.teamScore ?? 0).toLocaleString()}`}
          >
            <InputNumber
              style={{ width: '100%' }}
              placeholder="새로운 ELO 점수"
              min={0}
              max={9999}
            />
          </Form.Item>
          <Form.Item
            name="reason"
            label="조정 사유"
            rules={[{ required: true, message: '조정 사유를 입력해주세요.' }]}
          >
            <TextArea rows={3} placeholder="점수 조정 사유를 입력해주세요." showCount maxLength={500} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
