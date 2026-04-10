# 핀(Pin) 시스템 확장 설계

> 작성일: 2026-04-04

## 핵심 철학

> **핀은 모든 활동의 중심 단위다.**
>
> - GPS 위치는 "가까운 핀 찾기"에만 사용 (위치 기반 매칭 X)
> - **매칭**: 유저가 즐겨찾는 핀에서 직접 매칭 신청
> - **팀**: 핀 소속으로 결성, 해당 핀의 팀 목록에서 검색
> - **게시판**: 핀+종목별로 운영, 해당 핀에서 1회 이상 참가해야 작성 가능
> - **랭킹**: 핀별 랭킹 (같은 핀 유저끼리 순위 경쟁)

## 1. 현행 시스템

- `Pin` 모델: name, slug, center(Point), boundary(Polygon), level(DONG/GU/CITY/PROVINCE)
- 부모-자식 관계 (PinHierarchy)
- 핀별 게시판 (Post), 랭킹 (RankingEntry)
- 핀 위치 데이터: 103개 입력 완료 (서울 34 + 수도권 17 + 지방 17 + GU 25 + CITY 10)

핀 시드 데이터: [data/pins-seed.json](data/pins-seed.json)

## 2. 유저와 핀의 관계

### 2.1 즐겨찾기 핀 (UserPin)

유저는 자주 가는 핀을 **즐겨찾기**로 등록. 매칭/게시판/팀 활동은 등록한 핀에서만.

```
유저 A의 즐겨찾기 핀:
  ★ 강남역 (주 핀) — 매칭 알림 ON
  ☆ 홍대입구역 — 매칭 알림 ON
  ☆ 판교역 — 매칭 알림 OFF
```

**스키마** (기존 `UserPin` 모델 활용):
```prisma
model UserPin {
  id        String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId    String   @map("user_id") @db.Uuid
  pinId     String   @map("pin_id") @db.Uuid
  isPrimary Boolean  @default(false) @map("is_primary")
  matchAlert Boolean @default(true) @map("match_alert")  // 신규: 매칭 알림 수신 여부
  createdAt DateTime @default(now()) @map("created_at") @db.Timestamptz

  user User @relation(fields: [userId], references: [id])
  pin  Pin  @relation(fields: [pinId], references: [id])

  @@unique([userId, pinId])
  @@map("user_pins")
}
```

### 2.2 핀 기반 매칭 플로우

```
1. 유저가 즐겨찾기 핀 중 하나 선택 (예: 강남역)
2. 종목 선택 (GOLF)
3. 매칭 타입 선택 (랭크/연습)
4. 날짜/시간대 선택
5. → 강남역 GOLF 매칭 풀에 요청 추가
6. → 같은 핀+종목의 다른 유저와 매칭
```

### 2.3 핀 기반 팀 구조

팀은 반드시 **하나의 핀에 소속**:
- `Team.pinId` — 팀의 홈 핀
- 해당 핀의 팀 목록에서 검색/가입
- 팀 매칭도 핀 기반 (같은 핀 or 다른 핀의 팀과 대전)

```
강남역 핀
  ├── 팀: 강남 이글스 (GOLF, 8명)
  ├── 팀: 역삼 스매시 (TENNIS, 5명)
  └── 팀: GN 빌리어즈 (BILLIARDS, 4명)
```

**팀 검색 API 변경:**
```
기존: GET /teams/nearby?latitude=...&longitude=...  (위치 기반)
변경: GET /teams?pinId=...&sportType=...  (핀 기반)
```

### 2.4 핀 발견 (유일한 위치 기반 기능)

GPS는 **핀 발견**에만 사용:
```
GET /pins/nearby?latitude=37.4979&longitude=127.0276&radiusKm=5
→ [강남역, 서초역, 교대역, 삼성역(코엑스)]
```

유저가 핀을 발견하면 즐겨찾기에 추가 → 이후 모든 활동은 핀 기반.

## 3. 핀 종류 (PinType)

| PinType | 설명 | 아이콘 |
|---------|------|--------|
| LANDMARK | 랜드마크/역세권 (기본) | 📍 |
| SPORTS_FACILITY | 스포츠 시설 밀집 지역 | 🏟 |
| PARK | 공원/야외 운동 가능 지역 | 🌳 |
| CAMPUS | 대학교/학교 밀집 지역 | 🎓 |

> 초기에는 모든 핀을 LANDMARK로 설정. 추후 유저 피드백으로 세분화.

```prisma
enum PinType {
  LANDMARK
  SPORTS_FACILITY
  PARK
  CAMPUS
}

model Pin {
  // 기존 필드...
  pinType     PinType  @default(LANDMARK) @map("pin_type")
}
```

## 4. 핀+종목별 게시판

### 4.1 구조

현행: `Pin → Post (category: GENERAL|MATCH_SEEK|REVIEW|NOTICE)`

개편안: `Pin → SportType → Post`

게시판은 핀+종목 조합으로 나뉨:
- 강남역 > 골프 게시판
- 강남역 > 테니스 게시판
- 강남역 > 당구 게시판
- 강남역 > 전체 게시판 (종목 무관)

### 4.2 스키마 변경

```prisma
model Post {
  // 기존 필드...
  sportType   SportType?  @map("sport_type")  // null = 전체 게시판
}
```

API 변경:
```
GET /pins/:pinId/posts?sportType=GOLF&category=GENERAL
POST /pins/:pinId/posts  { sportType: "GOLF", ... }
```

### 4.3 게시판 입장 조건

**규칙**: 해당 핀에서 1회 이상 매칭 참가 (완료된 매칭)해야 게시판 이용 가능

**판별 로직**:
```typescript
async function canAccessPinBoard(userId: string, pinId: string): Promise<boolean> {
  const completedMatches = await prisma.match.count({
    where: {
      pinId,
      status: 'COMPLETED',
      OR: [
        { requesterProfile: { userId } },
        { opponentProfile: { userId } },
      ],
    },
  });
  return completedMatches >= 1;
}
```

**미들웨어로 적용**:
- `GET /pins/:pinId/posts` → 조회는 자유 (누구나 볼 수 있음)
- `POST /pins/:pinId/posts` → 작성은 참가자만
- `POST /pins/:pinId/posts/:postId/comments` → 댓글도 참가자만
- `POST /pins/:pinId/posts/:postId/like` → 좋아요도 참가자만

**예외**: category가 `NOTICE`인 글은 누구나 볼 수 있음 (어드민 공지)

## 5. Seed 스크립트 구조

```typescript
// server/prisma/seed-pins.ts
const PINS = [
  {
    name: '강남역',
    slug: 'gangnam-station',
    lat: 37.4979,
    lng: 127.0276,
    level: 'DONG',
    pinType: 'LANDMARK',
    parentSlug: 'gangnam-gu',
    regionCode: '1168010100',
  },
  // ... 78개 — 좌표 데이터: data/pins-seed.json 참고
];

// GU 레벨 핀도 생성 (서울 25구)
const GU_PINS = [
  { name: '강남구', slug: 'gangnam-gu', lat: 37.5172, lng: 127.0473, level: 'GU', parentSlug: 'seoul' },
  // ... 25개
];

// CITY 레벨 핀
const CITY_PINS = [
  { name: '서울특별시', slug: 'seoul', lat: 37.5665, lng: 126.9780, level: 'CITY' },
  { name: '부산광역시', slug: 'busan', lat: 35.1796, lng: 129.0756, level: 'CITY' },
  // ...
];
```
