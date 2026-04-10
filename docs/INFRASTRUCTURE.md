# 인프라 & 배포

## AWS 인프라

| 리소스 | 상세 |
|--------|------|
| AWS 계정 | 518148354480 |
| 리전 | ap-northeast-2 (서울) |
| EC2 | t3.small, 43.203.165.114 |
| RDS | PostgreSQL 17 + PostGIS, spots-db.cuhooenm6qww.ap-northeast-2.rds.amazonaws.com |
| S3 | spots-uploads-518 (이미지), spots-file-uploads |
| SSH Key | ~/WebProject2/match/spots-key.pem |
| CLI 프로파일 | `--profile spots` |

## 도메인

| 서비스 | URL |
|--------|-----|
| API | https://api.pins.kr |
| 랜딩 | https://pins.kr |
| 어드민 | https://admin.pins.kr |

## 서버 (EC2)

- **런타임**: Node.js (Fastify) + PM2
- **프로세스**: match-api (포트 3000), match-worker, match-queue
- **DB**: PostgreSQL 17 + PostGIS (RDS)
- **Redis**: EC2 로컬 (127.0.0.1:6379)
- **Nginx**: SSL 리버스 프록시 (Let's Encrypt)

### 서버 배포
```bash
cd server && bash deploy.sh
```
rsync → npm install (변경 시만) → PM2 reload → health check

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
rsync -az -e "ssh -i spots-key.pem" admin/dist/ ec2-user@43.203.165.114:spots-admin/
```

## 로컬 개발환경

- **서버**: PM2 (`pm2 start ecosystem.config.cjs`)
- **DB**: PostgreSQL 17 + PostGIS (localhost:5432, DB: sportsmatch)
- **Redis**: localhost:6379
- **포트**: 3000

## 모니터링

```bash
# 프로세스 상태 확인
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 status"

# 실시간 CPU/메모리 모니터링
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 monit"

# 서버 로그 (최근 100줄)
ssh -i spots-key.pem ec2-user@43.203.165.114 "pm2 logs match-api --lines 100"

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

## 장애 대응

- **PM2 자동 재시작**: 크래시 발생 시 `max_restarts: 10` 설정으로 자동 재시작
- **Health check**: `GET https://api.pins.kr/health` → `{ status: "ok" }` 응답 확인
- **서버 재시작 절차**:
  ```bash
  ssh -i spots-key.pem ec2-user@43.203.165.114
  pm2 restart match-api   # API 서버만
  pm2 restart all         # 전체 프로세스
  ```
- **서버 응답 없을 시**: EC2 콘솔에서 인스턴스 재시작 → `pm2 resurrect`로 프로세스 복구
