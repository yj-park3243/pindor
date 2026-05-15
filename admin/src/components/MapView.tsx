import { Suspense, useState } from 'react';
import { Spin } from 'antd';
import { Container, NaverMap, Marker, InfoWindow, Listener, useNavermaps } from 'react-naver-maps';
import type { Pin } from '@/types/pin';
import { PIN_LEVEL_CONFIG } from '@/config/constants';

const PIN_COLORS: Record<string, string> = {
  DONG: '#1890ff',
  GU: '#52c41a',
  CITY: '#fa8c16',
  PROVINCE: '#722ed1',
};

function pinIconHtml(level: string, isActive: boolean, selected: boolean): string {
  const color = isActive ? PIN_COLORS[level] || '#1890ff' : '#d9d9d9';
  const size = selected ? 32 : 24;
  const shadow = selected
    ? `0 0 0 3px ${color}, 0 2px 6px rgba(0,0,0,0.4)`
    : '0 2px 4px rgba(0,0,0,0.3)';
  const border = selected ? '3px' : '2px';
  return `<div style="background:${color};width:${size}px;height:${size}px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);border:${border} solid #fff;box-shadow:${shadow};"></div>`;
}

function popupHtml(pin: Pin): string {
  const levelLabel = PIN_LEVEL_CONFIG[pin.level]?.label || pin.level;
  const statusColor = pin.isActive ? '#52c41a' : '#999';
  const statusLabel = pin.isActive ? '활성' : '비활성';
  return `
    <div style="min-width:140px;padding:8px 10px;font-size:13px;line-height:1.6;">
      <strong>${pin.name}</strong><br/>
      <span style="font-size:12px;color:#666;">레벨: ${levelLabel}</span><br/>
      <span style="font-size:12px;color:#666;">사용자 수: ${pin.userCount.toLocaleString()}명</span><br/>
      <span style="font-size:11px;color:${statusColor};">${statusLabel}</span>
    </div>
  `;
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

function MapFallback({ height }: { height: number | string }) {
  return (
    <div
      style={{
        height,
        width: '100%',
        borderRadius: 8,
        background: '#f5f5f5',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Spin />
    </div>
  );
}

export function MapView(props: MapViewProps) {
  return (
    <Suspense fallback={<MapFallback height={props.height ?? 500} />}>
      <MapViewContent {...props} />
    </Suspense>
  );
}

function MapViewContent({
  pins = [],
  center = [37.5665, 126.978],
  zoom = 10,
  height = 500,
  onPinClick,
  selectedPinId,
  editable = false,
  onPinDragEnd,
  onMapClick,
}: MapViewProps) {
  const navermaps = useNavermaps();
  const [openPinId, setOpenPinId] = useState<string | null>(null);

  const openedPin = openPinId ? pins.find((p) => p.id === openPinId) : null;

  return (
    <Container style={{ height, width: '100%', borderRadius: 8, overflow: 'hidden' }}>
      <NaverMap
        center={new navermaps.LatLng(center[0], center[1])}
        zoom={zoom}
      >
        {onMapClick && (
          <Listener
            type="click"
            listener={(e: naver.maps.PointerEvent) => onMapClick(e.coord.y, e.coord.x)}
          />
        )}

        {pins.map((pin) => {
          const isSelected = pin.id === selectedPinId;
          const size = isSelected ? 32 : 24;
          return (
            <Marker
              key={pin.id}
              position={new navermaps.LatLng(pin.center.lat, pin.center.lng)}
              icon={{
                content: pinIconHtml(pin.level, pin.isActive, isSelected),
                anchor: new navermaps.Point(size / 2, size),
              }}
              draggable={editable}
              onClick={() => {
                onPinClick?.(pin);
                setOpenPinId(pin.id);
              }}
              onDragend={
                editable
                  ? (e: naver.maps.PointerEvent) =>
                      onPinDragEnd?.(pin.id, e.coord.y, e.coord.x)
                  : undefined
              }
            />
          );
        })}

        {openedPin && (
          <InfoWindow
            position={new navermaps.LatLng(openedPin.center.lat, openedPin.center.lng)}
            content={popupHtml(openedPin)}
            pixelOffset={new navermaps.Point(0, -10)}
          />
        )}
      </NaverMap>
    </Container>
  );
}
