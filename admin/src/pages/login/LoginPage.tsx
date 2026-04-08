import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Card,
  Form,
  Input,
  Button,
  Typography,
  Alert,
  Space,
  Divider,
} from 'antd';
import { UserOutlined, LockOutlined, SafetyOutlined } from '@ant-design/icons';
import { authApi } from '@/api/auth.api';
import { useAuthStore } from '@/store/auth.store';
import { AuthLayout } from '@/layouts/AuthLayout';
import { ROUTES } from '@/config/routes';

const { Title, Text } = Typography;

interface LoginFormValues {
  email: string;
  password: string;
  mfaCode?: string;
}

export function LoginPage() {
  const [form] = Form.useForm<LoginFormValues>();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [requireMfa, setRequireMfa] = useState(false);
  const navigate = useNavigate();
  const { login } = useAuthStore();

  const handleSubmit = async (values: LoginFormValues) => {
    try {
      setLoading(true);
      setError(null);

      const result = await authApi.login({
        email: values.email,
        password: values.password,
        mfaCode: values.mfaCode,
      });

      login(result.admin, result.accessToken, result.refreshToken);
      navigate(ROUTES.DASHBOARD, { replace: true });
    } catch (err: unknown) {
      const axiosError = err as { response?: { data?: { error?: { code?: string; message?: string } } } };
      const code = axiosError?.response?.data?.error?.code;

      if (code === 'MFA_REQUIRED') {
        setRequireMfa(true);
        setError('MFA 인증 코드를 입력해주세요.');
      } else if (code === 'INVALID_MFA') {
        setError('MFA 코드가 올바르지 않습니다.');
      } else {
        setError('이메일 또는 비밀번호가 올바르지 않습니다.');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout>
      <Card
        style={{
          width: 400,
          borderRadius: 16,
          boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
        }}
        styles={{ body: { padding: '40px 40px 32px' } }}
      >
        {/* 헤더 */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{ fontSize: 48, marginBottom: 12 }}>⛳</div>
          <Title level={3} style={{ margin: 0, color: '#001529' }}>
            핀돌 Admin
          </Title>
          <Text type="secondary">관리자 포털</Text>
        </div>

        <Divider style={{ margin: '0 0 24px' }} />

        {error && (
          <Alert
            message={error}
            type="error"
            showIcon
            style={{ marginBottom: 16, borderRadius: 8 }}
          />
        )}

        <Form
          form={form}
          layout="vertical"
          onFinish={handleSubmit}
          autoComplete="off"
          requiredMark={false}
        >
          <Form.Item
            name="email"
            label="이메일"
            rules={[
              { required: true, message: '이메일을 입력해주세요.' },
              { type: 'email', message: '올바른 이메일 형식이 아닙니다.' },
            ]}
          >
            <Input
              prefix={<UserOutlined style={{ color: '#bbb' }} />}
              placeholder="admin@sportsmatch.kr"
              size="large"
            />
          </Form.Item>

          <Form.Item
            name="password"
            label="비밀번호"
            rules={[{ required: true, message: '비밀번호를 입력해주세요.' }]}
          >
            <Input.Password
              prefix={<LockOutlined style={{ color: '#bbb' }} />}
              placeholder="비밀번호"
              size="large"
            />
          </Form.Item>

          {requireMfa && (
            <Form.Item
              name="mfaCode"
              label="MFA 인증 코드"
              rules={[
                { required: true, message: 'MFA 코드를 입력해주세요.' },
                { len: 6, message: '6자리 코드를 입력해주세요.' },
              ]}
              extra="인증 앱(Google Authenticator 등)에서 코드를 확인해주세요."
            >
              <Input
                prefix={<SafetyOutlined style={{ color: '#bbb' }} />}
                placeholder="000000"
                maxLength={6}
                size="large"
                style={{ letterSpacing: '0.3em' }}
              />
            </Form.Item>
          )}

          <Form.Item style={{ marginBottom: 12, marginTop: 8 }}>
            <Button
              type="primary"
              htmlType="submit"
              size="large"
              loading={loading}
              block
              style={{ borderRadius: 8, fontWeight: 600 }}
            >
              로그인
            </Button>
          </Form.Item>
        </Form>

        <Space
          style={{
            width: '100%',
            justifyContent: 'center',
            marginTop: 8,
          }}
        >
          <Text type="secondary" style={{ fontSize: 12 }}>
            핀돌 Admin 포털 v1.0
          </Text>
        </Space>
      </Card>
    </AuthLayout>
  );
}
