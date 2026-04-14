# 핀돌 (PINDOR)

위치 기반 스포츠 1:1 매칭 플랫폼

## 프로젝트 구조

| 디렉토리 | 설명 |
|----------|------|
| `app/` | Flutter 모바일 앱 (iOS/Android) |
| `server/` | Node.js API 서버 (Fastify + TypeORM) |
| `admin/` | React 어드민 대시보드 (Ant Design Pro) |
| `landing/` | 랜딩 페이지 (정적 HTML) |
| `docs/` | 프로젝트 문서 |

## 문서

### 기획
- [PRD (제품 요구사항)](docs/prd.md) — 핵심 기능, 화면 목록, 기술 요구사항
- [로드맵](docs/roadmap.md) — v1.1 ~ v2.0 릴리즈 계획
- [TODO](docs/todo.md) — 우선순위별 작업 목록

### 설계
- [매칭 시스템](docs/design-matching.md) — 매칭 흐름, 큐 워커, 비용함수, 패널티
  - [Glicko-2 알고리즘 상세](docs/design-matching-glicko2.md)
- [핀 시스템](docs/design-pin-system.md) — 핀 계층, 즐겨찾기, 매칭 연동
  - [핀 시드 데이터](docs/data/pins-seed.json)
- [티어 시스템](docs/design-tier-system.md) — 7티어 x 3단계, 승급/강등
- [신고/문의](docs/design-report-system.md) — 신고 플로우, 자동 제재
- [메인 화면](docs/design-main-screen.md) — 홈 UI 구조, 데이터 의존성
- [로컬 캐시](docs/design-local-cache.md) — Drift DB, SWR 패턴, TTL

### 운영
- [인프라 & 배포](docs/infrastructure.md) — AWS, 배포, 모니터링, 보안, 장애 대응
- [API/S3 최적화 분석](docs/optimization-analysis.md) — 요청 최적화 분석 및 액션 플랜

## 배포

```bash
# 서버
cd server && bash deploy.sh

# 앱 (iOS + Android)
cd app && bash deploy.sh

# 랜딩
rsync -az -e "ssh -i spots-key.pem" landing/ ec2-user@43.203.165.114:spots-landing/
```


# 핸드폰 인증키: eaa433b5da2ae426aa0d637e46c5644436c104870fa1eabd4af6e7f26e9536df