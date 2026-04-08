import { Tag } from 'antd';

interface StatusTagProps {
  status: string;
  config: Record<string, { label: string; color: string }>;
}

export function StatusTag({ status, config }: StatusTagProps) {
  const item = config[status];
  if (!item) {
    return <Tag>{status}</Tag>;
  }
  return <Tag color={item.color}>{item.label}</Tag>;
}
