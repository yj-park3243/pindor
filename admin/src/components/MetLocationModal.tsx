import { Component, Suspense, useEffect, useState, type ErrorInfo, type ReactNode } from 'react';
import { Modal, Empty, Tag, Space, Typography, Alert } from 'antd';
import { Container, NaverMap, Marker, InfoWindow, useNavermaps } from 'react-naver-maps';
import dayjs from 'dayjs';
import type { Match } from '@/types/match';

const { Text } = Typography;

interface MetLocationModalProps {
  open: boolean;
  match: Match | null;
  onClose: () => void;
}

interface MetPoint {
  side: 'requester' | 'opponent';
  nickname: string;
  lat: number;
  lng: number;
  confirmedAt: string;
}

declare global {
  interface Window {
    navermap_authFailure?: () => void;
  }
}

function buildPoints(match: Match): MetPoint[] {
  const points: MetPoint[] = [];
  if (
    match.requesterMetLatitude != null &&
    match.requesterMetLongitude != null &&
    match.requesterMetConfirmedAt
  ) {
    points.push({
      side: 'requester',
      nickname: match.requesterProfile?.user?.nickname || '요청자',
      lat: match.requesterMetLatitude,
      lng: match.requesterMetLongitude,
      confirmedAt: match.requesterMetConfirmedAt,
    });
  }
  if (
    match.opponentMetLatitude != null &&
    match.opponentMetLongitude != null &&
    match.opponentMetConfirmedAt
  ) {
    points.push({
      side: 'opponent',
      nickname: match.opponentProfile?.user?.nickname || '상대방',
      lat: match.opponentMetLatitude,
      lng: match.opponentMetLongitude,
      confirmedAt: match.opponentMetConfirmedAt,
    });
  }
  return points;
}

const SIDE_COLOR: Record<MetPoint['side'], string> = {
  requester: '#1890ff',
  opponent: '#fa8c16',
};

const SIDE_LABEL: Record<MetPoint['side'], string> = {
  requester: '요청자',
  opponent: '상대방',
};

function markerHtml(side: MetPoint['side']): string {
  const color = SIDE_COLOR[side];
  return `<div style="background:${color};width:28px;height:28px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);border:3px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,0.4);display:flex;align-items:center;justify-content:center;">
    <span style="transform:rotate(45deg);color:#fff;font-size:12px;font-weight:700;">${side === 'requester' ? 'R' : 'O'}</span>
  </div>`;
}

function infoHtml(p: MetPoint): string {
  const sideColor = SIDE_COLOR[p.side];
  return `<div style="padding:10px 12px;font-size:13px;line-height:1.6;min-width:160px;">
    <div style="margin-bottom:4px;"><span style="display:inline-block;padding:2px 8px;background:${sideColor};color:#fff;border-radius:4px;font-size:11px;font-weight:600;">${SIDE_LABEL[p.side]}</span></div>
    <strong>${p.nickname}</strong><br/>
    <span style="font-size:12px;color:#666;">${dayjs(p.confirmedAt).format('YYYY-MM-DD HH:mm')}</span><br/>
    <span style="font-size:11px;color:#999;font-family:monospace;">${p.lat.toFixed(6)}, ${p.lng.toFixed(6)}</span>
  </div>`;
}

/// Naver 지도 unmount 시 내부 throw가 root까지 올라가 흰 화면 되는 것을 차단
class MapErrorBoundary extends Component<{ children: ReactNode; fallback: ReactNode }, { hasError: boolean }> {
  state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.warn('[MetLocationModal] map crash isolated:', error, info);
  }

  render() {
    if (this.state.hasError) return this.props.fallback;
    return this.props.children;
  }
}

export function MetLocationModal({ open, match, onClose }: MetLocationModalProps) {
  return (
    <Suspense fallback={null}>
      <MetLocationModalContent open={open} match={match} onClose={onClose} />
    </Suspense>
  );
}

function MetLocationModalContent({ open, match, onClose }: MetLocationModalProps) {
  const navermaps = useNavermaps();
  const [openSide, setOpenSide] = useState<MetPoint['side'] | null>(null);
  const [authFailed, setAuthFailed] = useState(false);

  useEffect(() => {
    const prev = window.navermap_authFailure;
    window.navermap_authFailure = () => setAuthFailed(true);
    return () => {
      window.navermap_authFailure = prev;
    };
  }, []);

  const points = match ? buildPoints(match) : [];

  // 지도 중심 — 두 점 평균, 하나면 그 점, 없으면 서울
  const center: [number, number] =
    points.length === 2
      ? [(points[0].lat + points[1].lat) / 2, (points[0].lng + points[1].lng) / 2]
      : points.length === 1
        ? [points[0].lat, points[0].lng]
        : [37.5665, 126.978];

  const openedPoint = openSide ? points.find((p) => p.side === openSide) : null;

  const fallback = (
    <Alert
      type="error"
      showIcon
      message="네이버 지도를 불러오지 못했습니다"
      description={
        <div>
          <div>현재 도메인이 Naver Cloud 콘솔에 등록되어 있지 않을 수 있습니다.</div>
          <div style={{ marginTop: 6, fontSize: 12, color: '#666' }}>
            좌표 — {points.map((p) => `${SIDE_LABEL[p.side]} ${p.lat.toFixed(6)}, ${p.lng.toFixed(6)}`).join(' / ')}
          </div>
        </div>
      }
      style={{ height: 480, display: 'flex', alignItems: 'center' }}
    />
  );

  return (
    <Modal
      open={open}
      title="만남 확인 위치"
      onCancel={() => {
        setOpenSide(null);
        onClose();
      }}
      footer={null}
      width={720}
      destroyOnHidden
    >
      {points.length === 0 ? (
        <Empty description="아직 양쪽 모두 '우리 만났어요'를 누르지 않았습니다." />
      ) : (
        <>
          <Space size={12} style={{ marginBottom: 12 }}>
            {points.map((p) => (
              <Tag key={p.side} color={SIDE_COLOR[p.side]} style={{ fontSize: 13, padding: '2px 10px' }}>
                {SIDE_LABEL[p.side]}: {p.nickname}
              </Tag>
            ))}
            <Text type="secondary" style={{ fontSize: 12 }}>
              마커 클릭 시 상세 정보
            </Text>
          </Space>
          {authFailed ? (
            fallback
          ) : (
            <MapErrorBoundary fallback={fallback}>
              <Container style={{ height: 480, width: '100%', borderRadius: 8, overflow: 'hidden' }}>
                <NaverMap
                  center={new navermaps.LatLng(center[0], center[1])}
                  zoom={points.length > 1 ? 13 : 15}
                >
                  {points.map((p) => (
                    <Marker
                      key={p.side}
                      position={new navermaps.LatLng(p.lat, p.lng)}
                      icon={{
                        content: markerHtml(p.side),
                        anchor: new navermaps.Point(14, 28),
                      }}
                      onClick={() => setOpenSide(p.side)}
                    />
                  ))}
                  {openedPoint && (
                    <InfoWindow
                      position={new navermaps.LatLng(openedPoint.lat, openedPoint.lng)}
                      content={infoHtml(openedPoint)}
                      pixelOffset={new navermaps.Point(0, -10)}
                    />
                  )}
                </NaverMap>
              </Container>
            </MapErrorBoundary>
          )}
        </>
      )}
    </Modal>
  );
}
