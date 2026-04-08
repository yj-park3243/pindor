import { Card, Statistic } from 'antd';
import type { ReactNode } from 'react';

interface StatCardProps {
  title: string;
  value: number | string;
  prefix?: ReactNode;
  suffix?: string;
  trend?: {
    value: number;
    isPositive: boolean;
  };
  color?: string;
  loading?: boolean;
  onClick?: () => void;
}

export function StatCard({
  title,
  value,
  prefix,
  suffix,
  color = '#1890ff',
  loading = false,
  onClick,
}: StatCardProps) {
  return (
    <Card
      style={{
        cursor: onClick ? 'pointer' : 'default',
        borderTop: `3px solid ${color}`,
        borderRadius: 8,
      }}
      styles={{ body: { padding: '20px 24px' } }}
      loading={loading}
      onClick={onClick}
    >
      <Statistic
        title={title}
        value={value}
        prefix={prefix}
        suffix={suffix}
        valueStyle={{ color, fontSize: 28, fontWeight: 700 }}
      />
    </Card>
  );
}
