import 'dotenv/config';
import { Queue } from 'bullmq';
import { bullmqRedis } from '../src/config/redis.js';

async function main() {
  const queue = new Queue('ranking-refresh', { connection: bullmqRedis });
  await queue.add('refresh-all', {});
  console.log('Enqueued refresh-all');
  await queue.close();
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
