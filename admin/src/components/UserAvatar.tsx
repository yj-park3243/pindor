import { Avatar } from 'antd';
import { UserOutlined } from '@ant-design/icons';
import type { Tier } from '@/types/user';
import { TIER_CONFIG } from '@/config/constants';

interface UserAvatarProps {
  src?: string | null;
  nickname?: string;
  tier?: Tier;
  size?: number | 'small' | 'default' | 'large';
  showTier?: boolean;
}

export function UserAvatar({
  src,
  nickname,
  tier,
  size = 'default',
  showTier = false,
}: UserAvatarProps) {
  const tierConfig = tier ? TIER_CONFIG[tier] : null;
  const borderStyle = tierConfig
    ? { border: `2px solid ${tierConfig.color}` }
    : {};

  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
      <Avatar
        src={src || undefined}
        icon={!src ? <UserOutlined /> : undefined}
        alt={nickname}
        size={size}
        style={borderStyle}
      />
      {nickname && <span>{nickname}</span>}
      {showTier && tierConfig && (
        <span
          style={{
            fontSize: 11,
            fontWeight: 600,
            color: tierConfig.color,
            background: `${tierConfig.color}22`,
            padding: '1px 6px',
            borderRadius: 10,
            border: `1px solid ${tierConfig.color}`,
          }}
        >
          {tierConfig.label}
        </span>
      )}
    </span>
  );
}
