# 인프라 & 배포

> 최종 업데이트: 2026-04-22

## AWS 인프라

| 리소스 | 상세 |
|--------|------|
| AWS 계정 | 518148354480 |
| 리전 | ap-northeast-2 (서울) |
| EC2 | t3.small, 43.203.165.114 |
| RDS | PostgreSQL 17 + PostGIS, spots-db.cuhooenm6qww.ap-northeast-2.rds.amazonaws.com |
| S3 | spots-uploads-518 (이미지), spots-file-uploads |
| SSH Key | ~/WebProject2/match/spots-key.pem |
| CLI 프로파일 | `--profile spots` (다른 프로젝트와 AWS config 공유 — 항상 명시적으로 프로파일 지정) |

## 도메인

| 서비스 | URL |
|--------|-----|
| API | https://api.pins.kr |
| 랜딩 | https://pins.kr |
| 어드민 | https://admin.pins.kr |

## 서버 (EC2)

- **런타임**: Node.js (Fastify) + PM2
- **프로세스 (ecosystem.config.cjs)**:
  - `match-api` — API 서버 (포트 3000, `src/server.ts`)
  - `match-worker` — FCM 푸시 워커 (`src/workers/push.worker.ts`)
  - `match-queue` — 매칭 큐 워커 (`src/workers/matching-queue.worker.ts`, `STANDALONE_WORKER=true`)
- **DB**: PostgreSQL 17 + PostGIS (RDS)
- **Redis**: EC2 로컬 (127.0.0.1:6379) — BullMQ, Socket.io, 캐시, pub/sub
- **Nginx**: SSL 리버스 프록시 (Let's Encrypt)
- **Firebase**: `FIREBASE_SERVICE_ACCOUNT` 환경변수 (JSON 문자열 또는 파일 경로)

### PM2 프로세스 설정

| 프로세스 | 로그 파일 | 재시작 정책 |
|----------|----------|------------|
| match-api | `logs/api-out.log`, `logs/api-error.log` | max_restarts: 10, restart_delay: 1000ms |
| match-worker | `logs/worker-out.log`, `logs/worker-error.log` | max_restarts: 10, restart_delay: 2000ms |
| match-queue | `logs/queue-out.log`, `logs/queue-error.log` | max_restarts: 10, restart_delay: 2000ms |

로컬 개발: `match-api`는 `src/` 디렉토리 watch 모드, worker/queue는 `src/workers/` watch 모드.
인터프리터: `./node_modules/.bin/tsx` (TypeScript 직접 실행).

### 서버 내 주기적 작업 (server.ts setInterval)

| 작업 | 주기 | 파일 |
|------|------|------|
| 만료된 매칭 요청 처리 | 5분 | `workers/match-expiry.worker.ts` |
| 결과 입력 기한 임박 알림 | 1시간 | `workers/result-deadline.worker.ts` |
| 랭킹 갱신 (BullMQ job) | 1시간 | `workers/ranking-refresh.worker.ts` |
| 매칭 큐 처리 | 10초 | `workers/matching-queue.worker.ts` |
| 경기 결과 자동 확정 (백업 폴링) | 5분 | `workers/auto-resolve.worker.ts` |

추가 워커 (import로 상시 활성화):
- `workers/match-accept-timeout.worker.ts` — BullMQ delayed job (매칭 수락 타임아웃 + 리마인더)
- `workers/game-auto-resolve.worker.ts` — BullMQ delayed job (경기 결과 3분 자동 확정)

### Redis pub/sub 채널

| 채널 | 용도 |
|------|------|
| `system_notification` | 워커 → 메인 서버 알림 발송 |
| `push_notification` | 워커 → 메인 서버 푸시 발송 |
| `match_lifecycle` | 매칭 상태 변경 → Socket.io 브로드캐스트 |
| `chat_room_message` | 시스템 메시지 → 채팅 룸 브로드캐스트 |

### 서버 배포
```bash
cd server && bash deploy.sh
```
rsync → npm install (변경 시만) → PM2 reload → health check

**주의**: 서버 코드 변경 시 유저가 명시적으로 "배포"라고 할 때까지 배포하지 않음. 배포 시에는 `run_in_background`로 실행.

## 앱 배포

```bash
cd app && bash deploy.sh          # iOS + Android
cd app && bash deploy.sh ios      # iOS만
cd app && bash deploy.sh android  # Android만
```

| 플랫폼 | 상세 |
|--------|------|
| iOS | Bundle ID: kr.pins, TestFlight (xcrun altool) |
| Android | Package: kr.pins.spots, Google Play Internal (fastlane supply) |

## 랜딩 배포

```bash
rsync -az -e "ssh -i spots-key.pem" landing/ ec2-user@43.203.165.114:spots-landing/
```
Nginx가 `/home/ec2-user/spots-landing`에서 정적 파일 서빙.

## 어드민 배포

```bash
# 로컬에서 빌드 후 rsync로 EC2에 업로드
rsync -az -e "ssh -i spots-key.pem" admin/dist/ ec2-user@43.203.165.114:spots-admin/
```
Nginx가 `/home/ec2-user/spots-admin`에서 정적 파일 서빙 (admin.pins.kr).

## 로컬 개발환경

- **서버**: PM2 (`pm2 start ecosystem.config.cjs`)
- **DB**: PostgreSQL 17 + PostGIS (localhost:5432, DB: sportsmatch)
- **Redis**: localhost:6379
- **포트**: 3000
- **Docker 미사용** — PM2로 로컬 서버 실행 선호, Docker는 배포용만

## 모니터링

```bash
# 프로세스 상태 확인
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 status"

# 실시간 CPU/메모리 모니터링
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 monit"

# 서버 로그 (최근 100줄)
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 logs match-api --lines 100"

# 워커 로그 (FCM 푸시)
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 logs match-worker --lines 100"

# 매칭 큐 로그
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 logs match-queue --lines 100"

# 에러 로그만
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 logs match-api --err --lines 50"
```

## DB 백업

- **RDS 자동 백업**: AWS 기본 정책으로 7일 보존 (자동 스냅샷)
- **스냅샷 수동 생성**: AWS 콘솔 → RDS → 인스턴스 선택 → Actions → Take snapshot
- 복원 시: 새 RDS 인스턴스로 스냅샷 복원 후 `.env`의 `DATABASE_URL` 변경

## 보안

- **SSH 키**: `~/WebProject2/match/spots-key.pem` — 버전 관리에 포함 금지, 로컬에만 보관
- **RDS Security Group**: EC2 인스턴스의 프라이빗 IP에서만 5432 포트 인바운드 허용 (공개 접근 차단)
- **환경변수**: 서버 `.env` 파일은 EC2 홈 디렉토리에만 존재, `.gitignore` 적용
- **JWT**: Access 7일, Refresh 30일. 키는 `.env`의 `JWT_SECRET`으로 관리
- **Firebase**: `FIREBASE_SERVICE_ACCOUNT` 환경변수로 관리 (JSON 또는 파일 경로)

## 장애 대응

- **PM2 자동 재시작**: 크래시 발생 시 `max_restarts: 10` 설정으로 자동 재시작
- **Health check**: `GET https://api.pins.kr/health` → `{ status: "ok" }` 응답 확인
- **서버 재시작 절차**:
  ```bash
  ssh -i spots-key.pem ec2-user@43.203.165.114
  pm2 restart match-api     # API 서버만
  pm2 restart match-worker  # 푸시 워커만
  pm2 restart match-queue   # 매칭 큐만
  pm2 restart all           # 전체 프로세스
  ```
- **서버 응답 없을 시**: EC2 콘솔에서 인스턴스 재시작 → `pm2 resurrect`로 프로세스 복구
