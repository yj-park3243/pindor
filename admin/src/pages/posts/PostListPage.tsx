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
  Tooltip,
  Modal,
  Descriptions,
  Image,
  Switch,
} from 'antd';
import type { TableColumnsType } from 'antd';
import {
  SearchOutlined,
  DeleteOutlined,
  EyeInvisibleOutlined,
  EyeOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import { usePostList, useDeletePost, useBlindPost } from '@/hooks/usePosts';
import { ConfirmAction } from '@/components/ConfirmAction';
import { UserAvatar } from '@/components/UserAvatar';
import type { PinPost } from '@/types/pin';

const { Title, Text } = Typography;

const CATEGORY_CONFIG = {
  GENERAL: { label: '일반', color: 'default' },
  MATCH_SEEK: { label: '매칭 구인', color: 'blue' },
  REVIEW: { label: '후기', color: 'green' },
  NOTICE: { label: '공지', color: 'red' },
} as const;

export function PostListPage() {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState<string | undefined>();
  const [showDeleted, setShowDeleted] = useState(false);
  const [page, setPage] = useState(1);
  const [deleteTarget, setDeleteTarget] = useState<PinPost | null>(null);
  const [blindTarget, setBlindTarget] = useState<PinPost | null>(null);
  const [detailTarget, setDetailTarget] = useState<PinPost | null>(null);

  const { data, isLoading } = usePostList({
    search: search || undefined,
    category,
    isDeleted: showDeleted ? true : undefined,
    page,
    pageSize: 20,
  });

  const deleteMutation = useDeletePost();
  const blindMutation = useBlindPost();

  const columns: TableColumnsType<PinPost> = [
    {
      title: '핀',
      key: 'pin',
      render: (_, record) => (
        <Tag>{record.pin?.name || record.pinId.slice(0, 8)}</Tag>
      ),
      width: 120,
    },
    {
      title: '카테고리',
      dataIndex: 'category',
      key: 'category',
      render: (cat: string) => {
        const cfg = CATEGORY_CONFIG[cat as keyof typeof CATEGORY_CONFIG];
        return cfg ? <Tag color={cfg.color}>{cfg.label}</Tag> : <Tag>{cat}</Tag>;
      },
      width: 100,
    },
    {
      title: '제목',
      dataIndex: 'title',
      key: 'title',
      render: (title: string, record: PinPost) => (
        <Space>
          <Button
            type="link"
            style={{ padding: 0, maxWidth: 250, textAlign: 'left' }}
            onClick={() => setDetailTarget(record)}
          >
            <Text ellipsis style={{ maxWidth: 250 }}>{title}</Text>
          </Button>
          {record.isBlinded && <Tag color="orange" style={{ fontSize: 11 }}>블라인드</Tag>}
          {record.isDeleted && <Tag color="red" style={{ fontSize: 11 }}>삭제됨</Tag>}
        </Space>
      ),
    },
    {
      title: '작성자',
      key: 'author',
      render: (_, record) => (
        <UserAvatar
          src={record.author?.profileImageUrl}
          nickname={record.author?.nickname || '-'}
          size="small"
        />
      ),
      width: 130,
    },
    {
      title: '조회/좋아요/댓글',
      key: 'stats',
      render: (_, record) => (
        <Space style={{ fontSize: 12, color: '#666' }}>
          <span>👁 {record.viewCount}</span>
          <span>❤ {record.likeCount}</span>
          <span>💬 {record.commentCount}</span>
        </Space>
      ),
      width: 160,
    },
    {
      title: '작성일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('MM-DD HH:mm'),
      sorter: true,
      width: 110,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record) => (
        <Space>
          <Tooltip title={record.isBlinded ? '블라인드 해제' : '블라인드'}>
            <Button
              type="text"
              icon={record.isBlinded ? <EyeOutlined /> : <EyeInvisibleOutlined />}
              style={{ color: record.isBlinded ? '#52c41a' : '#fa8c16' }}
              onClick={() => setBlindTarget(record)}
              disabled={record.isDeleted}
            />
          </Tooltip>
          <Tooltip title="삭제">
            <Button
              type="text"
              danger
              icon={<DeleteOutlined />}
              onClick={() => setDeleteTarget(record)}
              disabled={record.isDeleted}
            />
          </Tooltip>
        </Space>
      ),
      width: 90,
    },
  ];

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        게시판 관리
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        게시글 목록 조회, 삭제 및 블라인드 처리
      </Text>

      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]} align="middle">
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="제목, 작성자로 검색"
              prefix={<SearchOutlined />}
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              allowClear
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="카테고리"
              style={{ width: '100%' }}
              allowClear
              value={category}
              onChange={(v) => { setCategory(v); setPage(1); }}
              options={Object.entries(CATEGORY_CONFIG).map(([value, { label }]) => ({
                value, label,
              }))}
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Space>
              <Switch
                checked={showDeleted}
                onChange={setShowDeleted}
                size="small"
              />
              <Text style={{ fontSize: 13 }}>삭제된 글 포함</Text>
            </Space>
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
          scroll={{ x: 900 }}
        />
      </Card>

      {/* 게시글 상세 모달 */}
      <Modal
        open={!!detailTarget}
        title={detailTarget?.title}
        onCancel={() => setDetailTarget(null)}
        footer={null}
        width={700}
      >
        {detailTarget && (
          <div>
            <Descriptions column={2} size="small" style={{ marginBottom: 16 }}>
              <Descriptions.Item label="작성자">
                {detailTarget.author?.nickname}
              </Descriptions.Item>
              <Descriptions.Item label="작성일">
                {dayjs(detailTarget.createdAt).format('YYYY-MM-DD HH:mm')}
              </Descriptions.Item>
              <Descriptions.Item label="카테고리">
                {CATEGORY_CONFIG[detailTarget.category as keyof typeof CATEGORY_CONFIG]?.label}
              </Descriptions.Item>
              <Descriptions.Item label="핀">
                {detailTarget.pin?.name || '-'}
              </Descriptions.Item>
            </Descriptions>
            <div
              style={{
                background: '#fafafa',
                padding: 16,
                borderRadius: 8,
                marginBottom: 16,
                whiteSpace: 'pre-wrap',
                lineHeight: 1.7,
              }}
            >
              {detailTarget.content}
            </div>
            {detailTarget.images && detailTarget.images.length > 0 && (
              <Image.PreviewGroup>
                <Space wrap>
                  {detailTarget.images.map((img) => (
                    <Image key={img.id} src={img.imageUrl} width={100} height={100}
                      style={{ objectFit: 'cover', borderRadius: 8 }}
                    />
                  ))}
                </Space>
              </Image.PreviewGroup>
            )}
          </div>
        )}
      </Modal>

      {/* 삭제 확인 */}
      <ConfirmAction
        open={!!deleteTarget}
        title={`'${deleteTarget?.title}' 게시글을 삭제하시겠습니까?`}
        requireReason
        reasonLabel="삭제 사유"
        onConfirm={async (reason) => {
          if (deleteTarget && reason) {
            await deleteMutation.mutateAsync({ id: deleteTarget.id, reason });
            setDeleteTarget(null);
          }
        }}
        onCancel={() => setDeleteTarget(null)}
        loading={deleteMutation.isPending}
        confirmText="삭제"
      />

      {/* 블라인드 확인 */}
      <ConfirmAction
        open={!!blindTarget}
        title={
          blindTarget?.isBlinded
            ? `'${blindTarget?.title}' 게시글의 블라인드를 해제하시겠습니까?`
            : `'${blindTarget?.title}' 게시글을 블라인드 처리하시겠습니까?`
        }
        requireReason={!blindTarget?.isBlinded}
        reasonLabel="블라인드 사유"
        onConfirm={async (reason) => {
          if (blindTarget) {
            await blindMutation.mutateAsync({ id: blindTarget.id, reason: reason || '' });
            setBlindTarget(null);
          }
        }}
        onCancel={() => setBlindTarget(null)}
        loading={blindMutation.isPending}
        danger={!blindTarget?.isBlinded}
        confirmText={blindTarget?.isBlinded ? '해제' : '블라인드'}
      />
    </div>
  );
}
