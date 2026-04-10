/**
 * 핀(Pin) 시드 데이터 스크립트
 * 실행: npx tsx prisma/seed-pins.ts
 */

import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const c = {
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  red:   (s: string) => `\x1b[31m${s}\x1b[0m`,
  blue:  (s: string) => `\x1b[34m${s}\x1b[0m`,
  yellow:(s: string) => `\x1b[33m${s}\x1b[0m`,
  bold:  (s: string) => `\x1b[1m${s}\x1b[0m`,
};

// ─────────────────────────────────────
// 핀 데이터 정의
// ─────────────────────────────────────

interface PinData {
  name: string;
  slug: string;
  lat: number;
  lng: number;
  level: 'DONG' | 'GU' | 'CITY' | 'PROVINCE';
  parentSlug?: string;
  regionCode?: string;
}

// ── 광역시/도 (CITY 레벨) ──
const CITY_PINS: PinData[] = [
  { name: '서울특별시', slug: 'seoul', lat: 37.5665, lng: 126.9780, level: 'CITY' },
  { name: '부산광역시', slug: 'busan', lat: 35.1796, lng: 129.0756, level: 'CITY' },
  { name: '대구광역시', slug: 'daegu', lat: 35.8714, lng: 128.6014, level: 'CITY' },
  { name: '인천광역시', slug: 'incheon', lat: 37.4563, lng: 126.7052, level: 'CITY' },
  { name: '광주광역시', slug: 'gwangju', lat: 35.1595, lng: 126.8526, level: 'CITY' },
  { name: '대전광역시', slug: 'daejeon', lat: 36.3504, lng: 127.3845, level: 'CITY' },
  { name: '울산광역시', slug: 'ulsan', lat: 35.5384, lng: 129.3114, level: 'CITY' },
  { name: '세종특별자치시', slug: 'sejong', lat: 36.4800, lng: 127.0000, level: 'CITY' },
  { name: '경기도', slug: 'gyeonggi', lat: 37.4138, lng: 127.5183, level: 'CITY' },
  { name: '제주특별자치도', slug: 'jeju', lat: 33.4996, lng: 126.5312, level: 'CITY' },
];

// ── 서울 구 (GU 레벨) ──
const SEOUL_GU_PINS: PinData[] = [
  { name: '강남구', slug: 'gangnam-gu', lat: 37.5172, lng: 127.0473, level: 'GU', parentSlug: 'seoul' },
  { name: '강동구', slug: 'gangdong-gu', lat: 37.5301, lng: 127.1238, level: 'GU', parentSlug: 'seoul' },
  { name: '강북구', slug: 'gangbuk-gu', lat: 37.6396, lng: 127.0257, level: 'GU', parentSlug: 'seoul' },
  { name: '강서구', slug: 'gangseo-gu', lat: 37.5510, lng: 126.8495, level: 'GU', parentSlug: 'seoul' },
  { name: '관악구', slug: 'gwanak-gu', lat: 37.4784, lng: 126.9516, level: 'GU', parentSlug: 'seoul' },
  { name: '광진구', slug: 'gwangjin-gu', lat: 37.5384, lng: 127.0822, level: 'GU', parentSlug: 'seoul' },
  { name: '구로구', slug: 'guro-gu', lat: 37.4954, lng: 126.8874, level: 'GU', parentSlug: 'seoul' },
  { name: '금천구', slug: 'geumcheon-gu', lat: 37.4519, lng: 126.9020, level: 'GU', parentSlug: 'seoul' },
  { name: '노원구', slug: 'nowon-gu', lat: 37.6542, lng: 127.0568, level: 'GU', parentSlug: 'seoul' },
  { name: '도봉구', slug: 'dobong-gu', lat: 37.6688, lng: 127.0471, level: 'GU', parentSlug: 'seoul' },
  { name: '동대문구', slug: 'dongdaemun-gu', lat: 37.5744, lng: 127.0400, level: 'GU', parentSlug: 'seoul' },
  { name: '동작구', slug: 'dongjak-gu', lat: 37.5124, lng: 126.9393, level: 'GU', parentSlug: 'seoul' },
  { name: '마포구', slug: 'mapo-gu', lat: 37.5663, lng: 126.9014, level: 'GU', parentSlug: 'seoul' },
  { name: '서대문구', slug: 'seodaemun-gu', lat: 37.5791, lng: 126.9368, level: 'GU', parentSlug: 'seoul' },
  { name: '서초구', slug: 'seocho-gu', lat: 37.4837, lng: 127.0324, level: 'GU', parentSlug: 'seoul' },
  { name: '성동구', slug: 'seongdong-gu', lat: 37.5634, lng: 127.0370, level: 'GU', parentSlug: 'seoul' },
  { name: '성북구', slug: 'seongbuk-gu', lat: 37.5894, lng: 127.0167, level: 'GU', parentSlug: 'seoul' },
  { name: '송파구', slug: 'songpa-gu', lat: 37.5145, lng: 127.1059, level: 'GU', parentSlug: 'seoul' },
  { name: '양천구', slug: 'yangcheon-gu', lat: 37.5170, lng: 126.8664, level: 'GU', parentSlug: 'seoul' },
  { name: '영등포구', slug: 'yeongdeungpo-gu', lat: 37.5264, lng: 126.8963, level: 'GU', parentSlug: 'seoul' },
  { name: '용산구', slug: 'yongsan-gu', lat: 37.5324, lng: 126.9907, level: 'GU', parentSlug: 'seoul' },
  { name: '은평구', slug: 'eunpyeong-gu', lat: 37.6027, lng: 126.9291, level: 'GU', parentSlug: 'seoul' },
  { name: '종로구', slug: 'jongno-gu', lat: 37.5735, lng: 126.9790, level: 'GU', parentSlug: 'seoul' },
  { name: '중구', slug: 'jung-gu', lat: 37.5636, lng: 126.9976, level: 'GU', parentSlug: 'seoul' },
  { name: '중랑구', slug: 'jungnang-gu', lat: 37.6066, lng: 127.0927, level: 'GU', parentSlug: 'seoul' },
];

// ── 서울 핫스팟 (DONG 레벨) ──
const SEOUL_HOTSPOT_PINS: PinData[] = [
  // 강남구
  { name: '강남역', slug: 'gangnam-station', lat: 37.4979, lng: 127.0276, level: 'DONG', parentSlug: 'gangnam-gu' },
  { name: '삼성역(코엑스)', slug: 'samsung-coex', lat: 37.5088, lng: 127.0631, level: 'DONG', parentSlug: 'gangnam-gu' },
  // 강동구
  { name: '천호역', slug: 'cheonho-station', lat: 37.5383, lng: 127.1239, level: 'DONG', parentSlug: 'gangdong-gu' },
  // 강북구
  { name: '수유역', slug: 'suyu-station', lat: 37.6380, lng: 127.0254, level: 'DONG', parentSlug: 'gangbuk-gu' },
  // 강서구
  { name: '발산역(마곡)', slug: 'balsan-magok', lat: 37.5585, lng: 126.8387, level: 'DONG', parentSlug: 'gangseo-gu' },
  // 관악구
  { name: '서울대입구역', slug: 'snu-station', lat: 37.4812, lng: 126.9527, level: 'DONG', parentSlug: 'gwanak-gu' },
  // 광진구
  { name: '건대입구역', slug: 'konkuk-station', lat: 37.5404, lng: 127.0696, level: 'DONG', parentSlug: 'gwangjin-gu' },
  // 구로구
  { name: '구로디지털단지역', slug: 'guro-digital', lat: 37.4854, lng: 126.9015, level: 'DONG', parentSlug: 'guro-gu' },
  // 금천구
  { name: '가산디지털단지역', slug: 'gasan-digital', lat: 37.4813, lng: 126.8828, level: 'DONG', parentSlug: 'geumcheon-gu' },
  // 노원구
  { name: '노원역', slug: 'nowon-station', lat: 37.6554, lng: 127.0614, level: 'DONG', parentSlug: 'nowon-gu' },
  // 도봉구
  { name: '쌍문역', slug: 'ssangmun-station', lat: 37.6484, lng: 127.0341, level: 'DONG', parentSlug: 'dobong-gu' },
  // 동대문구
  { name: '청량리역', slug: 'cheongnyangni-station', lat: 37.5802, lng: 127.0470, level: 'DONG', parentSlug: 'dongdaemun-gu' },
  // 동작구
  { name: '사당역', slug: 'sadang-station', lat: 37.4764, lng: 126.9816, level: 'DONG', parentSlug: 'dongjak-gu' },
  // 마포구
  { name: '홍대입구역', slug: 'hongdae-station', lat: 37.5571, lng: 126.9245, level: 'DONG', parentSlug: 'mapo-gu' },
  { name: '여의나루역', slug: 'yeouinaru-station', lat: 37.5270, lng: 126.9326, level: 'DONG', parentSlug: 'mapo-gu' },
  // 서대문구
  { name: '신촌역', slug: 'sinchon-station', lat: 37.5553, lng: 126.9368, level: 'DONG', parentSlug: 'seodaemun-gu' },
  // 서초구
  { name: '서초역', slug: 'seocho-station', lat: 37.4919, lng: 127.0078, level: 'DONG', parentSlug: 'seocho-gu' },
  { name: '교대역', slug: 'gyodae-station', lat: 37.4937, lng: 127.0145, level: 'DONG', parentSlug: 'seocho-gu' },
  // 성동구
  { name: '왕십리역', slug: 'wangsimni-station', lat: 37.5614, lng: 127.0370, level: 'DONG', parentSlug: 'seongdong-gu' },
  { name: '성수역', slug: 'seongsu-station', lat: 37.5446, lng: 127.0558, level: 'DONG', parentSlug: 'seongdong-gu' },
  // 성북구
  { name: '고려대역', slug: 'korea-univ-station', lat: 37.5863, lng: 127.0258, level: 'DONG', parentSlug: 'seongbuk-gu' },
  // 송파구
  { name: '잠실역', slug: 'jamsil-station', lat: 37.5133, lng: 127.1001, level: 'DONG', parentSlug: 'songpa-gu' },
  { name: '석촌역', slug: 'seokchon-station', lat: 37.5057, lng: 127.1009, level: 'DONG', parentSlug: 'songpa-gu' },
  // 양천구
  { name: '목동역', slug: 'mokdong-station', lat: 37.5250, lng: 126.8757, level: 'DONG', parentSlug: 'yangcheon-gu' },
  // 영등포구
  { name: '영등포역', slug: 'yeongdeungpo-station', lat: 37.5158, lng: 126.9074, level: 'DONG', parentSlug: 'yeongdeungpo-gu' },
  { name: '여의도역', slug: 'yeouido-station', lat: 37.5216, lng: 126.9243, level: 'DONG', parentSlug: 'yeongdeungpo-gu' },
  // 용산구
  { name: '이태원역', slug: 'itaewon-station', lat: 37.5346, lng: 126.9943, level: 'DONG', parentSlug: 'yongsan-gu' },
  { name: '용산역', slug: 'yongsan-station', lat: 37.5299, lng: 126.9645, level: 'DONG', parentSlug: 'yongsan-gu' },
  // 은평구
  { name: '연신내역', slug: 'yeonsinnae-station', lat: 37.6195, lng: 126.9210, level: 'DONG', parentSlug: 'eunpyeong-gu' },
  // 종로구
  { name: '종각역', slug: 'jonggak-station', lat: 37.5701, lng: 126.9828, level: 'DONG', parentSlug: 'jongno-gu' },
  { name: '광화문역', slug: 'gwanghwamun-station', lat: 37.5718, lng: 126.9769, level: 'DONG', parentSlug: 'jongno-gu' },
  // 중구
  { name: '명동역', slug: 'myeongdong-station', lat: 37.5608, lng: 126.9860, level: 'DONG', parentSlug: 'jung-gu' },
  { name: '서울역', slug: 'seoul-station', lat: 37.5547, lng: 126.9707, level: 'DONG', parentSlug: 'jung-gu' },
  // 중랑구
  { name: '중랑역', slug: 'jungnang-station', lat: 37.5967, lng: 127.0849, level: 'DONG', parentSlug: 'jungnang-gu' },
];

// ── 수도권 핫스팟 (DONG 레벨) ──
const METRO_PINS: PinData[] = [
  { name: '수원역', slug: 'suwon-station', lat: 37.2664, lng: 127.0000, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '인계동(로데오)', slug: 'suwon-rodeo', lat: 37.2654, lng: 127.0330, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '야탑역', slug: 'yatap-station', lat: 37.4112, lng: 127.1276, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '판교역', slug: 'pangyo-station', lat: 37.3948, lng: 127.1112, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '일산(마두역)', slug: 'ilsan-madu', lat: 37.6530, lng: 126.7693, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '수지(성복역)', slug: 'suji-seongbok', lat: 37.3219, lng: 127.0785, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '부천역', slug: 'bucheon-station', lat: 37.4837, lng: 126.7838, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '안산중앙역', slug: 'ansan-jungang', lat: 37.3185, lng: 126.8328, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '안양역', slug: 'anyang-station', lat: 37.4017, lng: 126.9234, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '동탄역', slug: 'dongtan-station', lat: 37.2003, lng: 127.0975, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '평택역', slug: 'pyeongtaek-station', lat: 36.9910, lng: 127.0858, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '의정부역', slug: 'uijeongbu-station', lat: 37.7383, lng: 127.0458, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '운정역', slug: 'unjeong-station', lat: 37.7149, lng: 126.7374, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '광명역(KTX)', slug: 'gwangmyeong-ktx', lat: 37.4165, lng: 126.8845, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '미사역', slug: 'misa-station', lat: 37.5600, lng: 127.1901, level: 'DONG', parentSlug: 'gyeonggi' },
  { name: '구리역', slug: 'guri-station', lat: 37.5997, lng: 127.1413, level: 'DONG', parentSlug: 'gyeonggi' },
];

// ── 광역시/주요도시 핫스팟 ──
const REGIONAL_PINS: PinData[] = [
  // 인천
  { name: '부평역', slug: 'bupyeong-station', lat: 37.4897, lng: 126.7231, level: 'DONG', parentSlug: 'incheon' },
  { name: '송도(센트럴파크)', slug: 'songdo-central', lat: 37.3815, lng: 126.6610, level: 'DONG', parentSlug: 'incheon' },
  // 부산
  { name: '서면역', slug: 'seomyeon-station', lat: 35.1579, lng: 129.0589, level: 'DONG', parentSlug: 'busan' },
  { name: '해운대역', slug: 'haeundae-station', lat: 35.1631, lng: 129.1639, level: 'DONG', parentSlug: 'busan' },
  { name: '부산역', slug: 'busan-station', lat: 35.1152, lng: 129.0405, level: 'DONG', parentSlug: 'busan' },
  // 대구
  { name: '동성로(중앙로역)', slug: 'daegu-dongseongro', lat: 35.8668, lng: 128.5936, level: 'DONG', parentSlug: 'daegu' },
  { name: '반월당역', slug: 'banwoldang-station', lat: 35.8577, lng: 128.5932, level: 'DONG', parentSlug: 'daegu' },
  // 대전
  { name: '대전역', slug: 'daejeon-station', lat: 36.3323, lng: 127.4346, level: 'DONG', parentSlug: 'daejeon' },
  { name: '둔산(시청역)', slug: 'daejeon-dunsan', lat: 36.3521, lng: 127.3848, level: 'DONG', parentSlug: 'daejeon' },
  // 광주
  { name: '충장로(금남로역)', slug: 'gwangju-chungjangro', lat: 35.1536, lng: 126.9138, level: 'DONG', parentSlug: 'gwangju' },
  { name: '상무지구', slug: 'gwangju-sangmu', lat: 35.1502, lng: 126.8516, level: 'DONG', parentSlug: 'gwangju' },
  // 울산
  { name: '울산역(KTX)', slug: 'ulsan-ktx', lat: 35.5544, lng: 129.3268, level: 'DONG', parentSlug: 'ulsan' },
  { name: '삼산동', slug: 'ulsan-samsan', lat: 35.5378, lng: 129.3362, level: 'DONG', parentSlug: 'ulsan' },
  // 세종
  { name: '정부세종청사', slug: 'sejong-gov', lat: 36.4998, lng: 127.0000, level: 'DONG', parentSlug: 'sejong' },
  // 제주
  { name: '제주시(연동)', slug: 'jeju-yeon', lat: 33.4996, lng: 126.5312, level: 'DONG', parentSlug: 'jeju' },
  { name: '서귀포시', slug: 'seogwipo', lat: 33.2538, lng: 126.5599, level: 'DONG', parentSlug: 'jeju' },
];

// ─────────────────────────────────────
// 시드 실행
// ─────────────────────────────────────

async function seedPins(): Promise<void> {
  console.log(c.bold(c.blue('\n=========================================')));
  console.log(c.bold(c.blue('   핀(Pin) 시드 스크립트 시작')));
  console.log(c.bold(c.blue('=========================================\n')));

  // 기존 핀 개수 확인
  const existingCount = await prisma.pin.count();
  if (existingCount > 0) {
    console.log(c.yellow(`[WARN] 기존 핀 ${existingCount}개 존재. 중복 slug는 건너뜁니다.`));
  }

  const allPins = [...CITY_PINS, ...SEOUL_GU_PINS, ...SEOUL_HOTSPOT_PINS, ...METRO_PINS, ...REGIONAL_PINS];
  let created = 0;
  let skipped = 0;

  // 1단계: CITY → GU → DONG 순으로 생성 (부모-자식 관계)
  const slugToId: Record<string, string> = {};

  for (const level of ['CITY', 'GU', 'DONG'] as const) {
    const pinsForLevel = allPins.filter(p => p.level === level);

    for (const pin of pinsForLevel) {
      // 중복 체크
      const existing = await prisma.pin.findUnique({ where: { slug: pin.slug } });
      if (existing) {
        slugToId[pin.slug] = existing.id;
        skipped++;
        continue;
      }

      // 부모 핀 ID 조회
      let parentPinId: string | null = null;
      if (pin.parentSlug && slugToId[pin.parentSlug]) {
        parentPinId = slugToId[pin.parentSlug];
      }

      try {
        // PostGIS POINT 생성을 위해 raw query 사용
        const result = await prisma.$queryRaw<{ id: string }[]>`
          INSERT INTO pins (id, name, slug, center, level, parent_pin_id, is_active, user_count, metadata, created_at)
          VALUES (
            gen_random_uuid(),
            ${pin.name},
            ${pin.slug},
            ST_GeogFromText(${`POINT(${pin.lng} ${pin.lat})`}),
            ${pin.level}::"PinLevel",
            ${parentPinId}::uuid,
            true,
            0,
            '{}',
            now()
          )
          RETURNING id
        `;

        slugToId[pin.slug] = result[0].id;
        created++;

        if (created % 10 === 0) {
          console.log(c.green(`[PASS] ${created}개 생성 완료 (최근: ${pin.name})`));
        }
      } catch (err) {
        console.error(c.red(`[FAIL] ${pin.name} (${pin.slug}) 생성 실패:`), err);
      }
    }
  }

  console.log(c.bold(c.green(`\n[DONE] 핀 시드 완료`)));
  console.log(`  생성: ${created}개`);
  console.log(`  건너뜀 (이미 존재): ${skipped}개`);
  console.log(`  총: ${created + skipped}개`);

  // 통계
  const stats = {
    CITY: allPins.filter(p => p.level === 'CITY').length,
    GU: allPins.filter(p => p.level === 'GU').length,
    DONG: allPins.filter(p => p.level === 'DONG').length,
  };
  console.log(c.bold('\n[레벨별 분포]'));
  console.log(`  CITY: ${stats.CITY}개`);
  console.log(`  GU: ${stats.GU}개`);
  console.log(`  DONG: ${stats.DONG}개`);
}

async function main() {
  try {
    await seedPins();
  } catch (err) {
    console.error(c.red('[ERROR] 시드 실패:'), err);
    process.exit(1);
  } finally {
    await prisma.$disconnect();
  }
}

main();
