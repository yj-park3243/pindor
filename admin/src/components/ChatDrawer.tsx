import { Drawer, Typography, Avatar, Image, Spin, Empty, Tag } from 'antd';
import { UserOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import { useChatMessages } from '@/hooks/useMatches';
import type { ChatMessage } from '@/api/matches.api';

const { Text } = Typography;

interface ChatDrawerProps {
  matchId: string | null;
  title?: string;
  onClose: () => void;
}

const MESSAGE_TYPE_LABEL: Record<string, { label: string; color: string }> = {
  TEXT: { label: '텍스트', color: 'default' },
  IMAGE: { label: '이미지', color: 'blue' },
  SYSTEM: { label: '시스템', color: 'orange' },
  LOCATION: { label: '위치', color: 'green' },
  VERIFICATION_CODE: { label: '인증번호', color: 'purple' },
  SCHEDULE_PROPOSAL: { label: '일정 제안', color: 'cyan' },
};

function MessageBubble({ msg }: { msg: ChatMessage }) {
  const isSystem = msg.messageType === 'SYSTEM';

  if (isSystem) {
    return (
      <div style={{ textAlign: 'center', margin: '8px 0' }}>
        <Tag color="default" style={{ fontSize: 11 }}>
          {msg.content}
        </Tag>
      </div>
    );
  }

  const typeInfo = MESSAGE_TYPE_LABEL[msg.messageType] ?? { label: msg.messageType, color: 'default' };

  return (
    <div style={{ display: 'flex', gap: 8, margin: '6px 0', alignItems: 'flex-start' }}>
      <Avatar
        size={28}
        src={msg.senderProfileImageUrl}
        icon={!msg.senderProfileImageUrl ? <UserOutlined /> : undefined}
        style={{ flexShrink: 0, marginTop: 2 }}
      />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
          <Text strong style={{ fontSize: 12 }}>{msg.senderNickname || '알 수 없음'}</Text>
          {msg.messageType !== 'TEXT' && (
            <Tag color={typeInfo.color} style={{ fontSize: 10, lineHeight: '16px', margin: 0 }}>
              {typeInfo.label}
            </Tag>
          )}
          <Text type="secondary" style={{ fontSize: 10 }}>
            {dayjs(msg.createdAt).format('MM/DD HH:mm')}
          </Text>
        </div>
        <div
          style={{
            background: '#f5f5f5',
            borderRadius: '4px 12px 12px 12px',
            padding: '6px 10px',
            display: 'inline-block',
            maxWidth: '100%',
            wordBreak: 'break-word',
          }}
        >
          {msg.messageType === 'IMAGE' && msg.imageUrl ? (
            <Image src={msg.imageUrl} width={180} style={{ borderRadius: 6 }} />
          ) : msg.messageType === 'LOCATION' && msg.extraData ? (
            <Text style={{ fontSize: 13 }}>
              {(msg.extraData as Record<string, string>).placeName ??
                (msg.extraData as Record<string, string>).address ??
                '위치 공유'}
            </Text>
          ) : (
            <Text style={{ fontSize: 13, whiteSpace: 'pre-wrap' }}>{msg.content || '-'}</Text>
          )}
        </div>
      </div>
    </div>
  );
}

export function ChatDrawer({ matchId, title, onClose }: ChatDrawerProps) {
  const { data: messages, isLoading } = useChatMessages(matchId);

  return (
    <Drawer
      open={!!matchId}
      onClose={onClose}
      title={title ?? '채팅 내역'}
      width={420}
      styles={{ body: { padding: '12px 16px' } }}
    >
      {isLoading ? (
        <div style={{ textAlign: 'center', padding: 40 }}>
          <Spin />
        </div>
      ) : !messages || messages.length === 0 ? (
        <Empty description="메시지가 없습니다" />
      ) : (
        <>
          <Text type="secondary" style={{ fontSize: 11, display: 'block', marginBottom: 12 }}>
            총 {messages.length}개 메시지
          </Text>
          {messages.map((msg) => (
            <MessageBubble key={msg.id} msg={msg} />
          ))}
        </>
      )}
    </Drawer>
  );
}
