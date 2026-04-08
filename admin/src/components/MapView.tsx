import { useEffect, useRef } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import type { Pin } from '@/types/pin';
import { PIN_LEVEL_CONFIG } from '@/config/constants';

// Leaflet 기본 아이콘 문제 수정
delete (L.Icon.Default.prototype as { _getIconUrl?: unknown })._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

// 핀 레벨별 아이콘 색상
const PIN_COLORS: Record<string, string> = {
  DONG: '#1890ff',
  GU: '#52c41a',
  CITY: '#fa8c16',
  PROVINCE: '#722ed1',
};

function createPinIcon(level: string, isActive: boolean, selected = false) {
  const color = isActive ? (PIN_COLORS[level] || '#1890ff') : '#d9d9d9';
  const size = selected ? 32 : 24;
  return L.divIcon({
    className: '',
    html: `
      <div style="
        background: ${color};
        width: ${size}px;
        height: ${size}px;
        border-radius: 50% 50% 50% 0;
        transform: rotate(-45deg);
        border: ${selected ? '3px' : '2px'} solid #fff;
        box-shadow: ${selected ? '0 0 0 3px ' + color + ', 0 2px 6px rgba(0,0,0,0.4)' : '0 2px 4px rgba(0,0,0,0.3)'};
      "></div>
    `,
    iconSize: [size, size],
    iconAnchor: [size / 2, size],
  });
}

interface MapViewProps {
  pins?: Pin[];
  center?: [number, number];
  zoom?: number;
  height?: number | string;
  onPinClick?: (pin: Pin) => void;
  selectedPinId?: string;
  editable?: boolean;
  onPinDragEnd?: (pinId: string, lat: number, lng: number) => void;
  onMapClick?: (lat: number, lng: number) => void;
}

// 지도 중심 이동 컴포넌트
function MapController({ center, zoom }: { center?: [number, number]; zoom?: number }) {
  const map = useMap();
  const prevCenter = useRef<[number, number] | undefined>(undefined);

  useEffect(() => {
    if (center && center !== prevCenter.current) {
      map.setView(center, zoom || map.getZoom());
      prevCenter.current = center;
    }
  }, [center, zoom, map]);

  return null;
}

// 지도 클릭 이벤트 핸들러
function ClickHandler({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

export function MapView({
  pins = [],
  center = [37.5665, 126.978], // 서울 기본값
  zoom = 10,
  height = 500,
  onPinClick,
  selectedPinId,
  editable = false,
  onPinDragEnd,
  onMapClick,
}: MapViewProps) {
  return (
    <MapContainer
      center={center}
      zoom={zoom}
      style={{ height, width: '100%', borderRadius: 8 }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <MapController center={center} zoom={zoom} />

      {onMapClick && <ClickHandler onMapClick={onMapClick} />}

      {pins.map((pin) => {
        const isSelected = pin.id === selectedPinId;
        return (
          <Marker
            key={pin.id}
            position={[pin.center.lat, pin.center.lng]}
            icon={createPinIcon(pin.level, pin.isActive, isSelected)}
            draggable={editable}
            eventHandlers={{
              click: () => onPinClick?.(pin),
              dragend: editable
                ? (e) => {
                    const { lat, lng } = (e.target as L.Marker).getLatLng();
                    onPinDragEnd?.(pin.id, lat, lng);
                  }
                : undefined,
            }}
          >
            <Popup>
              <div style={{ minWidth: 140 }}>
                <strong>{pin.name}</strong>
                <br />
                <span style={{ fontSize: 12, color: '#666' }}>
                  레벨: {PIN_LEVEL_CONFIG[pin.level]?.label || pin.level}
                </span>
                <br />
                <span style={{ fontSize: 12, color: '#666' }}>
                  사용자 수: {pin.userCount.toLocaleString()}명
                </span>
                <br />
                <span
                  style={{
                    fontSize: 11,
                    color: pin.isActive ? '#52c41a' : '#999',
                  }}
                >
                  {pin.isActive ? '활성' : '비활성'}
                </span>
              </div>
            </Popup>
          </Marker>
        );
      })}
    </MapContainer>
  );
}
