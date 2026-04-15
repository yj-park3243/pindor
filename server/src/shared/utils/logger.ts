// 서버 구조화 로거
// Fastify의 pino 로거와 별도로, 워커/서비스에서 사용
// 추후 DataDog/CloudWatch 연동 시 이 파일만 수정

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const MIN_LEVEL: LogLevel = process.env.NODE_ENV === 'production' ? 'info' : 'debug';

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] >= LOG_LEVELS[MIN_LEVEL];
}

function formatMessage(tag: string, level: LogLevel, message: string): string {
  const timestamp = new Date().toISOString();
  return `[${timestamp}] [${level.toUpperCase()}] [${tag}] ${message}`;
}

export const logger = {
  debug(tag: string, message: string, data?: any) {
    if (shouldLog('debug')) {
      console.log(formatMessage(tag, 'debug', message), data ?? '');
    }
  },

  info(tag: string, message: string, data?: any) {
    if (shouldLog('info')) {
      console.info(formatMessage(tag, 'info', message), data ?? '');
    }
  },

  warn(tag: string, message: string, data?: any) {
    if (shouldLog('warn')) {
      console.warn(formatMessage(tag, 'warn', message), data ?? '');
    }
  },

  error(tag: string, message: string, error?: any) {
    console.error(formatMessage(tag, 'error', message));
    if (error) {
      console.error(error instanceof Error ? error.stack : error);
    }
    // TODO: 추후 Sentry/DataDog 연동
    // if (process.env.NODE_ENV === 'production') {
    //   Sentry.captureException(error);
    // }
  },
};
