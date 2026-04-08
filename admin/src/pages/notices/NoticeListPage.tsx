import { useState } from 'react';
import {
  Typography,
  Card,
  Button,
  Tag,
  Space,
  Table,
  Modal,
  Form,
  Input,
  Checkbox,
  Popconfirm,
  message,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { PlusOutlined, EditOutlined, DeleteOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { noticesApi } from '@/api/notices.api';
import type { Notice, CreateNoticeRequest } from '@/api/notices.api';

const { Title, Text } = Typography;

export function NoticeListPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<Notice | null>(null);
  const [form] = Form.useForm<CreateNoticeRequest>();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-notices', page],
    queryFn: () => noticesApi.list(page, 20),
  });

  const createMutation = useMutation({
    mutationFn: (values: CreateNoticeRequest) => noticesApi.create(values),
    onSuccess: () => {
      message.success('공지사항이 등록되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['admin-notices'] });
      handleCloseModal();
    },
    onError: () => {
      message.error('등록 중 오류가 발생했습니다.');
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, values }: { id: string; values: Partial<CreateNoticeRequest> }) =>
      noticesApi.update(id, values),
    onSuccess: () => {
      message.success('공지사항이 수정되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['admin-notices'] });
      handleCloseModal();
    },
    onError: () => {
      message.error('수정 중 오류가 발생했습니다.');
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => noticesApi.delete(id),
    onSuccess: () => {
      message.success('공지사항이 삭제되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['admin-notices'] });
    },
    onError: () => {
      message.error('삭제 중 오류가 발생했습니다.');
    },
  });

  const handleOpenCreate = () => {
    setEditTarget(null);
    form.resetFields();
    form.setFieldsValue({ isPublished: true, isPinned: false });
    setModalOpen(true);
  };

  const handleOpenEdit = (record: Notice) => {
    setEditTarget(record);
    form.setFieldsValue({
      title: record.title,
      content: record.content,
      isPinned: record.isPinned,
      isPublished: record.isPublished,
    });
    setModalOpen(true);
  };

  const handleCloseModal = () => {
    setModalOpen(false);
    setEditTarget(null);
    form.resetFields();
  };

  const handleSubmit = async () => {
    try {
      const values = await form.validateFields();
      if (editTarget) {
        updateMutation.mutate({ id: editTarget.id, values });
      } else {
        createMutation.mutate(values);
      }
    } catch {
      // 유효성 검증 실패 — form 자체가 에러를 표시함
    }
  };

  const isMutating = createMutation.isPending || updateMutation.isPending;

  const columns: TableColumnsType<Notice> = [
    {
      title: '제목',
      dataIndex: 'title',
      key: 'title',
      render: (title: string) => (
        <Text style={{ fontWeight: 500 }}>{title}</Text>
      ),
    },
    {
      title: '메인 노출',
      dataIndex: 'isPinned',
      key: 'isPinned',
      render: (isPinned: boolean) =>
        isPinned ? (
          <Tag color="blue">노출중</Tag>
        ) : (
          <Tag color="default">미노출</Tag>
        ),
      width: 110,
      align: 'center',
    },
    {
      title: '상태',
      dataIndex: 'isPublished',
      key: 'isPublished',
      render: (isPublished: boolean) =>
        isPublished ? (
          <Tag color="green">게시</Tag>
        ) : (
          <Tag color="orange">비게시</Tag>
        ),
      width: 90,
      align: 'center',
    },
    {
      title: '작성일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('YYYY-MM-DD HH:mm'),
      width: 160,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record) => (
        <Space>
          <Button
            type="text"
            icon={<EditOutlined />}
            onClick={() => handleOpenEdit(record)}
          />
          <Popconfirm
            title="정말 삭제하시겠습니까?"
            okText="삭제"
            cancelText="취소"
            okButtonProps={{ danger: true }}
            onConfirm={() => deleteMutation.mutate(record.id)}
          >
            <Button
              type="text"
              danger
              icon={<DeleteOutlined />}
              loading={deleteMutation.isPending && deleteMutation.variables === record.id}
            />
          </Popconfirm>
        </Space>
      ),
      width: 90,
    },
  ];

  return (
    <div>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-start',
          marginBottom: 20,
        }}
      >
        <div>
          <Title level={4} style={{ marginBottom: 4 }}>
            공지사항 관리
          </Title>
          <Text type="secondary">공지사항 등록, 수정 및 삭제</Text>
        </div>
        <Button
          type="primary"
          icon={<PlusOutlined />}
          onClick={handleOpenCreate}
        >
          새 공지 작성
        </Button>
      </div>

      <Card style={{ borderRadius: 8 }}>
        <Table
          columns={columns}
          dataSource={data?.data || []}
          loading={isLoading}
          rowKey="id"
          pagination={{
            current: page,
            pageSize: 20,
            total: data?.meta?.total || 0,
            showTotal: (total) => `총 ${total.toLocaleString()}건`,
            onChange: setPage,
          }}
          scroll={{ x: 700 }}
        />
      </Card>

      {/* 공지 작성/수정 모달 */}
      <Modal
        open={modalOpen}
        title={editTarget ? '공지사항 수정' : '새 공지 작성'}
        onCancel={handleCloseModal}
        onOk={handleSubmit}
        okText="저장"
        cancelText="취소"
        confirmLoading={isMutating}
        width={640}
        destroyOnClose
      >
        <Form form={form} layout="vertical" style={{ marginTop: 16 }}>
          <Form.Item
            label="제목"
            name="title"
            rules={[{ required: true, message: '제목을 입력해주세요.' }]}
          >
            <Input placeholder="공지사항 제목" maxLength={200} showCount />
          </Form.Item>
          <Form.Item
            label="내용"
            name="content"
            rules={[{ required: true, message: '내용을 입력해주세요.' }]}
          >
            <Input.TextArea
              rows={8}
              placeholder="공지사항 내용"
              style={{ resize: 'vertical' }}
            />
          </Form.Item>
          <Form.Item name="isPinned" valuePropName="checked">
            <Checkbox>메인 화면에 공지 표시</Checkbox>
          </Form.Item>
          <Form.Item name="isPublished" valuePropName="checked" initialValue={true}>
            <Checkbox>게시</Checkbox>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
