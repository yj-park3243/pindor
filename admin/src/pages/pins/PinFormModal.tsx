import { useEffect, useRef } from 'react';
import {
  Modal,
  Form,
  Input,
  Select,
  InputNumber,
  Row,
  Col,
  Switch,
} from 'antd';
import { MapContainer, TileLayer, Marker, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import { useCreatePin, useUpdatePin } from '@/hooks/usePins';
import { PIN_LEVEL_CONFIG } from '@/config/constants';
import type { Pin } from '@/types/pin';

interface PinFormModalProps {
  open: boolean;
  pin: Pin | null;
  onClose: () => void;
  initialCoords?: { lat: number; lng: number };
}

interface PinFormValues {
  name: string;
  level: string;
  lat: number;
  lng: number;
  isActive: boolean;
}

// 지도 클릭 핸들러
function ClickHandler({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

// 지도 중심 이동 컴포넌트 (모달 열릴 때 center 동기화)
function MapCenterSync({ center }: { center: [number, number] }) {
  const map = useMap();
  const prevCenter = useRef<[number, number]>([0, 0]);

  useEffect(() => {
    const [prevLat, prevLng] = prevCenter.current;
    const [lat, lng] = center;
    if (prevLat !== lat || prevLng !== lng) {
      map.setView(center, map.getZoom());
      prevCenter.current = center;
    }
  }, [center, map]);

  return null;
}

// 드래그 가능한 마커
function DraggableMarker({
  position,
  onDragEnd,
}: {
  position: [number, number];
  onDragEnd: (lat: number, lng: number) => void;
}) {
  return (
    <Marker
      position={position}
      draggable
      eventHandlers={{
        dragend(e) {
          const { lat, lng } = (e.target as L.Marker).getLatLng();
          onDragEnd(lat, lng);
        },
      }}
    />
  );
}

const SEOUL_CENTER: [number, number] = [37.5665, 126.978];

export function PinFormModal({ open, pin, onClose, initialCoords }: PinFormModalProps) {
  const [form] = Form.useForm<PinFormValues>();
  const isEdit = !!pin;

  const createMutation = useCreatePin();
  const updateMutation = useUpdatePin();

  const isPending = createMutation.isPending || updateMutation.isPending;

  // 폼 필드에서 현재 lat/lng 읽기 (지도 마커 위치용)
  const latValue = Form.useWatch('lat', form);
  const lngValue = Form.useWatch('lng', form);

  const hasCoords =
    typeof latValue === 'number' &&
    typeof lngValue === 'number' &&
    !isNaN(latValue) &&
    !isNaN(lngValue);

  const markerPosition: [number, number] | null = hasCoords ? [latValue, lngValue] : null;

  const mapCenter: [number, number] = markerPosition ?? SEOUL_CENTER;

  useEffect(() => {
    if (open) {
      if (pin) {
        form.setFieldsValue({
          name: pin.name,
          level: pin.level,
          lat: pin.center.lat,
          lng: pin.center.lng,
          isActive: pin.isActive,
        });
      } else if (initialCoords) {
        form.resetFields();
        form.setFieldsValue({
          lat: initialCoords.lat,
          lng: initialCoords.lng,
          isActive: true,
        });
      } else {
        form.resetFields();
      }
    }
  }, [open, pin, initialCoords, form]);

  const handleMapClick = (lat: number, lng: number) => {
    form.setFieldsValue({ lat: parseFloat(lat.toFixed(6)), lng: parseFloat(lng.toFixed(6)) });
  };

  const handleDragEnd = (lat: number, lng: number) => {
    form.setFieldsValue({ lat: parseFloat(lat.toFixed(6)), lng: parseFloat(lng.toFixed(6)) });
  };

  const handleSubmit = async (values: PinFormValues) => {
    const payload = {
      name: values.name,
      level: values.level,
      center: { lat: values.lat, lng: values.lng },
    };

    if (isEdit) {
      await updateMutation.mutateAsync({
        id: pin!.id,
        data: { ...payload, isActive: values.isActive },
      });
    } else {
      await createMutation.mutateAsync(payload);
    }
    onClose();
  };

  return (
    <Modal
      open={open}
      title={isEdit ? `핀 수정 — ${pin?.name}` : '핀 생성'}
      onOk={() => form.submit()}
      onCancel={onClose}
      okText={isEdit ? '수정' : '생성'}
      cancelText="취소"
      confirmLoading={isPending}
      destroyOnHide
      width={600}
    >
      <Form
        form={form}
        layout="vertical"
        onFinish={handleSubmit}
        initialValues={{ isActive: true }}
      >
        <Form.Item
          name="name"
          label="핀 이름"
          rules={[{ required: true, message: '핀 이름을 입력해주세요.' }]}
        >
          <Input placeholder="예: 강남구 역삼동" />
        </Form.Item>

        <Form.Item
          name="level"
          label="레벨"
          rules={[{ required: true, message: '레벨을 선택해주세요.' }]}
        >
          <Select placeholder="레벨 선택">
            {Object.entries(PIN_LEVEL_CONFIG).map(([value, { label, activationThreshold }]) => (
              <Select.Option key={value} value={value}>
                {label} (활성화 임계값: {activationThreshold}명)
              </Select.Option>
            ))}
          </Select>
        </Form.Item>

        <Row gutter={12}>
          <Col span={12}>
            <Form.Item
              name="lat"
              label="위도 (Latitude)"
              rules={[
                { required: true, message: '위도를 입력해주세요.' },
                {
                  type: 'number',
                  min: 33,
                  max: 39,
                  message: '유효한 한국 위도를 입력하세요 (33~39)',
                },
              ]}
            >
              <InputNumber
                style={{ width: '100%' }}
                precision={6}
                placeholder="37.504049"
                onChange={(val) => {
                  if (typeof val === 'number') {
                    form.setFieldsValue({ lat: val });
                  }
                }}
              />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item
              name="lng"
              label="경도 (Longitude)"
              rules={[
                { required: true, message: '경도를 입력해주세요.' },
                {
                  type: 'number',
                  min: 124,
                  max: 132,
                  message: '유효한 한국 경도를 입력하세요 (124~132)',
                },
              ]}
            >
              <InputNumber
                style={{ width: '100%' }}
                precision={6}
                placeholder="127.024612"
                onChange={(val) => {
                  if (typeof val === 'number') {
                    form.setFieldsValue({ lng: val });
                  }
                }}
              />
            </Form.Item>
          </Col>
        </Row>

        {isEdit && (
          <Form.Item
            name="isActive"
            label="활성 상태"
            valuePropName="checked"
          >
            <Switch checkedChildren="활성" unCheckedChildren="비활성" />
          </Form.Item>
        )}

        {/* 지도 — 클릭 또는 드래그로 좌표 입력 */}
        <Form.Item label="지도에서 위치 선택" style={{ marginBottom: 0 }}>
          <div style={{ height: 300, borderRadius: 8, overflow: 'hidden', border: '1px solid #d9d9d9' }}>
            {open && (
              <MapContainer
                center={mapCenter}
                zoom={13}
                style={{ height: '100%', width: '100%' }}
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                <MapCenterSync center={mapCenter} />
                <ClickHandler onMapClick={handleMapClick} />
                {markerPosition && (
                  <DraggableMarker
                    position={markerPosition}
                    onDragEnd={handleDragEnd}
                  />
                )}
              </MapContainer>
            )}
          </div>
          <div style={{ marginTop: 4, fontSize: 12, color: '#8c8c8c' }}>
            지도를 클릭하거나 마커를 드래그하면 좌표가 자동 입력됩니다.
          </div>
        </Form.Item>
      </Form>
    </Modal>
  );
}
