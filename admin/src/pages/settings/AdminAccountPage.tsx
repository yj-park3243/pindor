import { useState } from 'react';
import {
  Typography,
  Card,
  Table,
  Button,
  Tag,
  Space,
  Modal,
  Form,
  Input,
  Select,
  Popconfirm,
  Tooltip,
  Alert,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { PlusOutlined, EditOutlined, DeleteOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { settingsApi } from '@/api/settings.api';
import { useAuthStore } from '@/store/auth.store';
import { ADMIN_ROLE_CONFIG } from '@/config/constants';
import type { AdminUser, AdminRole } from '@/store/auth.store';

const { Title, Text } = Typography;

interface AccountFormValues {
  email: string;
  name: string;
  password?: string;
  role: AdminRole;
}

export function AdminAccountPage() {
  const { admin: currentAdmin } = useAuthStore();
  const queryClient = useQueryClient();
  const [formOpen, setFormOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<AdminUser | null>(null);
  const [form] = Form.useForm<AccountFormValues>();

  const { data: accounts, isLoading } = useQuery({
    queryKey: ['settings', 'accounts'],
    queryFn: settingsApi.getAdminAccounts,
  });

  const createMutation = useMutation({
    mutationFn: settingsApi.createAdminAccount,
    onSuccess: () => {
      message.success('어드민 계정이 생성되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['settings', 'accounts'] });
      setFormOpen(false);
      form.resetFields();
    },
    onError: () => message.error('계정 생성에 실패했습니다.'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: AccountFormValues }) =>
      settingsApi.updateAdminAccount(id, data),
    onSuccess: () => {
      message.success('계정이 수정되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['settings', 'accounts'] });
      setFormOpen(false);
      setEditTarget(null);
      form.resetFields();
    },
    onError: () => message.error('계정 수정에 실패했습니다.'),
  });

  const deleteMutation = useMutation({
    mutationFn: settingsApi.deleteAdminAccount,
    onSuccess: () => {
      message.success('계정이 삭제되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['settings', 'accounts'] });
    },
    onError: () => message.error('계정 삭제에 실패했습니다.'),
  });

  const handleSubmit = async (values: AccountFormValues) => {
    if (editTarget) {
      await updateMutation.mutateAsync({ id: editTarget.id, data: values });
    } else {
      await createMutation.mutateAsync({
        email: values.email,
        password: values.password!,
        name: values.name,
        role: values.role,
      });
    }
  };

  const openCreate = () => {
    setEditTarget(null);
    form.resetFields();
    setFormOpen(true);
  };

  const openEdit = (account: AdminUser) => {
    setEditTarget(account);
    form.setFieldsValue({
      name: account.name,
      email: account.email,
      role: account.role,
    });
    setFormOpen(true);
  };

  const columns: TableColumnsType<AdminUser> = [
    {
      title: '이름',
      dataIndex: 'name',
      key: 'name',
    },
    {
      title: '이메일',
      dataIndex: 'email',
      key: 'email',
    },
    {
      title: '역할',
      dataIndex: 'role',
      key: 'role',
      render: (role: AdminRole) => {
        const cfg = ADMIN_ROLE_CONFIG[role];
        return <Tag color={cfg.color}>{cfg.label}</Tag>;
      },
      width: 120,
    },
    {
      title: '가입일',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (d: string) => dayjs(d).format('YYYY-MM-DD'),
      width: 120,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record) => {
        const isSelf = record.id === currentAdmin?.id;
        return (
          <Space>
            <Tooltip title="수정">
              <Button
                type="text"
                icon={<EditOutlined />}
                onClick={() => openEdit(record)}
              />
            </Tooltip>
            {!isSelf && (
              <Popconfirm
                title="이 계정을 삭제하시겠습니까?"
                onConfirm={() => deleteMutation.mutate(record.id)}
                okText="삭제"
                cancelText="취소"
                okButtonProps={{ danger: true }}
              >
                <Tooltip title="삭제">
                  <Button type="text" danger icon={<DeleteOutlined />} />
                </Tooltip>
              </Popconfirm>
            )}
          </Space>
        );
      },
      width: 100,
    },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
        <Title level={4} style={{ margin: 0 }}>
          어드민 계정 관리
        </Title>
        <Button
          type="primary"
          icon={<PlusOutlined />}
          onClick={openCreate}
        >
          계정 추가
        </Button>
      </div>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        어드민 포털 접근 계정 관리
      </Text>

      <Alert
        message="권한 안내"
        description={
          <ul style={{ margin: 0, paddingLeft: 20, fontSize: 13 }}>
            <li>SUPER_ADMIN: 모든 기능 접근 가능, 어드민 계정 관리 포함</li>
            <li>ADMIN: 설정 메뉴를 제외한 모든 기능 접근 가능</li>
            <li>MODERATOR: 사용자 관리, 게시판 관리, 신고 처리만 가능</li>
          </ul>
        }
        type="info"
        showIcon
        style={{ marginBottom: 16 }}
      />

      <Card style={{ borderRadius: 8 }}>
        <Table
          columns={columns}
          dataSource={accounts || []}
          loading={isLoading}
          rowKey="id"
          pagination={false}
        />
      </Card>

      <Modal
        open={formOpen}
        title={editTarget ? '계정 수정' : '계정 추가'}
        onOk={() => form.submit()}
        onCancel={() => { setFormOpen(false); setEditTarget(null); form.resetFields(); }}
        okText={editTarget ? '수정' : '생성'}
        cancelText="취소"
        confirmLoading={createMutation.isPending || updateMutation.isPending}
        destroyOnHide
      >
        <Form form={form} layout="vertical" onFinish={handleSubmit}>
          <Form.Item
            name="name"
            label="이름"
            rules={[{ required: true, message: '이름을 입력해주세요.' }]}
          >
            <Input placeholder="홍길동" />
          </Form.Item>

          <Form.Item
            name="email"
            label="이메일"
            rules={[
              { required: true, message: '이메일을 입력해주세요.' },
              { type: 'email', message: '올바른 이메일 형식이 아닙니다.' },
            ]}
          >
            <Input placeholder="admin@sportsmatch.kr" disabled={!!editTarget} />
          </Form.Item>

          {!editTarget && (
            <Form.Item
              name="password"
              label="초기 비밀번호"
              rules={[
                { required: true, message: '비밀번호를 입력해주세요.' },
                { min: 8, message: '8자 이상 입력해주세요.' },
              ]}
            >
              <Input.Password placeholder="8자 이상" />
            </Form.Item>
          )}

          <Form.Item
            name="role"
            label="역할"
            rules={[{ required: true, message: '역할을 선택해주세요.' }]}
          >
            <Select>
              {Object.entries(ADMIN_ROLE_CONFIG).map(([value, { label, color }]) => (
                <Select.Option key={value} value={value}>
                  <Tag color={color}>{label}</Tag>
                </Select.Option>
              ))}
            </Select>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
