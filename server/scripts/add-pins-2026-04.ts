/**
 * 2026-04 신규 핀 추가 + 송도 센트럴파크 중복 정리
 *
 * 실행 (운영 RDS):
 *   ssh ec2-user@... "cd ~/spots-server && npx tsx scripts/add-pins-2026-04.ts"
 */
import 'dotenv/config';
import pg from 'pg';
const { Client } = pg;

// ─── 신규 추가 핀 ───
const pins: Array<{ name: string; slug: string; lat: number; lng: number }> = [
  { name: '김포 고촌역', slug: 'gimpo-gochon-station', lat: 37.6037, lng: 126.7724 },
  { name: '고양시청', slug: 'goyang-city', lat: 37.6584, lng: 126.8320 },
  { name: '구리역', slug: 'guri-station', lat: 37.5944, lng: 127.1392 },
  { name: '하남 스타필드', slug: 'hanam-starfield', lat: 37.5429, lng: 127.2247 },
  { name: '청라 호수공원', slug: 'cheongna-lakepark', lat: 37.5360, lng: 126.6440 },
  { name: '강화군청', slug: 'ganghwa-county', lat: 37.7470, lng: 126.4882 },
  { name: '인제군청', slug: 'inje-county', lat: 38.0697, lng: 128.1700 },
  { name: '양구 종합운동장', slug: 'yanggu-sports-complex', lat: 38.1100, lng: 127.9886 },
  { name: '공주국립대학교', slug: 'kongju-national-univ', lat: 36.4710, lng: 127.1450 },
  { name: '고흥 녹동 여객선터미널', slug: 'goheung-nokdong-terminal', lat: 34.5239, lng: 127.1334 },
  { name: '평창 버스터미널', slug: 'pyeongchang-bus-terminal', lat: 37.3711, lng: 128.3902 },
  { name: '여주시청', slug: 'yeoju-city', lat: 37.2984, lng: 127.6371 },
  { name: '모란역', slug: 'moran-station', lat: 37.4334, lng: 127.1290 },
  { name: '죽전역', slug: 'jukjeon-station', lat: 37.3284, lng: 127.1066 },
  { name: '영통역', slug: 'yeongtong-station', lat: 37.2519, lng: 127.0716 },
];

async function main() {
  // URL 파싱 시 비밀번호의 특수문자(!) 인코딩 이슈를 피하기 위해 명시적 설정 사용
  const dbUrl = new URL(process.env.DATABASE_URL!);
  const client = new Client({
    host: dbUrl.hostname,
    port: dbUrl.port ? Number(dbUrl.port) : 5432,
    user: decodeURIComponent(dbUrl.username),
    password: decodeURIComponent(dbUrl.password),
    database: dbUrl.pathname.replace(/^\//, ''),
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();

  // ── 1) 송도 센트럴파크 중복 제거 (incheon-songdo, songdo-central) ──
  // 둘 다 유저/매치/랭킹 참조 0건이므로 더 명확한 한글명 'songdo-central'을 유지하고
  // 'incheon-songdo'를 제거. 만약 어느 쪽이라도 참조가 생겼다면 안전하게 스킵.
  const refCheck = await client.query(
    `SELECT p.id, p.slug,
            COALESCE((SELECT COUNT(*) FROM ranking_entries WHERE pin_id = p.id), 0) AS ranks,
            COALESCE((SELECT COUNT(*) FROM matches WHERE pin_id = p.id), 0) AS matches,
            COALESCE((SELECT COUNT(*) FROM user_pins WHERE pin_id = p.id), 0) AS user_pins
     FROM pins p WHERE p.slug IN ('incheon-songdo', 'songdo-central')`,
  );
  const dup = refCheck.rows.find((r: any) => r.slug === 'incheon-songdo');
  if (dup) {
    const totalRefs = Number(dup.ranks) + Number(dup.matches) + Number(dup.user_pins);
    if (totalRefs === 0) {
      await client.query(`DELETE FROM pins WHERE id = $1`, [dup.id]);
      console.log('중복 핀 삭제: 송도 센트럴파크 (incheon-songdo)');
    } else {
      console.log(`송도 중복 핀 참조 ${totalRefs}건 — 수동 병합 필요`);
    }
  }

  // ── 2) 신규 핀 추가 ──
  let created = 0;
  let skipped = 0;
  for (const pin of pins) {
    const res = await client.query(
      `INSERT INTO pins (id, name, slug, center, level, is_active, user_count, metadata, created_at)
       VALUES (gen_random_uuid(), $1, $2, ST_GeogFromText($3), 'DONG', true, 0, '{}', now())
       ON CONFLICT (slug) DO NOTHING RETURNING id`,
      [pin.name, pin.slug, `POINT(${pin.lng} ${pin.lat})`],
    );
    if (res.rowCount && res.rowCount > 0) {
      created++;
      console.log(`  + ${pin.name}`);
    } else {
      skipped++;
      console.log(`  · ${pin.name} (이미 존재)`);
    }
  }

  console.log(`\n신규 추가: ${created}개, 스킵: ${skipped}개`);
  const total = await client.query("SELECT COUNT(*) FROM pins WHERE level = 'DONG'");
  console.log(`전체 DONG 핀: ${total.rows[0].count}개`);
  await client.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
