import 'dotenv/config';
import pg from 'pg';
const { Client } = pg;

const pins = [
  { name: '창원역', slug: 'changwon-station', lat: 35.2270, lng: 128.6895 },
  { name: '김해시청', slug: 'gimhae-city', lat: 35.2285, lng: 128.8894 },
  { name: '천안역', slug: 'cheonan-station', lat: 36.8108, lng: 127.1487 },
  { name: '청주시청', slug: 'cheongju-city', lat: 36.6356, lng: 127.4914 },
  { name: '전주 객사', slug: 'jeonju-gaeksa', lat: 35.8175, lng: 127.1474 },
  { name: '포항역', slug: 'pohang-station', lat: 35.9901, lng: 129.3445 },
  { name: '원주역', slug: 'wonju-station', lat: 37.3264, lng: 127.9466 },
  { name: '춘천역', slug: 'chuncheon-station', lat: 37.8852, lng: 127.7181 },
  { name: '여수엑스포역', slug: 'yeosu-expo', lat: 34.7433, lng: 127.7410 },
  { name: '속초 해수욕장', slug: 'sokcho-beach', lat: 38.1900, lng: 128.5930 },
  { name: '강릉역', slug: 'gangneung-station', lat: 37.7643, lng: 128.8961 },
  { name: '목포역', slug: 'mokpo-station', lat: 34.7907, lng: 126.3883 },
  { name: '순천역', slug: 'suncheon-station', lat: 34.9506, lng: 127.4872 },
  { name: '구미역', slug: 'gumi-station', lat: 36.1190, lng: 128.3290 },
  { name: '경주역', slug: 'gyeongju-station', lat: 35.8422, lng: 129.2153 },
  { name: '안동역', slug: 'andong-station', lat: 36.5684, lng: 128.7268 },
  { name: '제천역', slug: 'jecheon-station', lat: 37.1327, lng: 128.2120 },
  { name: '충주역', slug: 'chungju-station', lat: 36.9699, lng: 127.9321 },
  { name: '익산역', slug: 'iksan-station', lat: 35.9533, lng: 126.9562 },
  { name: '군산역', slug: 'gunsan-station', lat: 35.9673, lng: 126.7369 },
  { name: '진주역', slug: 'jinju-station', lat: 35.1619, lng: 128.1002 },
  { name: '거제 옥포', slug: 'geoje-okpo', lat: 34.8934, lng: 128.6880 },
  { name: '양산역', slug: 'yangsan-station', lat: 35.3357, lng: 129.0206 },
  { name: '아산역', slug: 'asan-station', lat: 36.7892, lng: 127.0075 },
];

async function main() {
  const url = process.env.DATABASE_URL!.replace(/\?.*$/, '');
  const client = new Client({ connectionString: url });
  await client.connect();
  let created = 0;
  for (const pin of pins) {
    const res = await client.query(
      `INSERT INTO pins (id, name, slug, center, level, is_active, user_count, metadata, created_at)
       VALUES (gen_random_uuid(), $1, $2, ST_GeogFromText($3), 'DONG', true, 0, '{}', now())
       ON CONFLICT (slug) DO NOTHING RETURNING id`,
      [pin.name, pin.slug, `POINT(${pin.lng} ${pin.lat})`]
    );
    if (res.rowCount && res.rowCount > 0) created++;
  }
  console.log(`추가: ${created}개`);
  const total = await client.query("SELECT count(*) FROM pins WHERE level = 'DONG'");
  console.log(`전체 DONG 핀: ${total.rows[0].count}개`);
  await client.end();
}
main();
