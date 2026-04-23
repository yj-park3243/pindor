# 핀(Pin) 시스템 설계

> 작성일: 2026-04-04
> 최종 업데이트: 2026-04-22 (코드 기반 최신화)

## 핵심 철학

> **핀은 모든 활동의 중심 단위다.**
>
> - GPS 위치는 "가까운 핀 찾기"에만 사용 (위치 기반 매칭 X)
> - **매칭**: 유저가 즐겨찾는 핀에서 직접 매칭 신청
> - **팀**: 핀 소속으로 결성, 해당 핀의 팀 목록에서 검색
> - **게시판**: 핀+종목별로 분리 운영 (`posts.sport_type` 컬럼)
> - **랭킹**: 핀별 독립 랭킹 (`ranking_entries` 테이블, 핀별 독립 점수)

## 1. Pin 엔티티 (현행)

`server/src/entities/pin.entity.ts` 기준:

```typescript
@Entity('pins')
export class Pin {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 100 })
  name!: string;

  @Column({ type: 'varchar', length: 100, unique: true })
  slug!: string;

  @Column({ name: 'center', type: 'geography', spatialFeatureType: 'Point', srid: 4326 })
  center!: object;

  @Column({ name: 'boundary', type: 'geography', spatialFeatureType: 'Polygon', srid: 4326, nullable: true })
  boundary!: object | null;

  @Column({ type: 'enum', enum: PinLevel, enumName: 'PinLevel' })
  level!: PinLevel;  // DONG | GU | CITY | PROVINCE

  @Column({ name: 'parent_pin_id', type: 'uuid', nullable: true })
  parentPinId!: string | null;

  @Column({ name: 'region_code', type: 'varchar', length: 10, nullable: true })
  regionCode!: string | null;

  @Column({ name: 'is_active', type: 'boolean', default: true })
  isActive!: boolean;

  @Column({ name: 'user_count', type: 'int', default: 0 })
  userCount!: number;

  @Column({ type: 'jsonb', default: {} })
  metadata!: Record<string, unknown>;

  // Self-referencing (부모-자식)
  parentPin!: Pin | null;
  childPins!: Pin[];
}
```

**참고**: 설계 문서에 있던 `PinType` (LANDMARK / SPORTS_FACILITY / PARK / CAMPUS)은 현재 코드에 미구현 상태. 핀 엔티티에 `pinType` 필드가 없으며, `PinType` enum도 `enums.ts`에 정의되어 있지 않음. 향후 필요 시 추가 예정.

핀 위치 데이터: 103개 입력 완료 (서울 34 + 수도권 17 + 지방 17 + GU 25 + CITY 10)
시드 데이터: [data/pins-seed.json](data/pins-seed.json)

## 2. 유저와 핀의 관계

### 2.1 즐겨찾기 핀 (UserPin)

유저는 자주 가는 핀을 등록. 매칭/게시판/팀 활동은 등록한 핀에서만.

`server/src/entities/user-pin.entity.ts`:

```typescript
@Entity('user_pins')
@Unique(['userId', 'pinId'])
export class UserPin {
  id!: string;
  userId!: string;
  pinId!: string;
  isPrimary!: boolean;   // 주 핀 여부
  joinedAt!: Date;
}
```

**설계 문서와의 차이**: 설계 문서에 있던 `matchAlert` (매칭 알림 수신 여부) 필드는 현재 미구현.

### 2.2 핀 활동 기록 (PinActivity)

핀에서의 활동(매칭, 즐겨찾기 등록 등)을 추적하는 테이블.

`server/src/entities/pin-activity.entity.ts`:

```typescript
@Entity('pin_activities')
@Unique(['pinId', 'userId'])
export class PinActivity {
  id!: string;
  pinId!: string;
  userId!: string;
  createdAt!: Date;
}
```

`PinsService`에서 활동 UPSERT 후 해당 핀의 `userCount`를 갱신한다:

```typescript
async recordActivity(pinId, userId): Promise<void> {
  // INSERT ... ON CONFLICT DO NOTHING
  await this.refreshUserCount(pinId);
}
```

### 2.3 핀 기반 매칭 플로우

```
1. 유저가 즐겨찾기 핀 중 하나 선택 (예: 강남역)
2. 종목 선택 (GOLF)
3. 매칭 타입 선택 (SCHEDULED/INSTANT/CASUAL)
4. 날짜/시간대 선택
5. -> 강남역 GOLF 매칭 풀에 요청 추가
6. -> 같은 핀+종목의 다른 유저와 매칭
```

### 2.4 핀 기반 팀 구조

팀은 반드시 **하나의 핀에 소속**:
- `Team.pinId` -- 팀의 홈 핀
- 해당 핀의 팀 목록에서 검색/가입
- 팀 매칭도 핀 기반 (같은 핀 or 다른 핀의 팀과 대전)

```
강남역 핀
  ├── 팀: 강남 이글스 (GOLF, 8명)
  ├── 팀: 역삼 스매시 (TENNIS, 5명)
  └── 팀: GN 빌리어즈 (BILLIARDS, 4명)
```

**팀 검색 API:**
```
GET /teams?pinId=...&sportType=...  (핀 기반)
```

### 2.5 핀 발견 (유일한 위치 기반 기능)

GPS는 **핀 발견**에만 사용:
```
GET /pins/nearby?latitude=37.4979&longitude=127.0276&radius=10
```

유저가 핀을 발견하면 즐겨찾기에 추가, 이후 모든 활동은 핀 기반.

## 3. 핀+종목별 게시판 (구현 완료)

### 3.1 구조

게시판은 **핀+종목** 조합으로 분리 운영:
- 강남역 > 골프 게시판
- 강남역 > 테니스 게시판
- 강남역 > 당구 게시판
- 강남역 > 종목 미지정 (전체) 게시판

### 3.2 Post 엔티티

`server/src/entities/post.entity.ts`:

```typescript
@Entity('posts')
export class Post {
  id!: string;
  pinId!: string;
  authorId!: string;
  title!: string;           // varchar(100)
  content!: string;         // text
  category!: PostCategory;  // GENERAL | MATCH_SEEK | REVIEW | NOTICE

  @Column({ name: 'sport_type', type: 'varchar', length: 30, default: 'GOLF' })
  sportType!: string;       // 종목 필터링용

  viewCount!: number;
  likeCount!: number;
  commentCount!: number;
  isDeleted!: boolean;
  createdAt!: Date;
  updatedAt!: Date;
}
```

**핵심 변경 사항**:
- `sport_type` 컬럼이 `varchar(30)` 타입으로 추가됨 (기본값: `'GOLF'`)
- 게시글 작성 시 `sportType` 파라미터로 종목 지정 (미지정 시 기본값 GOLF)
- 게시글 목록 조회 시 `sportType` 쿼리 파라미터로 필터링 가능

### 3.3 스키마 (Zod 검증)

`server/src/modules/pins/pins.schema.ts`:

```typescript
// 게시글 목록 조회
export const listPostsQuerySchema = z.object({
  category: z.nativeEnum(PostCategory).optional(),
  sportType: z.nativeEnum(SportType).optional(),  // 종목별 필터링
  search: z.string().max(100).optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(50).default(20),
});

// 게시글 작성
export const createPostSchema = z.object({
  title: z.string().min(1).max(100),
  content: z.string().min(1).max(2000),
  category: z.nativeEnum(PostCategory).default(PostCategory.GENERAL),
  sportType: z.nativeEnum(SportType).optional(),  // 종목 지정
  imageUrls: z.array(z.string().url()).max(5).optional(),
});
```

### 3.4 게시글 작성 시 종목 처리

`PinsService.createPost()`:

```typescript
const post = postRepo.create({
  pinId,
  authorId: userId,
  title: dto.title,
  content: dto.content,
  category: dto.category,
  sportType: dto.sportType ?? 'GOLF',  // 미지정 시 GOLF 기본값
});
```

### 3.5 게시글 목록 조회 시 종목 필터링

`PinsService.getPosts()` -- QueryBuilder 기반:

```typescript
if (query.sportType) {
  qb.andWhere('post.sportType = :sportType', { sportType: query.sportType });
}
```

### 3.6 작성자 티어 표시

게시글 목록/상세에서 작성자의 티어를 함께 조회:
- 목록: `DISTINCT ON (user_id)` + `ORDER BY current_score DESC` 로 해당 유저의 최고 점수 종목 티어 조회
- 상세: `ORDER BY current_score DESC LIMIT 1` 로 단건 조회

```typescript
// 목록 조회 시
const tierRows = await AppDataSource.query(
  `SELECT DISTINCT ON (user_id) user_id AS "userId", tier FROM sports_profiles
   WHERE user_id = ANY($1::uuid[]) AND is_active = true
   ORDER BY user_id, current_score DESC`,
  [authorIds],
);
```

### 3.7 게시판 입장 조건

현재 구현 기준으로 **게시글 조회는 자유**, **작성은 인증된 사용자**면 가능 (로그인 필수, `fastify.authenticate` 미들웨어 적용).

설계 문서에 있던 "해당 핀에서 1회 이상 매칭 참가해야 게시판 이용 가능" 조건은 현재 미구현.

### 3.8 API 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/pins/all?version=...` | 전체 핀 목록 (버전 기반 동기화) |
| GET | `/pins/batch?ids=...` | 핀 배치 조회 |
| POST | `/pins/favorite` | 자주 가는 핀 등록 |
| GET | `/pins/nearby?latitude=...&longitude=...&radius=...` | 주변 핀 탐색 |
| GET | `/pins/:id` | 핀 상세 |
| GET | `/pins/:pinId/posts?sportType=...&category=...&search=...` | 게시글 목록 |
| POST | `/pins/:pinId/posts` | 게시글 작성 (`{ sportType, ... }`) |
| GET | `/pins/:pinId/posts/:postId` | 게시글 상세 |
| PATCH | `/pins/:pinId/posts/:postId` | 게시글 수정 |
| DELETE | `/pins/:pinId/posts/:postId` | 게시글 삭제 (소프트) |
| POST | `/pins/:pinId/posts/:postId/comments` | 댓글 작성 |
| GET | `/pins/:pinId/posts/:postId/comments` | 댓글 목록 |
| DELETE | `/pins/:pinId/posts/:postId/comments/:commentId` | 댓글 삭제 (소프트) |
| POST | `/pins/:pinId/posts/:postId/like` | 좋아요 토글 |

## 4. 핀별 랭킹 시스템

### 4.1 RankingEntry 엔티티

`server/src/entities/ranking-entry.entity.ts`:

```typescript
@Entity('ranking_entries')
@Unique(['pinId', 'sportsProfileId', 'sportType'])
export class RankingEntry {
  id!: string;
  pinId!: string;
  sportsProfileId!: string;
  sportType!: SportType;
  rank!: number;
  score!: number;        // 핀별 독립 점수
  tier!: Tier;
  gamesPlayed!: number;
  updatedAt!: Date;
}
```

### 4.2 핀별 독립 점수 체계

- 각 핀+종목 조합마다 독립적인 점수 (`ranking_entries.score`)를 관리
- 매칭 결과 반영(`applyEloChanges`)에서 핀별 점수를 개별 업데이트
- `sports_profiles.currentScore`는 해당 유저의 모든 `ranking_entries` 중 최고 점수로 갱신
- 등수 기반 티어 계산: `calculateTierByRank(rank, totalPlayers)`

### 4.3 랭킹 리프레시 워커

`server/src/workers/ranking-refresh.worker.ts`:

BullMQ 기반 워커로 매시간 랭킹 갱신:

**특정 핀 랭킹 갱신** (`refreshPinRanking`):
1. `ranking_entries` 기반으로 해당 핀+종목의 기존 유저 조회 (점수 높은 순, 100명 제한)
2. 신규 진입자(기존 엔트리 없으나 3게임 이상 플레이)도 포함
3. Redis 랭킹 캐시 초기화 후 재빌드
4. DB `ranking_entries` 동기화 (등수/티어 재계산)
5. 핀 `userCount` 갱신

**빈 배열 처리 (수정 완료)**: `existingProfileIds`가 빈 Set일 때 `NOT IN (:...existingIds)` 쿼리가 실패하는 문제를 분기 처리로 해결:

```typescript
let newProfiles: SportsProfile[] = [];
if (existingProfileIds.size > 0) {
  // NOT IN 조건 포함 쿼리
  newProfiles = await sportsProfileRepo
    .createQueryBuilder('sp')
    // ...
    .andWhere('sp.id NOT IN (:...existingIds)', {
      existingIds: [...existingProfileIds],
    })
    .getMany();
} else {
  // existingProfileIds가 비어있으면 NOT IN 조건 없이 전체 조회
  newProfiles = await sportsProfileRepo
    .createQueryBuilder('sp')
    // ...
    .getMany();
}
```

**전체 랭킹 갱신** (`refreshAllRankings`):
1. 전국 랭킹 갱신 (종목별 상위 500명, 10게임 이상)
2. 각 핀별 랭킹을 큐에 배치 등록 (100개씩)

### 4.4 핀 userCount 갱신 로직

두 가지 경로로 갱신:

1. **PinsService** (`refreshUserCount`): `pin_activities` 카운트 기반
2. **RankingRefreshWorker**: `user_pins` + `matches` 조인 기반 (고유 사용자 수)

## 5. 지원 종목 목록

`server/src/entities/enums.ts`의 `SportType` enum:

| 코드 | 종목 |
|------|------|
| GOLF | 골프 |
| BILLIARDS | 당구 |
| BILLIARDS_4BALL | 당구 (4구) |
| BILLIARDS_3CUSHION | 당구 (3쿠션) |
| TENNIS | 테니스 |
| TABLE_TENNIS | 탁구 |
| BADMINTON | 배드민턴 |
| BOWLING | 볼링 |
| SOCCER | 축구 |
| BASKETBALL | 농구 |
| BASEBALL | 야구 |
| ROCK_PAPER_SCISSORS | 가위바위보 |
| ARM_WRESTLING | 팔씨름 |
