# 운영 / 스테이징 분리 계획 (2026-05-11 작성)

운영 출시 후 E2E 테스트를 운영 DB·서버에서 돌리면 안 되니 별도 staging 환경 구축.

## 현재 구조 (분리 전)

```
사용자 앱/Admin ──┬─→ api.pins.kr (EC2 1대)
                  ├─→ admin.pins.kr (EC2 1대, Nginx 정적)
                  ├─→ Redis (EC2 로컬)
                  └─→ RDS spots (운영 DB)
E2E 시나리오  ────┘  (위 운영 인프라 그대로 사용)
```

**문제점**
- E2E `bash run_all_scenarios.sh`가 운영 DB·서버에 직접 호출 → 실 사용자와 충돌
- 운영 매칭 큐(BullMQ)에 E2E 매칭 요청이 끼어들어 실 사용자 매칭 지연
- 점수/랭킹/푸시 모두 운영 데이터 오염
- 운영 시간대 회귀 못 돌림

---

## 목표 구조 (분리 후)

```
운영                                  스테이징 (테스트 전용)
─────────────────────────────         ────────────────────────────────
api.pins.kr (EC2)                     api-staging.pins.kr (EC2 같은 머신, 다른 포트)
admin.pins.kr                         admin-staging.pins.kr
RDS spots (운영 DB)                   RDS spots_staging 또는 spots_test (별도 DB)
Redis :6379 db 0                       Redis :6379 db 1 (또는 별도 인스턴스)
S3 bucket: pins-prod                   S3 bucket: pins-staging
Firebase project: pins-prod            Firebase project: pins-staging (FCM)
KCP: 운영 키                           KCP: 테스트 모드
```

---

## 분리 단계

### Phase 1 — 인프라 셋업 (1일)

#### 1-1. RDS staging DB 생성
**옵션 A (권장)**: 같은 RDS 인스턴스에 새 DB 추가
```sql
CREATE DATABASE spots_staging
  WITH OWNER spots_admin
  ENCODING 'UTF8'
  LC_COLLATE = 'C'
  LC_CTYPE = 'C'
  TEMPLATE = template0;

GRANT ALL PRIVILEGES ON DATABASE spots_staging TO spots_admin;
```
같은 RDS라 비용 추가 없음, 분리 효과 확보. 단점: DB 부하 공유.

**옵션 B**: 별도 RDS 인스턴스 생성 (db.t3.micro 정도, 월 15$)
완전 격리지만 비용/관리 부담.

#### 1-2. EC2 staging API 띄우기
같은 EC2에 PM2로 다른 포트(예: 3001) + 다른 .env로 추가 프로세스:

```
/home/ec2-user/spots-server          (운영, port 3000)
/home/ec2-user/spots-server-staging  (스테이징, port 3001, DATABASE_URL=spots_staging)
```

`ecosystem.staging.config.cjs`:
- name: `match-api-staging` / `match-worker-staging` / `match-queue-staging`
- env: `DATABASE_URL=...spots_staging`, `REDIS_URL=...db=1`, `PORT=3001`

#### 1-3. Nginx 라우팅
```
api.pins.kr           → 127.0.0.1:3000  (운영)
api-staging.pins.kr   → 127.0.0.1:3001  (스테이징)
admin-staging.pins.kr → spots-admin-staging/ 정적
```

ACM 인증서: `*.pins.kr` 와일드카드 한 장으로 둘 다 커버.

#### 1-4. Redis 분리
- 같은 인스턴스, `db=1` 사용 (가장 간단)
- 또는 별도 Redis (port 6380) 추가 — BullMQ 큐 완전 격리

---

### Phase 2 — 코드/설정 분리 (반나절)

#### 2-1. 환경별 .env 분리
```
server/.env              (운영)
server/.env.staging      (스테이징, gitignore)
```

#### 2-2. E2E 스크립트 환경 분리
`app/scripts/scenario-helpers.sh`:
```bash
API_URL="${API_URL:-https://api-staging.pins.kr/v1}"   # default를 staging으로
```

`run_all_scenarios.sh` 도 동일.

#### 2-3. Admin 환경 빌드 분리
```
admin/.env.production    VITE_API_URL=https://api.pins.kr/v1
admin/.env.staging       VITE_API_URL=https://api-staging.pins.kr/v1

npm run build:staging    # mode=staging
npm run build            # production
```

#### 2-4. Firebase project 분리 (선택, 권장)
새 Firebase project `pins-staging` 생성:
- FCM 푸시 토큰 운영과 격리 (테스트 푸시가 실 사용자에게 안 감)
- Identity Toolkit (test1@gmail.com 등)도 staging 프로젝트에 별도 가입
- `firebase_options.dart`를 build flavor로 분기 (`--dart-define=ENV=staging`)

---

### Phase 3 — 운영 데이터 스테이징 복제 (1회성)

스테이징에 운영 스키마만 옮김 (데이터는 새로 생성):
```bash
# 운영 schema dump (data 제외)
pg_dump --schema-only "${PROD_DATABASE_URL}" > schema.sql

# 스테이징 import
psql "${STAGING_DATABASE_URL}" < schema.sql

# 테스트 시드 (test1/test2/test3, 핀 일부, 공지 등)
psql "${STAGING_DATABASE_URL}" < e2e_seed.sql
```

선택: 운영 핀 데이터만 복제 (사용자 데이터 미복제):
```bash
pg_dump --data-only --table=pins "${PROD_DATABASE_URL}" \
  | psql "${STAGING_DATABASE_URL}"
```

---

### Phase 4 — CI 연동 (선택)

GitHub Actions:
- `main` 브랜치 push → 운영 배포
- `staging` 브랜치 push → 스테이징 배포 + 자동 회귀 (`run_all_scenarios.sh`)
- PR → 스테이징 회귀만 + 실패 시 머지 차단

```yaml
- name: E2E regression
  env:
    ADMIN_PASSWORD: ${{ secrets.STAGING_ADMIN_PASSWORD }}
    API_URL: https://api-staging.pins.kr/v1
  run: cd app && bash run_all_scenarios.sh
```

---

## 작업 우선순위 (즉시 진행 가능 순서)

| # | 작업 | 영향도 | 작업시간 |
|---|---|---|---|
| 1 | RDS에 `spots_staging` DB 생성 (옵션 A) | 운영 무관 | 10분 |
| 2 | EC2에 staging 서버 별도 디렉터리 + PM2 추가 | 운영 무관 | 1시간 |
| 3 | Nginx에 `api-staging.pins.kr` 라우팅 | 운영 무관 (별 도메인) | 30분 |
| 4 | DNS 레코드 (`api-staging`, `admin-staging`) 추가 | 운영 무관 | 10분 (전파 대기) |
| 5 | E2E 스크립트의 `API_URL` 기본값을 staging으로 변경 | E2E만 영향 | 5분 |
| 6 | Admin 빌드를 `staging` mode로 분기 | 운영 무관 | 30분 |
| 7 | Firebase staging 프로젝트 (선택) | 운영 무관 | 1시간 |

**최소 작업 (4시간)**: 1 → 2 → 3 → 4 → 5 만 해도 운영 격리 완료.

---

## 비용 추가 (옵션 A 기준)

| 항목 | 월 추가 비용 |
|---|---|
| RDS 새 DB | $0 (기존 인스턴스 공유) |
| EC2 staging 프로세스 (PM2) | $0 (기존 인스턴스 공유) |
| Nginx + ACM | $0 |
| Route53 서브도메인 | $0 |
| **합계** | **$0** |

옵션 B (별도 RDS 인스턴스)면 월 ~$15 추가.

---

## 진행 결정 부탁

- 옵션 A (같은 RDS에 spots_staging DB) vs 옵션 B (별도 RDS)
- Firebase staging 프로젝트 분리 여부
- Phase 4 (CI 자동 회귀) 진행 여부

확정되면 위 작업 1~5 (4시간)부터 시작합니다.
