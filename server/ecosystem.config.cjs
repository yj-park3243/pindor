module.exports = {
  apps: [
    {
      name: 'match-api',
      script: 'src/server.ts',
      interpreter: './node_modules/.bin/tsx',
      watch: ['src'],
      watch_delay: 1000,
      ignore_watch: ['node_modules', 'dist', 'logs', '*.log'],
      env: {
        NODE_ENV: 'development',
        PORT: 3000,
      },
      // 로그 — 날짜별 로테이션 (7일 보관)
      error_file: 'logs/api-error.log',
      out_file: 'logs/api-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      merge_logs: true,
      // 무중단 배포 설정
      listen_timeout: 5000,    // 새 프로세스 ready 대기 (5초)
      kill_timeout: 5000,      // 기존 프로세스 graceful shutdown 대기 (5초)
      wait_ready: false,       // listen 이벤트 대기 (process.send('ready') 불필요)
      // 재시작 정책
      max_restarts: 10,
      restart_delay: 1000,
      autorestart: true,
    },
    {
      name: 'match-worker',
      script: 'src/workers/push.worker.ts',
      interpreter: './node_modules/.bin/tsx',
      watch: ['src/workers'],
      watch_delay: 1000,
      ignore_watch: ['node_modules', 'dist', 'logs'],
      env: {
        NODE_ENV: 'development',
      },
      error_file: 'logs/worker-error.log',
      out_file: 'logs/worker-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      merge_logs: true,
      max_restarts: 10,
      restart_delay: 2000,
      autorestart: true,
    },
    {
      name: 'match-queue',
      script: 'src/workers/matching-queue.worker.ts',
      interpreter: './node_modules/.bin/tsx',
      watch: ['src/workers'],
      watch_delay: 1000,
      ignore_watch: ['node_modules', 'dist', 'logs'],
      env: {
        NODE_ENV: 'development',
        STANDALONE_WORKER: 'true',
      },
      error_file: 'logs/queue-error.log',
      out_file: 'logs/queue-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      merge_logs: true,
      max_restarts: 10,
      restart_delay: 2000,
      autorestart: true,
    },
  ],
};
