import { useState } from 'react';
import {
  Typography,
  Card,
  Row,
  Col,
  Button,
  Tag,
  Space,
  Table,
  Input,
  Select,
  Tooltip,
  Switch,
  Statistic,
  Modal,
} from 'antd';
import type { TableColumnsType } from 'antd';
import { SearchOutlined, EditOutlined, PlusOutlined, StopOutlined } from '@ant-design/icons';
import { usePinList, useTogglePinActive, useUpdatePin } from '@/hooks/usePins';
import { MapView } from '@/components/MapView';
import { PinFormModal } from './PinFormModal';
import { PIN_LEVEL_CONFIG } from '@/config/constants';
import type { Pin, PinLevel } from '@/types/pin';

const { Title, Text } = Typography;

export function PinListPage() {
  const [search, setSearch] = useState('');
  const [level, setLevel] = useState<PinLevel | undefined>();
  const [isActive, setIsActiveFilter] = useState<boolean | undefined>();
  const [page, setPage] = useState(1);
  const [selectedPin, setSelectedPin] = useState<Pin | null>(null);
  const [formModalOpen, setFormModalOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<Pin | null>(null);
  const [viewMode, setViewMode] = useState<'table' | 'map'>('table');
  const [initialCoords, setInitialCoords] = useState<{ lat: number; lng: number } | undefined>();

  const { data, isLoading } = usePinList({
    search: search || undefined,
    level,
    isActive,
    page,
    pageSize: 20,
  });

  const toggleActiveMutation = useTogglePinActive();
  const updatePinMutation = useUpdatePin();

  // 지도에서 마커 드래그 완료 시 위치 업데이트
  const handlePinDragEnd = (pinId: string, lat: number, lng: number) => {
    const pin = data?.items.find((p) => p.id === pinId);
    if (!pin) return;

    Modal.confirm({
      title: '핀 위치 변경',
      content: `"${pin.name}"의 위치를 변경하시겠습니까?`,
      okText: '변경',
      cancelText: '취소',
      onOk: () => {
        updatePinMutation.mutate({
          id: pinId,
          data: { center: { lat, lng } },
        });
        // selectedPin 업데이트
        if (selectedPin?.id === pinId) {
          setSelectedPin({ ...selectedPin, center: { lat, lng } });
        }
      },
    });
  };

  // 지도 빈 영역 클릭 시 핀 생성 모달 열기
  const handleMapClick = (lat: number, lng: number) => {
    setEditTarget(null);
    setInitialCoords({ lat, lng });
    setFormModalOpen(true);
  };

  // 선택된 핀 비활성화(활성 토글)
  const handleToggleSelectedPin = () => {
    if (!selectedPin) return;
    toggleActiveMutation.mutate(
      { id: selectedPin.id, isActive: selectedPin.isActive },
      {
        onSuccess: () => {
          setSelectedPin((prev) =>
            prev ? { ...prev, isActive: !prev.isActive } : null
          );
        },
      }
    );
  };

  const columns: TableColumnsType<Pin> = [
    {
      title: '핀 이름',
      dataIndex: 'name',
      key: 'name',
      render: (name: string, record: Pin) => (
        <Button
          type="link"
          style={{ padding: 0, fontWeight: selectedPin?.id === record.id ? 700 : 400 }}
          onClick={() => setSelectedPin(record)}
        >
          {name}
        </Button>
      ),
    },
    {
      title: '레벨',
      dataIndex: 'level',
      key: 'level',
      render: (l: PinLevel) => (
        <Tag color={
          l === 'DONG' ? 'blue' :
          l === 'GU' ? 'green' :
          l === 'CITY' ? 'orange' : 'purple'
        }>
          {PIN_LEVEL_CONFIG[l]?.label || l}
        </Tag>
      ),
      width: 80,
      filters: Object.entries(PIN_LEVEL_CONFIG).map(([value, { label }]) => ({
        text: label, value,
      })),
    },
    {
      title: '중심 좌표',
      key: 'center',
      render: (_, record: Pin) => (
        <Text style={{ fontSize: 12 }}>
          {record.center.lat.toFixed(4)}, {record.center.lng.toFixed(4)}
        </Text>
      ),
      width: 160,
    },
    {
      title: '사용자 수',
      dataIndex: 'userCount',
      key: 'userCount',
      render: (v: number) => v.toLocaleString(),
      sorter: true,
      width: 100,
    },
    {
      title: '활성 임계값',
      key: 'threshold',
      render: (_, record: Pin) => {
        const threshold = PIN_LEVEL_CONFIG[record.level]?.activationThreshold || 0;
        const ratio = Math.min(record.userCount / threshold, 1);
        return (
          <Tooltip title={`${record.userCount}/${threshold}명`}>
            <div style={{
              width: 80,
              height: 6,
              background: '#f0f0f0',
              borderRadius: 3,
              overflow: 'hidden',
            }}>
              <div style={{
                width: `${ratio * 100}%`,
                height: '100%',
                background: ratio >= 1 ? '#52c41a' : '#fa8c16',
                borderRadius: 3,
              }} />
            </div>
          </Tooltip>
        );
      },
      width: 100,
    },
    {
      title: '활성',
      dataIndex: 'isActive',
      key: 'isActive',
      render: (isActive: boolean, record: Pin) => (
        <Switch
          checked={isActive}
          size="small"
          loading={toggleActiveMutation.isPending}
          onChange={() => toggleActiveMutation.mutate({ id: record.id, isActive })}
        />
      ),
      width: 70,
    },
    {
      title: '액션',
      key: 'actions',
      render: (_, record: Pin) => (
        <Tooltip title="수정">
          <Button
            type="text"
            icon={<EditOutlined />}
            onClick={() => {
              setEditTarget(record);
              setInitialCoords(undefined);
              setFormModalOpen(true);
            }}
          />
        </Tooltip>
      ),
      width: 70,
    },
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
        <Title level={4} style={{ margin: 0 }}>
          핀 관리
        </Title>
        <Button
          type="primary"
          icon={<PlusOutlined />}
          onClick={() => {
            setEditTarget(null);
            setInitialCoords(undefined);
            setFormModalOpen(true);
          }}
        >
          핀 생성
        </Button>
      </div>
      <Text type="secondary" style={{ display: 'block', marginBottom: 20 }}>
        지역 핀 목록 조회 및 지도 뷰
      </Text>

      {/* 필터 */}
      <Card style={{ marginBottom: 16, borderRadius: 8 }}>
        <Row gutter={[12, 12]} align="middle">
          <Col xs={24} sm={12} lg={8}>
            <Input
              placeholder="핀 이름으로 검색"
              prefix={<SearchOutlined />}
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              allowClear
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="레벨"
              style={{ width: '100%' }}
              allowClear
              value={level}
              onChange={(v) => { setLevel(v); setPage(1); }}
              options={Object.entries(PIN_LEVEL_CONFIG).map(([value, { label }]) => ({
                value, label,
              }))}
            />
          </Col>
          <Col xs={12} sm={6} lg={4}>
            <Select
              placeholder="활성 상태"
              style={{ width: '100%' }}
              allowClear
              value={isActive}
              onChange={(v) => { setIsActiveFilter(v); setPage(1); }}
              options={[
                { value: true, label: '활성' },
                { value: false, label: '비활성' },
              ]}
            />
          </Col>
          <Col>
            <Space>
              <Button
                type={viewMode === 'table' ? 'primary' : 'default'}
                onClick={() => setViewMode('table')}
              >
                목록
              </Button>
              <Button
                type={viewMode === 'map' ? 'primary' : 'default'}
                onClick={() => setViewMode('map')}
              >
                지도
              </Button>
            </Space>
          </Col>
        </Row>
      </Card>

      {viewMode === 'map' ? (
        <Row gutter={[16, 16]}>
          <Col xs={24} lg={16}>
            <Card
              style={{ borderRadius: 8 }}
              bodyStyle={{ padding: 0, overflow: 'hidden', borderRadius: 8 }}
            >
              <MapView
                pins={data?.items || []}
                height={560}
                onPinClick={setSelectedPin}
                selectedPinId={selectedPin?.id}
                editable
                onPinDragEnd={handlePinDragEnd}
                onMapClick={handleMapClick}
              />
              <div style={{ padding: '8px 12px', background: '#fafafa', borderTop: '1px solid #f0f0f0', fontSize: 12, color: '#8c8c8c' }}>
                빈 영역 클릭 — 새 핀 생성 &nbsp;|&nbsp; 마커 드래그 — 위치 변경
              </div>
            </Card>
          </Col>
          <Col xs={24} lg={8}>
            {selectedPin ? (
              <Card
                title={selectedPin.name}
                style={{ borderRadius: 8 }}
                extra={
                  <Space>
                    <Button
                      size="small"
                      icon={<EditOutlined />}
                      onClick={() => {
                        setEditTarget(selectedPin);
                        setInitialCoords(undefined);
                        setFormModalOpen(true);
                      }}
                    >
                      수정
                    </Button>
                    <Button
                      size="small"
                      danger={selectedPin.isActive}
                      icon={<StopOutlined />}
                      loading={toggleActiveMutation.isPending}
                      onClick={handleToggleSelectedPin}
                    >
                      {selectedPin.isActive ? '비활성화' : '활성화'}
                    </Button>
                  </Space>
                }
              >
                <Row gutter={16}>
                  <Col span={12}>
                    <Statistic title="사용자 수" value={selectedPin.userCount} suffix="명" />
                  </Col>
                  <Col span={12}>
                    <Statistic
                      title="레벨"
                      value={PIN_LEVEL_CONFIG[selectedPin.level]?.label || selectedPin.level}
                    />
                  </Col>
                </Row>
                <div style={{ marginTop: 16 }}>
                  <Tag color={selectedPin.isActive ? 'green' : 'default'}>
                    {selectedPin.isActive ? '활성' : '비활성'}
                  </Tag>
                  <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                    좌표: {selectedPin.center.lat.toFixed(4)}, {selectedPin.center.lng.toFixed(4)}
                  </Text>
                </div>
              </Card>
            ) : (
              <Card style={{ borderRadius: 8, textAlign: 'center', padding: 40 }}>
                <Text type="secondary">핀을 클릭하면 상세 정보가 표시됩니다.</Text>
                <br />
                <Text type="secondary" style={{ fontSize: 12 }}>
                  지도 빈 영역을 클릭하면 새 핀을 생성할 수 있습니다.
                </Text>
              </Card>
            )}
          </Col>
        </Row>
      ) : (
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
              showTotal: (total) => `총 ${total.toLocaleString()}개`,
              onChange: setPage,
            }}
            onRow={(record) => ({
              onClick: () => setSelectedPin(record),
              style: { cursor: 'pointer', background: selectedPin?.id === record.id ? '#e6f4ff' : undefined },
            })}
            scroll={{ x: 800 }}
          />
        </Card>
      )}

      <PinFormModal
        open={formModalOpen}
        pin={editTarget}
        initialCoords={initialCoords}
        onClose={() => {
          setFormModalOpen(false);
          setEditTarget(null);
          setInitialCoords(undefined);
        }}
      />
    </div>
  );
}
