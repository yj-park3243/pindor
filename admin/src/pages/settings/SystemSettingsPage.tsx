import {
  Typography,
  Card,
  Form,
  InputNumber,
  Button,
  Row,
  Col,
  Divider,
  Alert,
  Spin,
  Tabs,
} from 'antd';
import { SaveOutlined } from '@ant-design/icons';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { message } from 'antd';
import { settingsApi } from '@/api/settings.api';
import type { SystemSettings } from '@/api/settings.api';

const { Title, Text } = Typography;

export function SystemSettingsPage() {
  const queryClient = useQueryClient();
  const [kForm] = Form.useForm();
  const [tierForm] = Form.useForm();
  const [matchForm] = Form.useForm();
  const [rankingForm] = Form.useForm();

  const { data: settings, isLoading } = useQuery({
    queryKey: ['settings', 'system'],
    queryFn: settingsApi.getSystemSettings,
  });

  // 설정 데이터 로드 후 폼 초기값 설정
  if (settings) {
    kForm.setFieldsValue(settings.kFactor);
    tierForm.setFieldsValue(settings.tierThresholds);
    matchForm.setFieldsValue(settings.matchSettings);
    rankingForm.setFieldsValue(settings.rankingSettings);
  }

  const updateMutation = useMutation({
    mutationFn: (data: Partial<SystemSettings>) => settingsApi.updateSystemSettings(data),
    onSuccess: () => {
      message.success('설정이 저장되었습니다.');
      queryClient.invalidateQueries({ queryKey: ['settings', 'system'] });
    },
    onError: () => message.error('설정 저장에 실패했습니다.'),
  });

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 80 }}>
        <Spin size="large" />
      </div>
    );
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 4 }}>
        시스템 설정
      </Title>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        K계수, 티어 기준, 매칭 설정 등 시스템 파라미터 관리
      </Text>

      <Alert
        message="설정 변경 주의사항"
        description="시스템 설정 변경은 즉시 서비스에 적용됩니다. 신중하게 변경해주세요."
        type="warning"
        showIcon
        style={{ marginBottom: 20 }}
      />

      <Tabs
        defaultActiveKey="kfactor"
        items={[
          {
            key: 'kfactor',
            label: 'ELO K계수',
            children: (
              <Card style={{ borderRadius: 8 }}>
                <Alert
                  message="K계수 설명"
                  description="K계수는 경기 결과에 따른 점수 변동폭을 결정합니다. 값이 클수록 점수 변동이 커집니다."
                  type="info"
                  showIcon
                  style={{ marginBottom: 20 }}
                />
                <Form
                  form={kForm}
                  layout="vertical"
                  initialValues={settings?.kFactor}
                  onFinish={(values) => updateMutation.mutate({ kFactor: values })}
                >
                  <Row gutter={24}>
                    <Col xs={24} sm={12} lg={6}>
                      <Form.Item
                        name="beginner"
                        label="입문 (첫 10게임)"
                        extra="빠른 점수 수렴"
                        rules={[{ required: true }, { type: 'number', min: 10, max: 80 }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={10} max={80} />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={6}>
                      <Form.Item
                        name="intermediate"
                        label="중간 (11~30게임)"
                        extra="중간 수렴 단계"
                        rules={[{ required: true }, { type: 'number', min: 10, max: 60 }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={10} max={60} />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={6}>
                      <Form.Item
                        name="standard"
                        label="표준 (31게임 이상)"
                        extra="안정화 단계"
                        rules={[{ required: true }, { type: 'number', min: 8, max: 40 }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={8} max={40} />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={6}>
                      <Form.Item
                        name="platinum"
                        label="플래티넘 티어"
                        extra="고점수 변동 억제"
                        rules={[{ required: true }, { type: 'number', min: 4, max: 24 }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={4} max={24} />
                      </Form.Item>
                    </Col>
                  </Row>
                  <Button
                    type="primary"
                    htmlType="submit"
                    icon={<SaveOutlined />}
                    loading={updateMutation.isPending}
                  >
                    K계수 저장
                  </Button>
                </Form>
              </Card>
            ),
          },
          {
            key: 'tier',
            label: '티어 기준',
            children: (
              <Card style={{ borderRadius: 8 }}>
                <Alert
                  message="티어 점수 기준 (최솟값)"
                  description="각 티어의 최소 점수를 설정합니다. 브론즈 최솟값은 시스템 하한선입니다."
                  type="info"
                  showIcon
                  style={{ marginBottom: 20 }}
                />
                <Form
                  form={tierForm}
                  layout="vertical"
                  initialValues={settings?.tierThresholds}
                  onFinish={(values) => updateMutation.mutate({ tierThresholds: values })}
                >
                  <Row gutter={24}>
                    {[
                      { name: 'bronzeMin', label: '브론즈 최솟값', color: '#CD7F32' },
                      { name: 'silverMin', label: '실버 최솟값', color: '#C0C0C0' },
                      { name: 'goldMin', label: '골드 최솟값', color: '#FFD700' },
                      { name: 'platinumMin', label: '플래티넘 최솟값', color: '#888' },
                    ].map(({ name, label, color }) => (
                      <Col xs={24} sm={12} lg={6} key={name}>
                        <Form.Item
                          name={name}
                          label={<span style={{ color, fontWeight: 600 }}>{label}</span>}
                          rules={[{ required: true }, { type: 'number', min: 100 }]}
                        >
                          <InputNumber
                            style={{ width: '100%', borderColor: color }}
                            min={100}
                            max={3000}
                            step={50}
                            addonAfter="점"
                          />
                        </Form.Item>
                      </Col>
                    ))}
                  </Row>
                  <Button
                    type="primary"
                    htmlType="submit"
                    icon={<SaveOutlined />}
                    loading={updateMutation.isPending}
                  >
                    티어 기준 저장
                  </Button>
                </Form>
              </Card>
            ),
          },
          {
            key: 'match',
            label: '매칭 설정',
            children: (
              <Card style={{ borderRadius: 8 }}>
                <Form
                  form={matchForm}
                  layout="vertical"
                  initialValues={settings?.matchSettings}
                  onFinish={(values) => updateMutation.mutate({ matchSettings: values })}
                >
                  <Row gutter={24}>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="expirationHours"
                        label="매칭 요청 만료 시간"
                        extra="대기 중 매칭 요청 자동 만료 시간"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={1} max={72} addonAfter="시간" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="instantMatchWindowHours"
                        label="즉시 매칭 유효 시간"
                        extra="오늘 대결 요청 유효 시간"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={1} max={12} addonAfter="시간" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="defaultRadiusKm"
                        label="기본 매칭 반경"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={1} max={50} addonAfter="km" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="minRadiusKm"
                        label="최소 매칭 반경"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={1} max={10} addonAfter="km" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="maxRadiusKm"
                        label="최대 매칭 반경"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={10} max={100} addonAfter="km" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="cancelPenaltyThreshold"
                        label="취소 패널티 기준 (월)"
                        extra="월 N회 이상 취소 시 경고"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={1} max={10} addonAfter="회" />
                      </Form.Item>
                    </Col>
                  </Row>
                  <Button
                    type="primary"
                    htmlType="submit"
                    icon={<SaveOutlined />}
                    loading={updateMutation.isPending}
                  >
                    매칭 설정 저장
                  </Button>
                </Form>
              </Card>
            ),
          },
          {
            key: 'ranking',
            label: '랭킹 설정',
            children: (
              <Card style={{ borderRadius: 8 }}>
                <Form
                  form={rankingForm}
                  layout="vertical"
                  initialValues={settings?.rankingSettings}
                  onFinish={(values) => updateMutation.mutate({ rankingSettings: values })}
                >
                  <Row gutter={24}>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="minGamesForRanking"
                        label="핀 랭킹 최소 게임 수"
                        extra="랭킹 진입 조건"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={1} max={20} addonAfter="게임" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="nationalRankingMinGames"
                        label="전국 랭킹 최소 게임 수"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={5} max={50} addonAfter="게임" />
                      </Form.Item>
                    </Col>
                    <Col xs={24} sm={12} lg={8}>
                      <Form.Item
                        name="inactiveDaysThreshold"
                        label="비활성 랭킹 숨김 기간"
                        extra="N일 이상 비활성 시 랭킹 숨김"
                        rules={[{ required: true }]}
                      >
                        <InputNumber style={{ width: '100%' }} min={7} max={180} addonAfter="일" />
                      </Form.Item>
                    </Col>
                  </Row>
                  <Divider />
                  <Button
                    type="primary"
                    htmlType="submit"
                    icon={<SaveOutlined />}
                    loading={updateMutation.isPending}
                  >
                    랭킹 설정 저장
                  </Button>
                </Form>
              </Card>
            ),
          },
        ]}
      />
    </div>
  );
}
