import { useState } from 'react';
import { Modal, Image, Row, Col, Typography, Empty } from 'antd';
import { ZoomInOutlined } from '@ant-design/icons';

const { Text } = Typography;

interface PhotoGroup {
  label: string;
  urls: string[];
}

interface PhotoViewerProps {
  groups?: PhotoGroup[];
  urls?: string[];
  title?: string;
  compareMode?: boolean;
}

export function PhotoViewer({ groups, urls, title, compareMode = false }: PhotoViewerProps) {
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);

  if (compareMode && groups) {
    return (
      <>
        <Row gutter={16}>
          {groups.map((group, gi) => (
            <Col key={gi} span={Math.floor(24 / groups.length)}>
              <Text type="secondary" style={{ display: 'block', marginBottom: 8 }}>
                {group.label}
              </Text>
              {group.urls.length === 0 ? (
                <Empty description="사진 없음" imageStyle={{ height: 60 }} />
              ) : (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {group.urls.map((url, i) => (
                    <div
                      key={i}
                      style={{
                        width: 120,
                        height: 120,
                        overflow: 'hidden',
                        borderRadius: 8,
                        cursor: 'pointer',
                        position: 'relative',
                        border: '1px solid #f0f0f0',
                      }}
                      onClick={() => setPreviewUrl(url)}
                    >
                      <img
                        src={url}
                        alt={`증빙 ${i + 1}`}
                        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      />
                      <div
                        style={{
                          position: 'absolute',
                          inset: 0,
                          background: 'rgba(0,0,0,0.3)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          opacity: 0,
                          transition: 'opacity 0.2s',
                        }}
                        onMouseEnter={(e) =>
                          ((e.currentTarget as HTMLDivElement).style.opacity = '1')
                        }
                        onMouseLeave={(e) =>
                          ((e.currentTarget as HTMLDivElement).style.opacity = '0')
                        }
                      >
                        <ZoomInOutlined style={{ color: '#fff', fontSize: 20 }} />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Col>
          ))}
        </Row>

        <Modal
          open={!!previewUrl}
          footer={null}
          onCancel={() => setPreviewUrl(null)}
          width={800}
          centered
          title={title || '사진 보기'}
        >
          {previewUrl && (
            <img src={previewUrl} alt="증빙 사진" style={{ width: '100%', borderRadius: 8 }} />
          )}
        </Modal>
      </>
    );
  }

  // 단순 모드
  return (
    <Image.PreviewGroup>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {(urls || []).map((url, i) => (
          <Image
            key={i}
            src={url}
            width={120}
            height={120}
            style={{ objectFit: 'cover', borderRadius: 8 }}
            alt={`사진 ${i + 1}`}
          />
        ))}
        {(!urls || urls.length === 0) && <Empty description="사진 없음" />}
      </div>
    </Image.PreviewGroup>
  );
}
