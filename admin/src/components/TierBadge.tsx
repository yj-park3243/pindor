import { Tag } from 'antd';
import type { Tier } from '@/types/user';
import { TIER_CONFIG } from '@/config/constants';

interface TierBadgeProps {
  tier: Tier;
  showScore?: boolean;
  score?: number;
}

// 밝은 배경 티어 — 텍스트를 어둡게 표시
const LIGHT_BG_TIERS: Tier[] = ['PLATINUM'];

export function TierBadge({ tier, showScore, score }: TierBadgeProps) {
  const config = TIER_CONFIG[tier];
  const isLightBg = LIGHT_BG_TIERS.includes(tier);

  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
      <Tag
        color={config.color}
        style={{
          color: isLightBg ? '#555' : '#fff',
          fontWeight: 600,
          borderColor: config.color,
        }}
      >
        {config.icon} {config.label}
      </Tag>
      {showScore && score !== undefined && (
        <span style={{ fontSize: 13, color: '#666' }}>{score.toLocaleString()}점</span>
      )}
    </span>
  );
}
