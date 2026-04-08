import { ArrowUpOutlined, ArrowDownOutlined } from '@ant-design/icons';

interface ScoreDisplayProps {
  score: number;
  change?: number;
  showChange?: boolean;
}

export function ScoreDisplay({ score, change, showChange = true }: ScoreDisplayProps) {
  const hasChange = showChange && change !== undefined && change !== 0;

  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
      <strong>{score.toLocaleString()}</strong>
      {hasChange && (
        <span
          style={{
            fontSize: 12,
            color: change! > 0 ? '#52c41a' : '#ff4d4f',
            display: 'inline-flex',
            alignItems: 'center',
          }}
        >
          {change! > 0 ? (
            <ArrowUpOutlined />
          ) : (
            <ArrowDownOutlined />
          )}
          {Math.abs(change!)}
        </span>
      )}
    </span>
  );
}
