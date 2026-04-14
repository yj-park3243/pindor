import { AppDataSource } from '../../config/database.js';

// ─────────────────────────────────────
// 타입 정의
// ─────────────────────────────────────

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface MatchCandidate {
  id: string;
  userId: string;
  currentScore: number;
  gHandicap: number | null;
  tier: string;
  gamesPlayed: number;
  nickname: string;
  gender: string | null;
  birthDate: Date | null;
  homePointLat: number;
  homePointLng: number;
  distanceMeters: number;
  // 해당 후보의 매칭 요청 ID 및 조건
  matchRequestId: string;
  genderPreference: string;
  minAge: number | null;
  maxAge: number | null;
}

// ─────────────────────────────────────
// PostGIS 포인트 생성 헬퍼
// ─────────────────────────────────────

/**
 * WKT 형식 포인트 문자열 생성
 * PostGIS GEOGRAPHY(POINT, 4326) 삽입용
 */
export function makeGeoPoint(lat: number, lng: number): string {
  return `POINT(${lng} ${lat})`;
}

/**
 * ST_GeogFromText 인자용 WKT 문자열
 */
export function wktPoint(lat: number, lng: number): string {
  return `POINT(${lng} ${lat})`;
}

// ─────────────────────────────────────
// 반경 내 매칭 후보 탐색
// ─────────────────────────────────────

export interface FindCandidatesOptions {
  sportType: string;
  locationPoint: GeoPoint;
  radiusKm: number;
  minOpponentScore: number;
  maxOpponentScore: number;
  requesterScore: number;
  excludeUserIds?: string[];
  limit?: number;
}

/**
 * PostGIS ST_DWithin을 사용한 반경 내 매칭 후보 탐색
 * PRD 섹션 6.3의 findMatchCandidates 구현
 * 성별/나이 조건, 매칭 요청 ID 및 조건 정보도 함께 반환
 */
export async function findMatchCandidates(
  opts: FindCandidatesOptions,
): Promise<MatchCandidate[]> {
  const {
    sportType,
    locationPoint,
    radiusKm,
    minOpponentScore,
    maxOpponentScore,
    requesterScore,
    excludeUserIds = [],
    limit = 20,
  } = opts;

  const pointWkt = wktPoint(locationPoint.lat, locationPoint.lng);
  const radiusMeters = radiusKm * 1000;

  // excludeUserIds를 ANY($6::uuid[]) 형태의 parametrized array로 전달
  // 고정 파라미터: $1=sportType, $2=minOpponentScore, $3=maxOpponentScore,
  //               $4=pointWkt, $5=radiusMeters, $6=excludeUuids, $7=requesterScore, $8=limit
  const excludeClause = excludeUserIds.length > 0
    ? 'AND sp.user_id != ALL($6::uuid[])'
    : '';

  const adjustedParams: (string | number | string[])[] = [
    sportType,          // $1
    minOpponentScore,   // $2
    maxOpponentScore,   // $3
    pointWkt,           // $4
    radiusMeters,       // $5
    excludeUserIds,     // $6 (uuid array)
    requesterScore,     // $7
    limit,              // $8
  ];

  const rawQuery = `
    SELECT
      sp.id,
      sp.user_id AS "userId",
      sp.current_score AS "currentScore",
      sp.g_handicap AS "gHandicap",
      sp.tier,
      sp.games_played AS "gamesPlayed",
      u.nickname,
      u.gender,
      u.birth_date AS "birthDate",
      ST_Y(ul.home_point::geography::geometry) AS "homePointLat",
      ST_X(ul.home_point::geography::geometry) AS "homePointLng",
      ST_Distance(ul.home_point, ST_GeogFromText($4)) AS "distanceMeters",
      mr.id AS "matchRequestId",
      mr.gender_preference AS "genderPreference",
      mr.min_age AS "minAge",
      mr.max_age AS "maxAge"
    FROM sports_profiles sp
    JOIN users u ON u.id = sp.user_id
    JOIN user_locations ul ON ul.user_id = sp.user_id
    JOIN match_requests mr ON mr.requester_id = sp.user_id
      AND mr.sport_type = $1
      AND mr.status = 'WAITING'
    WHERE sp.sport_type = $1
      AND sp.current_score BETWEEN $2 AND $3
      AND sp.is_active = TRUE
      AND u.status = 'ACTIVE'
      AND ST_DWithin(
        ul.home_point,
        ST_GeogFromText($4),
        $5
      )
      ${excludeClause}
      AND sp.user_id NOT IN (
        SELECT DISTINCT unnest(ARRAY[
          (SELECT user_id FROM sports_profiles WHERE id = m.requester_profile_id),
          (SELECT user_id FROM sports_profiles WHERE id = m.opponent_profile_id)
        ])
        FROM matches m
        WHERE m.status IN ('PENDING_ACCEPT', 'CHAT', 'CONFIRMED')
      )
    ORDER BY
      ABS(sp.current_score - $7) ASC,
      ST_Distance(ul.home_point, ST_GeogFromText($4)) ASC
    LIMIT $8
  `;

  const results = await AppDataSource.query<MatchCandidate[]>(
    rawQuery,
    adjustedParams,
  );

  return results;
}

// ─────────────────────────────────────
// 주변 핀 탐색
// ─────────────────────────────────────

export interface NearbyPin {
  id: string;
  name: string;
  slug: string;
  level: string;
  centerLat: number;
  centerLng: number;
  userCount: number;
  distanceMeters: number;
}

export async function findNearbyPins(
  lat: number,
  lng: number,
  radiusKm: number,
): Promise<NearbyPin[]> {
  const pointWkt = wktPoint(lat, lng);
  const radiusMeters = radiusKm * 1000;

  return AppDataSource.query<NearbyPin[]>(
    `
    SELECT
      p.id,
      p.name,
      p.slug,
      p.level,
      ST_Y(p.center::geometry) AS "centerLat",
      ST_X(p.center::geometry) AS "centerLng",
      COUNT(pa.user_id)::int AS "userCount",
      ST_Distance(p.center, ST_GeogFromText($1)) AS "distanceMeters"
    FROM pins p
    LEFT JOIN pin_activities pa ON pa.pin_id = p.id
    WHERE p.is_active = TRUE
      AND ST_DWithin(p.center, ST_GeogFromText($1), $2)
    GROUP BY p.id, p.name, p.slug, p.level, p.center
    ORDER BY
      p.level DESC,
      ST_Distance(p.center, ST_GeogFromText($1)) ASC
    LIMIT 20
    `,
    [pointWkt, radiusMeters],
  );
}

// ─────────────────────────────────────
// 두 지점 간 거리 계산 (하버사인 공식)
// ─────────────────────────────────────

export function calculateDistance(pointA: GeoPoint, pointB: GeoPoint): number {
  const R = 6371; // 지구 반지름 (km)
  const dLat = toRad(pointB.lat - pointA.lat);
  const dLng = toRad(pointB.lng - pointA.lng);
  const lat1 = toRad(pointA.lat);
  const lat2 = toRad(pointB.lat);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.sin(dLng / 2) * Math.sin(dLng / 2) * Math.cos(lat1) * Math.cos(lat2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // km
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

// ─────────────────────────────────────
// 좌표 유효성 검증
// ─────────────────────────────────────

export function isValidLatLng(lat: number, lng: number): boolean {
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

// ─────────────────────────────────────
// PostGIS 업데이트 쿼리 헬퍼
// ─────────────────────────────────────

export async function upsertUserLocation(
  userId: string,
  opts: {
    lat: number;
    lng: number;
    address?: string;
    matchRadiusKm?: number;
    isHome?: boolean;
  },
): Promise<void> {
  const { lat, lng, address, matchRadiusKm = 10, isHome = true } = opts;
  const pointWkt = wktPoint(lat, lng);
  const columnName = isHome ? 'home_point' : 'current_point';

  await AppDataSource.query(
    `
    INSERT INTO user_locations (user_id, ${columnName}, home_address, match_radius_km)
    VALUES (
      $1::uuid,
      ST_GeogFromText($2),
      $3,
      $4
    )
    ON CONFLICT (user_id) DO UPDATE SET
      ${columnName} = ST_GeogFromText($2),
      home_address = COALESCE($3, user_locations.home_address),
      match_radius_km = $4,
      updated_at = NOW()
    `,
    [userId, pointWkt, address ?? null, matchRadiusKm],
  );
}

/**
 * 사용자 위치 업데이트 (raw SQL 직접 실행)
 */
export async function updateUserHomeLocation(
  userId: string,
  lat: number,
  lng: number,
  address?: string,
  matchRadiusKm?: number,
): Promise<void> {
  const pointWkt = wktPoint(lat, lng);

  await AppDataSource.query(
    `
    INSERT INTO user_locations (user_id, home_point, home_address, match_radius_km, updated_at)
    VALUES (
      $1::uuid,
      ST_GeogFromText($2),
      $3,
      $4,
      NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
      home_point = ST_GeogFromText($2),
      home_address = COALESCE($3, user_locations.home_address),
      match_radius_km = COALESCE($4, user_locations.match_radius_km),
      updated_at = NOW()
    `,
    [userId, pointWkt, address ?? null, matchRadiusKm ?? null],
  );
}

export async function updateMatchRequestLocation(
  matchRequestId: string,
  lat: number,
  lng: number,
): Promise<void> {
  const pointWkt = wktPoint(lat, lng);

  await AppDataSource.query(
    `
    UPDATE match_requests
    SET location_point = ST_GeogFromText($1),
        updated_at = NOW()
    WHERE id = $2::uuid
    `,
    [pointWkt, matchRequestId],
  );
}
