# PINS 인프라 정보

> 최종 업데이트: 2026-04-04

---

## 도메인 & 서비스 구성

| 서비스 | URL | 설명 |
|--------|-----|------|
| **랜딩 페이지** | https://pins.kr | 소개 + 개인정보처리방침 + 이용약관 + 고객지원 |
| **API 서버** | https://api.pins.kr/v1 | Fastify REST API |
| **WebSocket** | wss://api.pins.kr/ws | Socket.IO 실시간 채팅 |
| **어드민** | https://pins.kr/admin | React 어드민 대시보드 |
| **Swagger 문서** | https://pins.kr/docs | API 문서 (개발 환경만) |

---

## 서버 인프라

| 항목 | 값 |
|------|-----|
| **EC2** | 43.203.165.114 (ap-northeast-2) |
| **AWS 계정** | 518148354480 |
| **OS** | Amazon Linux / Ubuntu |
| **Node.js** | >= 20.x |
| **프로세스 관리** | PM2 |
| **포트** | API: 3000, WS: 3001 |

---

## DB 접속 정보

### PostgreSQL 17 + PostGIS

| 항목 | 로컬 | 운영 (RDS) |
|------|------|------------|
| **Host** | localhost | RDS 엔드포인트 (AWS 콘솔 확인) |
| **Port** | 5432 | 5432 |
| **Database** | spots | spots |
| **User** | yongju | (RDS 마스터 유저) |
| **URL** | `postgresql://yongju@localhost:5432/spots?schema=public` | `.env` 파일 참조 |

### Redis

| 항목 | 로컬 | 운영 |
|------|------|------|
| **URL** | `redis://localhost:6379` | ElastiCache 또는 EC2 Redis |

---

## 앱 정보

| 항목 | iOS | Android |
|------|-----|---------|
| **Bundle ID** | `kr.pins` | `kr.pins.spots` |
| **스토어** | App Store (TestFlight) | Google Play (내부 테스트) |
| **ASC Key ID** | LCL3N2RXK5 | - |
| **ASC Issuer ID** | 3cfdbba6-47f7-42ea-a707-ce14cf8369ef | - |
| **Play 서비스 키** | - | `etc/google console/youandme-6d92c-1c90442bbc10.json` |
| **네이버 지도 Client ID** | 539desbv96 | 539desbv96 |
| **API 도메인** | https://pins.kr | https://pins.kr |

---

## 배포 방법

### 앱 (Flutter)

```bash
# 전체 배포 (iOS + Android)
cd app && ./deploy.sh

# iOS만
./deploy.sh ios

# Android만
./deploy.sh android
```

- 빌드번호 자동 증가
- iOS: `flutter build ipa` → `xcrun altool` → TestFlight 업로드
- Android: `flutter build appbundle` → `fastlane supply` → Google Play 내부 테스트

### 서버 (Fastify + TypeORM)

```bash
# 로컬 개발
cd server
pm2 start ecosystem.config.cjs     # API + Worker 시작
pm2 logs                            # 로그 확인
pm2 restart all                     # 재시작

# EC2 배포
ssh ec2-user@43.203.165.114
cd ~/match/server
git pull origin main
npm install
pm2 restart all
```

**PM2 프로세스:**
| 이름 | 스크립트 | 역할 |
|------|---------|------|
| match-api | `src/server.ts` | REST API + WebSocket |
| match-worker | `src/workers/push.worker.ts` | FCM 푸시 알림 워커 |

### 어드민 (React + Vite)

```bash
# 로컬 개발
cd admin && npm run dev

# 빌드 & 배포
cd admin && npm run build
# dist/ 폴더를 EC2 또는 S3+CloudFront에 배포
```

### 랜딩 페이지

```bash
# 정적 파일 — S3 또는 EC2 nginx에 배포
cd landing/
# index.html, privacy.html, terms.html, support.html
```

---

## 환경 변수 (.env)

```env
# 서버
PORT=3000
WS_PORT=3001
NODE_ENV=development

# DB
DATABASE_URL=postgresql://user:pass@host:5432/spots?schema=public

# Redis
REDIS_URL=redis://localhost:6379

# JWT
JWT_SECRET=<32자 이상>
JWT_ACCESS_EXPIRES_IN=7d
JWT_REFRESH_EXPIRES_IN=30d

# AWS S3
AWS_REGION=ap-northeast-2
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_S3_BUCKET=sportsmatch-uploads-dev
AWS_CLOUDFRONT_DOMAIN=

# Firebase (FCM 푸시)
FIREBASE_SERVICE_ACCOUNT=<JSON string>

# CORS
CORS_ORIGIN=*

# 어드민
ADMIN_SECRET_KEY=<32자 이상>

# 카카오 OAuth
KAKAO_REST_API_KEY=
```

---

## 기술 스택

| 레이어 | 기술 |
|--------|------|
| **앱** | Flutter (Dart), Riverpod, GoRouter, Socket.IO Client |
| **어드민** | React 18, Vite, Ant Design, TanStack Query, Axios |
| **서버** | Fastify 4, TypeORM, TypeScript, Socket.IO, BullMQ |
| **DB** | PostgreSQL 17 + PostGIS |
| **캐시/큐** | Redis + BullMQ |
| **인증** | JWT (jose), 소셜 로그인 (카카오/구글/애플) |
| **푸시** | Firebase Admin SDK (FCM) |
| **파일** | AWS S3 + CloudFront (presigned URL) |
| **지도** | 네이버 지도 SDK |
| **배포** | PM2, Fastlane, xcrun altool |
