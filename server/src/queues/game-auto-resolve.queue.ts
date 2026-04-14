import { Queue } from 'bullmq';
import { bullmqRedis } from '../config/redis.js';

// ─────────────────────────────────────
// 경기 결과 자동 확정 BullMQ 큐 (분리 파일)
//
// games.service.ts → 큐에 job 추가
// game-auto-resolve.worker.ts → 큐에서 job 소비
// 순환 의존성 방지를 위해 큐 정의를 별도 파일로 분리
// ─────────────────────────────────────

export interface GameAutoResolveJobData {
  gameId: string;
}

export const gameAutoResolveQueue = new Queue<GameAutoResolveJobData>(
  'game-auto-resolve',
  { connection: bullmqRedis },
);
