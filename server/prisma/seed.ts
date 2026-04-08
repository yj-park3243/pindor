import { PrismaClient, PinLevel } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.info('Seeding database...');

  // ─────────────────────────────────────
  // 전국 핀 데이터 (서울 25구 + 수도권 + 광역시)
  // ─────────────────────────────────────

  const allPins = [
    // ===== 서울특별시 25개 구 (GU 레벨) =====
    { name: '강남구', slug: 'seoul-gangnam-gu', lat: 37.5172, lng: 127.0473, level: 'GU' as PinLevel, regionCode: '11680' },
    { name: '강동구', slug: 'seoul-gangdong-gu', lat: 37.5301, lng: 127.1238, level: 'GU' as PinLevel, regionCode: '11740' },
    { name: '강북구', slug: 'seoul-gangbuk-gu', lat: 37.6396, lng: 127.0255, level: 'GU' as PinLevel, regionCode: '11305' },
    { name: '강서구', slug: 'seoul-gangseo-gu', lat: 37.5510, lng: 126.8495, level: 'GU' as PinLevel, regionCode: '11500' },
    { name: '관악구', slug: 'seoul-gwanak-gu', lat: 37.4784, lng: 126.9516, level: 'GU' as PinLevel, regionCode: '11620' },
    { name: '광진구', slug: 'seoul-gwangjin-gu', lat: 37.5385, lng: 127.0823, level: 'GU' as PinLevel, regionCode: '11215' },
    { name: '구로구', slug: 'seoul-guro-gu', lat: 37.4954, lng: 126.8874, level: 'GU' as PinLevel, regionCode: '11530' },
    { name: '금천구', slug: 'seoul-geumcheon-gu', lat: 37.4569, lng: 126.8955, level: 'GU' as PinLevel, regionCode: '11545' },
    { name: '노원구', slug: 'seoul-nowon-gu', lat: 37.6542, lng: 127.0568, level: 'GU' as PinLevel, regionCode: '11350' },
    { name: '도봉구', slug: 'seoul-dobong-gu', lat: 37.6688, lng: 127.0471, level: 'GU' as PinLevel, regionCode: '11320' },
    { name: '동대문구', slug: 'seoul-dongdaemun-gu', lat: 37.5744, lng: 127.0400, level: 'GU' as PinLevel, regionCode: '11230' },
    { name: '동작구', slug: 'seoul-dongjak-gu', lat: 37.5124, lng: 126.9393, level: 'GU' as PinLevel, regionCode: '11590' },
    { name: '마포구', slug: 'seoul-mapo-gu', lat: 37.5663, lng: 126.9014, level: 'GU' as PinLevel, regionCode: '11440' },
    { name: '서대문구', slug: 'seoul-seodaemun-gu', lat: 37.5791, lng: 126.9368, level: 'GU' as PinLevel, regionCode: '11410' },
    { name: '서초구', slug: 'seoul-seocho-gu', lat: 37.4837, lng: 127.0324, level: 'GU' as PinLevel, regionCode: '11650' },
    { name: '성동구', slug: 'seoul-seongdong-gu', lat: 37.5634, lng: 127.0369, level: 'GU' as PinLevel, regionCode: '11200' },
    { name: '성북구', slug: 'seoul-seongbuk-gu', lat: 37.5894, lng: 127.0167, level: 'GU' as PinLevel, regionCode: '11290' },
    { name: '송파구', slug: 'seoul-songpa-gu', lat: 37.5148, lng: 127.1059, level: 'GU' as PinLevel, regionCode: '11710' },
    { name: '양천구', slug: 'seoul-yangcheon-gu', lat: 37.5170, lng: 126.8667, level: 'GU' as PinLevel, regionCode: '11470' },
    { name: '영등포구', slug: 'seoul-yeongdeungpo-gu', lat: 37.5264, lng: 126.8963, level: 'GU' as PinLevel, regionCode: '11560' },
    { name: '용산구', slug: 'seoul-yongsan-gu', lat: 37.5324, lng: 126.9906, level: 'GU' as PinLevel, regionCode: '11170' },
    { name: '은평구', slug: 'seoul-eunpyeong-gu', lat: 37.6027, lng: 126.9291, level: 'GU' as PinLevel, regionCode: '11380' },
    { name: '종로구', slug: 'seoul-jongno-gu', lat: 37.5735, lng: 126.9790, level: 'GU' as PinLevel, regionCode: '11110' },
    { name: '중구', slug: 'seoul-jung-gu', lat: 37.5641, lng: 126.9979, level: 'GU' as PinLevel, regionCode: '11140' },
    { name: '중랑구', slug: 'seoul-jungnang-gu', lat: 37.6066, lng: 127.0928, level: 'GU' as PinLevel, regionCode: '11260' },

    // ===== 서울 주요 핫스팟 (DONG 레벨) =====
    // 강남구
    { name: '강남역', slug: 'seoul-gangnam-gangnam-station', lat: 37.4979, lng: 127.0276, level: 'DONG' as PinLevel, regionCode: '1168010100', parentSlug: 'seoul-gangnam-gu' },
    { name: '삼성역 코엑스', slug: 'seoul-gangnam-coex', lat: 37.5120, lng: 127.0590, level: 'DONG' as PinLevel, regionCode: '1168010700', parentSlug: 'seoul-gangnam-gu' },
    { name: '압구정 로데오', slug: 'seoul-gangnam-apgujeong', lat: 37.5272, lng: 127.0403, level: 'DONG' as PinLevel, regionCode: '1168010500', parentSlug: 'seoul-gangnam-gu' },
    // 강동구
    { name: '천호역', slug: 'seoul-gangdong-cheonho', lat: 37.5388, lng: 127.1237, level: 'DONG' as PinLevel, regionCode: '1174010100', parentSlug: 'seoul-gangdong-gu' },
    { name: '강일동 미사', slug: 'seoul-gangdong-misa', lat: 37.5572, lng: 127.1750, level: 'DONG' as PinLevel, regionCode: '1174010800', parentSlug: 'seoul-gangdong-gu' },
    // 강북구
    { name: '수유역', slug: 'seoul-gangbuk-suyu', lat: 37.6380, lng: 127.0254, level: 'DONG' as PinLevel, regionCode: '1130510100', parentSlug: 'seoul-gangbuk-gu' },
    // 강서구
    { name: '발산역', slug: 'seoul-gangseo-balsan', lat: 37.5584, lng: 126.8389, level: 'DONG' as PinLevel, regionCode: '1150010100', parentSlug: 'seoul-gangseo-gu' },
    { name: '마곡나루역', slug: 'seoul-gangseo-magok', lat: 37.5672, lng: 126.8275, level: 'DONG' as PinLevel, regionCode: '1150010600', parentSlug: 'seoul-gangseo-gu' },
    // 관악구
    { name: '서울대입구역', slug: 'seoul-gwanak-snu-station', lat: 37.4812, lng: 126.9528, level: 'DONG' as PinLevel, regionCode: '1162010100', parentSlug: 'seoul-gwanak-gu' },
    { name: '신림역', slug: 'seoul-gwanak-sillim', lat: 37.4841, lng: 126.9296, level: 'DONG' as PinLevel, regionCode: '1162010200', parentSlug: 'seoul-gwanak-gu' },
    // 광진구
    { name: '건대입구역', slug: 'seoul-gwangjin-konkuk', lat: 37.5404, lng: 127.0693, level: 'DONG' as PinLevel, regionCode: '1121510100', parentSlug: 'seoul-gwangjin-gu' },
    { name: '뚝섬역', slug: 'seoul-gwangjin-ttukseom', lat: 37.5315, lng: 127.0472, level: 'DONG' as PinLevel, regionCode: '1121510200', parentSlug: 'seoul-gwangjin-gu' },
    // 구로구
    { name: '구로디지털단지역', slug: 'seoul-guro-digital', lat: 37.4851, lng: 126.9015, level: 'DONG' as PinLevel, regionCode: '1153010100', parentSlug: 'seoul-guro-gu' },
    { name: '신도림역', slug: 'seoul-guro-sindorim', lat: 37.5088, lng: 126.8914, level: 'DONG' as PinLevel, regionCode: '1153010400', parentSlug: 'seoul-guro-gu' },
    // 금천구
    { name: '가산디지털단지역', slug: 'seoul-geumcheon-gasan', lat: 37.4816, lng: 126.8827, level: 'DONG' as PinLevel, regionCode: '1154510100', parentSlug: 'seoul-geumcheon-gu' },
    // 노원구
    { name: '노원역', slug: 'seoul-nowon-nowon-station', lat: 37.6555, lng: 127.0612, level: 'DONG' as PinLevel, regionCode: '1135010100', parentSlug: 'seoul-nowon-gu' },
    // 도봉구
    { name: '쌍문역', slug: 'seoul-dobong-ssangmun', lat: 37.6484, lng: 127.0345, level: 'DONG' as PinLevel, regionCode: '1132010100', parentSlug: 'seoul-dobong-gu' },
    // 동대문구
    { name: '청량리역', slug: 'seoul-dongdaemun-cheongnyangni', lat: 37.5806, lng: 127.0470, level: 'DONG' as PinLevel, regionCode: '1123010100', parentSlug: 'seoul-dongdaemun-gu' },
    { name: '회기역', slug: 'seoul-dongdaemun-hoegi', lat: 37.5894, lng: 127.0578, level: 'DONG' as PinLevel, regionCode: '1123010200', parentSlug: 'seoul-dongdaemun-gu' },
    // 동작구
    { name: '사당역', slug: 'seoul-dongjak-sadang', lat: 37.4765, lng: 126.9816, level: 'DONG' as PinLevel, regionCode: '1159010100', parentSlug: 'seoul-dongjak-gu' },
    { name: '노량진역', slug: 'seoul-dongjak-noryangjin', lat: 37.5134, lng: 126.9425, level: 'DONG' as PinLevel, regionCode: '1159010200', parentSlug: 'seoul-dongjak-gu' },
    // 마포구
    { name: '홍대입구역', slug: 'seoul-mapo-hongdae', lat: 37.5568, lng: 126.9237, level: 'DONG' as PinLevel, regionCode: '1144010100', parentSlug: 'seoul-mapo-gu' },
    { name: '상암 디지털미디어시티', slug: 'seoul-mapo-sangam-dmc', lat: 37.5768, lng: 126.8909, level: 'DONG' as PinLevel, regionCode: '1144010200', parentSlug: 'seoul-mapo-gu' },
    // 서대문구
    { name: '신촌역', slug: 'seoul-seodaemun-sinchon', lat: 37.5550, lng: 126.9366, level: 'DONG' as PinLevel, regionCode: '1141010100', parentSlug: 'seoul-seodaemun-gu' },
    // 서초구
    { name: '교대역', slug: 'seoul-seocho-gyodae', lat: 37.4934, lng: 127.0146, level: 'DONG' as PinLevel, regionCode: '1165010100', parentSlug: 'seoul-seocho-gu' },
    { name: '고속터미널역', slug: 'seoul-seocho-express-terminal', lat: 37.5049, lng: 127.0050, level: 'DONG' as PinLevel, regionCode: '1165010300', parentSlug: 'seoul-seocho-gu' },
    // 성동구
    { name: '성수역', slug: 'seoul-seongdong-seongsu', lat: 37.5445, lng: 127.0557, level: 'DONG' as PinLevel, regionCode: '1120010100', parentSlug: 'seoul-seongdong-gu' },
    { name: '왕십리역', slug: 'seoul-seongdong-wangsimni', lat: 37.5614, lng: 127.0380, level: 'DONG' as PinLevel, regionCode: '1120010200', parentSlug: 'seoul-seongdong-gu' },
    // 성북구
    { name: '고려대역', slug: 'seoul-seongbuk-korea-univ', lat: 37.5903, lng: 127.0290, level: 'DONG' as PinLevel, regionCode: '1129010100', parentSlug: 'seoul-seongbuk-gu' },
    // 송파구
    { name: '잠실역', slug: 'seoul-songpa-jamsil', lat: 37.5133, lng: 127.1001, level: 'DONG' as PinLevel, regionCode: '1171010100', parentSlug: 'seoul-songpa-gu' },
    { name: '석촌호수', slug: 'seoul-songpa-seokchon', lat: 37.5052, lng: 127.1020, level: 'DONG' as PinLevel, regionCode: '1171010200', parentSlug: 'seoul-songpa-gu' },
    // 양천구
    { name: '목동역', slug: 'seoul-yangcheon-mokdong', lat: 37.5285, lng: 126.8657, level: 'DONG' as PinLevel, regionCode: '1147010100', parentSlug: 'seoul-yangcheon-gu' },
    // 영등포구
    { name: '여의도역', slug: 'seoul-yeongdeungpo-yeouido', lat: 37.5219, lng: 126.9245, level: 'DONG' as PinLevel, regionCode: '1156010100', parentSlug: 'seoul-yeongdeungpo-gu' },
    { name: '영등포역', slug: 'seoul-yeongdeungpo-station', lat: 37.5160, lng: 126.9074, level: 'DONG' as PinLevel, regionCode: '1156010200', parentSlug: 'seoul-yeongdeungpo-gu' },
    // 용산구
    { name: '이태원역', slug: 'seoul-yongsan-itaewon', lat: 37.5346, lng: 126.9946, level: 'DONG' as PinLevel, regionCode: '1117010100', parentSlug: 'seoul-yongsan-gu' },
    { name: '용산역', slug: 'seoul-yongsan-station', lat: 37.5299, lng: 126.9646, level: 'DONG' as PinLevel, regionCode: '1117010200', parentSlug: 'seoul-yongsan-gu' },
    // 은평구
    { name: '연신내역', slug: 'seoul-eunpyeong-yeonsinnae', lat: 37.6190, lng: 126.9208, level: 'DONG' as PinLevel, regionCode: '1138010100', parentSlug: 'seoul-eunpyeong-gu' },
    // 종로구
    { name: '종각역', slug: 'seoul-jongno-jonggak', lat: 37.5700, lng: 126.9832, level: 'DONG' as PinLevel, regionCode: '1111010100', parentSlug: 'seoul-jongno-gu' },
    { name: '광화문역', slug: 'seoul-jongno-gwanghwamun', lat: 37.5716, lng: 126.9769, level: 'DONG' as PinLevel, regionCode: '1111010200', parentSlug: 'seoul-jongno-gu' },
    // 중구
    { name: '명동역', slug: 'seoul-jung-myeongdong', lat: 37.5609, lng: 126.9860, level: 'DONG' as PinLevel, regionCode: '1114010100', parentSlug: 'seoul-jung-gu' },
    { name: '서울역', slug: 'seoul-jung-seoul-station', lat: 37.5547, lng: 126.9707, level: 'DONG' as PinLevel, regionCode: '1114010200', parentSlug: 'seoul-jung-gu' },
    { name: '동대문역사문화공원역', slug: 'seoul-jung-ddp', lat: 37.5654, lng: 127.0094, level: 'DONG' as PinLevel, regionCode: '1114010300', parentSlug: 'seoul-jung-gu' },
    // 중랑구
    { name: '상봉역', slug: 'seoul-jungnang-sangbong', lat: 37.5967, lng: 127.0858, level: 'DONG' as PinLevel, regionCode: '1126010100', parentSlug: 'seoul-jungnang-gu' },

    // ===== 경기도 주요 도시 (DONG 레벨) =====
    // 수원시
    { name: '수원역', slug: 'gyeonggi-suwon-station', lat: 37.2660, lng: 127.0015, level: 'DONG' as PinLevel, regionCode: '4111010100' },
    { name: '광교호수공원', slug: 'gyeonggi-suwon-gwanggyo', lat: 37.2857, lng: 127.0516, level: 'DONG' as PinLevel, regionCode: '4111010200' },
    // 성남시
    { name: '판교역', slug: 'gyeonggi-seongnam-pangyo', lat: 37.3948, lng: 127.1112, level: 'DONG' as PinLevel, regionCode: '4113510100' },
    { name: '서현역', slug: 'gyeonggi-seongnam-seohyeon', lat: 37.3842, lng: 127.1235, level: 'DONG' as PinLevel, regionCode: '4113510200' },
    // 고양시
    { name: '킨텍스 (일산)', slug: 'gyeonggi-goyang-kintex', lat: 37.6700, lng: 126.7510, level: 'DONG' as PinLevel, regionCode: '4128110100' },
    { name: '정발산역', slug: 'gyeonggi-goyang-jeongbalsan', lat: 37.6590, lng: 126.7690, level: 'DONG' as PinLevel, regionCode: '4128510100' },
    // 용인시
    { name: '기흥역', slug: 'gyeonggi-yongin-giheung', lat: 37.2750, lng: 127.1160, level: 'DONG' as PinLevel, regionCode: '4146310100' },
    { name: '수지구청역', slug: 'gyeonggi-yongin-suji', lat: 37.3225, lng: 127.0986, level: 'DONG' as PinLevel, regionCode: '4146510100' },
    // 부천시
    { name: '부천역', slug: 'gyeonggi-bucheon-station', lat: 37.4860, lng: 126.7830, level: 'DONG' as PinLevel, regionCode: '4119010100' },
    { name: '중동 신도시', slug: 'gyeonggi-bucheon-jungdong', lat: 37.5040, lng: 126.7630, level: 'DONG' as PinLevel, regionCode: '4119010200' },
    // 안산시
    { name: '안산역', slug: 'gyeonggi-ansan-station', lat: 37.3218, lng: 126.8310, level: 'DONG' as PinLevel, regionCode: '4127310100' },
    { name: '중앙역 (안산)', slug: 'gyeonggi-ansan-jungang', lat: 37.3123, lng: 126.8395, level: 'DONG' as PinLevel, regionCode: '4127310200' },
    // 안양시
    { name: '안양역', slug: 'gyeonggi-anyang-station', lat: 37.4027, lng: 126.9221, level: 'DONG' as PinLevel, regionCode: '4117110100' },
    { name: '범계역', slug: 'gyeonggi-anyang-beomgye', lat: 37.3903, lng: 126.9530, level: 'DONG' as PinLevel, regionCode: '4117310100' },
    // 남양주시
    { name: '다산신도시', slug: 'gyeonggi-namyangju-dasan', lat: 37.6118, lng: 127.1540, level: 'DONG' as PinLevel, regionCode: '4136010100' },
    { name: '마석역', slug: 'gyeonggi-namyangju-maseok', lat: 37.6505, lng: 127.2075, level: 'DONG' as PinLevel, regionCode: '4136010200' },
    // 화성시
    { name: '동탄역', slug: 'gyeonggi-hwaseong-dongtan', lat: 37.2009, lng: 127.0971, level: 'DONG' as PinLevel, regionCode: '4159010100' },
    { name: '병점역', slug: 'gyeonggi-hwaseong-byeongjeom', lat: 37.2250, lng: 127.0101, level: 'DONG' as PinLevel, regionCode: '4159010200' },
    // 평택시
    { name: '평택역', slug: 'gyeonggi-pyeongtaek-station', lat: 36.9920, lng: 127.0855, level: 'DONG' as PinLevel, regionCode: '4122010100' },
    { name: '송탄역', slug: 'gyeonggi-pyeongtaek-songtan', lat: 37.0810, lng: 127.0560, level: 'DONG' as PinLevel, regionCode: '4122010200' },
    // 의정부시
    { name: '의정부역', slug: 'gyeonggi-uijeongbu-station', lat: 37.7383, lng: 127.0458, level: 'DONG' as PinLevel, regionCode: '4115010100' },
    // 시흥시
    { name: '시흥시청역', slug: 'gyeonggi-siheung-cityhall', lat: 37.3800, lng: 126.8034, level: 'DONG' as PinLevel, regionCode: '4139010100' },
    { name: '월곶역', slug: 'gyeonggi-siheung-wolgot', lat: 37.3874, lng: 126.7371, level: 'DONG' as PinLevel, regionCode: '4139010200' },
    // 파주시
    { name: '파주 운정역', slug: 'gyeonggi-paju-unjeong', lat: 37.7152, lng: 126.7448, level: 'DONG' as PinLevel, regionCode: '4148010100' },
    { name: '파주 금촌역', slug: 'gyeonggi-paju-geumchon', lat: 37.7600, lng: 126.7800, level: 'DONG' as PinLevel, regionCode: '4148010200' },
    // 김포시
    { name: '김포한강신도시', slug: 'gyeonggi-gimpo-hangang', lat: 37.6323, lng: 126.7170, level: 'DONG' as PinLevel, regionCode: '4157010100' },
    { name: '김포공항역', slug: 'gyeonggi-gimpo-airport', lat: 37.5624, lng: 126.8010, level: 'DONG' as PinLevel, regionCode: '4157010200' },
    // 광명시
    { name: '광명역', slug: 'gyeonggi-gwangmyeong-station', lat: 37.4153, lng: 126.8844, level: 'DONG' as PinLevel, regionCode: '4121010100' },
    // 하남시
    { name: '하남 스타필드', slug: 'gyeonggi-hanam-starfield', lat: 37.5453, lng: 127.2238, level: 'DONG' as PinLevel, regionCode: '4145010100' },
    { name: '미사역', slug: 'gyeonggi-hanam-misa', lat: 37.5600, lng: 127.1930, level: 'DONG' as PinLevel, regionCode: '4145010200' },
    // 구리시
    { name: '구리역', slug: 'gyeonggi-guri-station', lat: 37.5985, lng: 127.1296, level: 'DONG' as PinLevel, regionCode: '4131010100' },
    // 양주시
    { name: '양주역', slug: 'gyeonggi-yangju-station', lat: 37.7857, lng: 127.0456, level: 'DONG' as PinLevel, regionCode: '4163010100' },
    // 오산시
    { name: '오산역', slug: 'gyeonggi-osan-station', lat: 37.1495, lng: 127.0692, level: 'DONG' as PinLevel, regionCode: '4137010100' },
    // 군포시
    { name: '군포역', slug: 'gyeonggi-gunpo-station', lat: 37.3610, lng: 126.9350, level: 'DONG' as PinLevel, regionCode: '4141010100' },
    // 의왕시
    { name: '의왕역', slug: 'gyeonggi-uiwang-station', lat: 37.3448, lng: 126.9685, level: 'DONG' as PinLevel, regionCode: '4143010100' },
    // 과천시
    { name: '과천 정부청사역', slug: 'gyeonggi-gwacheon-gov-complex', lat: 37.4264, lng: 126.9896, level: 'DONG' as PinLevel, regionCode: '4129010100' },

    // ===== 광역시 / 특별자치시 (DONG 레벨) =====
    // 부산광역시
    { name: '부산역', slug: 'busan-busan-station', lat: 35.1152, lng: 129.0422, level: 'DONG' as PinLevel, regionCode: '2617010100' },
    { name: '서면역', slug: 'busan-seomyeon', lat: 35.1578, lng: 129.0599, level: 'DONG' as PinLevel, regionCode: '2623010100' },
    { name: '해운대역', slug: 'busan-haeundae', lat: 35.1631, lng: 129.1635, level: 'DONG' as PinLevel, regionCode: '2635010100' },
    { name: '광안리 해수욕장', slug: 'busan-gwangalli', lat: 35.1532, lng: 129.1187, level: 'DONG' as PinLevel, regionCode: '2641010100' },
    { name: '센텀시티역', slug: 'busan-centum-city', lat: 35.1695, lng: 129.1314, level: 'DONG' as PinLevel, regionCode: '2635010200' },
    // 대구광역시
    { name: '대구역', slug: 'daegu-daegu-station', lat: 35.8772, lng: 128.6283, level: 'DONG' as PinLevel, regionCode: '2711010100' },
    { name: '동성로', slug: 'daegu-dongseongro', lat: 35.8690, lng: 128.5963, level: 'DONG' as PinLevel, regionCode: '2711010200' },
    { name: '수성못', slug: 'daegu-suseongmot', lat: 35.8283, lng: 128.6180, level: 'DONG' as PinLevel, regionCode: '2726010100' },
    // 인천광역시
    { name: '인천역 차이나타운', slug: 'incheon-chinatown', lat: 37.4738, lng: 126.6172, level: 'DONG' as PinLevel, regionCode: '2811010100' },
    { name: '부평역', slug: 'incheon-bupyeong', lat: 37.4900, lng: 126.7235, level: 'DONG' as PinLevel, regionCode: '2823710100' },
    { name: '송도 센트럴파크', slug: 'incheon-songdo', lat: 37.3815, lng: 126.6610, level: 'DONG' as PinLevel, regionCode: '2818510100' },
    // 광주광역시
    { name: '광주송정역', slug: 'gwangju-songjeong-station', lat: 35.1377, lng: 126.7928, level: 'DONG' as PinLevel, regionCode: '2920010100' },
    { name: '충장로', slug: 'gwangju-chungjangro', lat: 35.1466, lng: 126.9215, level: 'DONG' as PinLevel, regionCode: '2911010100' },
    { name: '상무지구', slug: 'gwangju-sangmu', lat: 35.1500, lng: 126.8521, level: 'DONG' as PinLevel, regionCode: '2914010100' },
    // 대전광역시
    { name: '대전역', slug: 'daejeon-daejeon-station', lat: 36.3325, lng: 127.4345, level: 'DONG' as PinLevel, regionCode: '3011010100' },
    { name: '둔산동', slug: 'daejeon-dunsan', lat: 36.3518, lng: 127.3782, level: 'DONG' as PinLevel, regionCode: '3014010100' },
    { name: '유성온천역', slug: 'daejeon-yuseong', lat: 36.3555, lng: 127.3415, level: 'DONG' as PinLevel, regionCode: '3020010100' },
    // 울산광역시
    { name: '울산역', slug: 'ulsan-ulsan-station', lat: 35.5498, lng: 129.2575, level: 'DONG' as PinLevel, regionCode: '3171010100' },
    { name: '성남동 중앙거리', slug: 'ulsan-seongnam-center', lat: 35.5537, lng: 129.3132, level: 'DONG' as PinLevel, regionCode: '3114010100' },
    // 세종특별자치시
    { name: '세종시 정부세종청사', slug: 'sejong-gov-complex', lat: 36.5040, lng: 127.0046, level: 'DONG' as PinLevel, regionCode: '3611010100' },
    { name: '세종시 보람동', slug: 'sejong-boram', lat: 36.5106, lng: 127.0100, level: 'DONG' as PinLevel, regionCode: '3611010200' },
  ];

  // 구 레벨 핀 먼저 삽입
  const guPins = allPins.filter((p) => p.level === 'GU');
  for (const pin of guPins) {
    await prisma.$executeRawUnsafe(
      `INSERT INTO pins (id, name, slug, center, level, region_code, is_active, metadata, created_at)
       VALUES (gen_random_uuid(), $1, $2, ST_GeogFromText($3), $4::"PinLevel", $5, TRUE, '{}', NOW())
       ON CONFLICT (slug) DO NOTHING`,
      pin.name,
      pin.slug,
      `POINT(${pin.lng} ${pin.lat})`,
      pin.level,
      pin.regionCode,
    );
  }

  // 동 레벨 핀 삽입 (부모 핀 ID 연결)
  const dongPins = allPins.filter((p) => p.level === 'DONG');
  for (const pin of dongPins) {
    const parentSlug = (pin as any).parentSlug;
    let parentPinId: string | null = null;

    if (parentSlug) {
      const parentPin = await prisma.pin.findUnique({
        where: { slug: parentSlug },
      });
      parentPinId = parentPin?.id ?? null;
    }

    await prisma.$executeRawUnsafe(
      `INSERT INTO pins (id, name, slug, center, level, parent_pin_id, region_code, is_active, metadata, created_at)
       VALUES (gen_random_uuid(), $1, $2, ST_GeogFromText($3), $4::"PinLevel", $5::uuid, $6, TRUE, '{}', NOW())
       ON CONFLICT (slug) DO NOTHING`,
      pin.name,
      pin.slug,
      `POINT(${pin.lng} ${pin.lat})`,
      pin.level,
      parentPinId,
      pin.regionCode,
    );
  }

  // ─────────────────────────────────────
  // 테스트 사용자 (개발 환경 전용)
  // ─────────────────────────────────────

  if (process.env.NODE_ENV !== 'production') {
    const testUser = await prisma.user.upsert({
      where: { email: 'test@pins.kr' },
      create: {
        email: 'test@pins.kr',
        nickname: '테스트골퍼',
        status: 'ACTIVE',
        lastLoginAt: new Date(),
        notificationSettings: { create: {} },
      },
      update: {},
    });

    // 테스트 스포츠 프로필
    await prisma.sportsProfile.upsert({
      where: {
        userId_sportType: { userId: testUser.id, sportType: 'GOLF' },
      },
      create: {
        userId: testUser.id,
        sportType: 'GOLF',
        displayName: '주말 골퍼',
        gHandicap: 18.0,
        initialScore: 1150,
        currentScore: 1150,
        tier: 'SILVER',
      },
      update: {},
    });

    // 테스트 사용자 위치 (강남 역삼동)
    await prisma.$executeRawUnsafe(
      `INSERT INTO user_locations (id, user_id, home_point, home_address, match_radius_km, updated_at)
       VALUES (gen_random_uuid(), $1::uuid, ST_GeogFromText('POINT(127.0361 37.5007)'), '서울 강남구 역삼동', 10, NOW())
       ON CONFLICT (user_id) DO NOTHING`,
      testUser.id,
    );

    console.info(`Test user created: ${testUser.id}`);

    // 두 번째 테스트 사용자 (매칭 테스트용)
    const testUser2 = await prisma.user.upsert({
      where: { email: 'test2@pins.kr' },
      create: {
        email: 'test2@pins.kr',
        nickname: '골프매니아',
        status: 'ACTIVE',
        lastLoginAt: new Date(),
        notificationSettings: { create: {} },
      },
      update: {},
    });

    await prisma.sportsProfile.upsert({
      where: {
        userId_sportType: { userId: testUser2.id, sportType: 'GOLF' },
      },
      create: {
        userId: testUser2.id,
        sportType: 'GOLF',
        displayName: '싱글 도전',
        gHandicap: 12.0,
        initialScore: 1280,
        currentScore: 1280,
        tier: 'SILVER',
      },
      update: {},
    });

    await prisma.$executeRawUnsafe(
      `INSERT INTO user_locations (id, user_id, home_point, home_address, match_radius_km, updated_at)
       VALUES (gen_random_uuid(), $1::uuid, ST_GeogFromText('POINT(127.0596 37.5140)'), '서울 강남구 삼성동', 15, NOW())
       ON CONFLICT (user_id) DO NOTHING`,
      testUser2.id,
    );

    console.info(`Test user 2 created: ${testUser2.id}`);

    // 어드민 계정
    const adminUser = await prisma.user.upsert({
      where: { email: 'admin@pins.kr' },
      create: {
        email: 'admin@pins.kr',
        nickname: '어드민',
        status: 'ACTIVE',
        lastLoginAt: new Date(),
        notificationSettings: { create: {} },
      },
      update: {},
    });

    await prisma.adminProfile.upsert({
      where: { userId: adminUser.id },
      create: { userId: adminUser.id, role: 'SUPER_ADMIN' },
      update: {},
    });

    console.info(`Admin user created: ${adminUser.id}`);
  }

  // ─────────────────────────────────────
  // 테스트 팀 데이터 (개발 환경 전용)
  // ─────────────────────────────────────

  if (process.env.NODE_ENV !== 'production') {
    // 테스트 사용자 조회 (이미 위에서 생성됨)
    const testUser = await prisma.user.findUnique({ where: { email: 'test@pins.kr' } });
    const testUser2 = await prisma.user.findUnique({ where: { email: 'test2@pins.kr' } });

    if (testUser && testUser2) {
      // 축구팀 생성 (종목 확장용 — 기존 SportType enum에 SOCCER 없으면 GOLF로 대체)
      // 현재 enum: GOLF, BILLIARDS, TENNIS, TABLE_TENNIS
      // 팀 시스템 종목은 기존 SportType을 재활용

      // 골프팀 생성
      const golfTeamSlug = `test-golf-team-${Date.now().toString(36).slice(-6)}`;
      const golfTeam = await prisma.team.upsert({
        where: { slug: golfTeamSlug },
        create: {
          name: '강남 골프 클럽',
          slug: golfTeamSlug,
          sportType: 'GOLF',
          description: '강남에서 활동하는 골프 동호회입니다. 함께 즐거운 라운딩해요!',
          activityRegion: '서울 강남구',
          minMembers: 4,
          maxMembers: 20,
          currentMembers: 2,
          isRecruiting: true,
          status: 'ACTIVE',
        },
        update: {},
      });

      // CAPTAIN 등록 (testUser)
      await prisma.teamMember.upsert({
        where: { teamId_userId: { teamId: golfTeam.id, userId: testUser.id } },
        create: {
          teamId: golfTeam.id,
          userId: testUser.id,
          role: 'CAPTAIN',
          status: 'ACTIVE',
        },
        update: {},
      });

      // MEMBER 등록 (testUser2)
      await prisma.teamMember.upsert({
        where: { teamId_userId: { teamId: golfTeam.id, userId: testUser2.id } },
        create: {
          teamId: golfTeam.id,
          userId: testUser2.id,
          role: 'MEMBER',
          status: 'ACTIVE',
        },
        update: {},
      });

      // 테니스팀 생성
      const tennisTeamSlug = `test-tennis-team-${Date.now().toString(36).slice(-6)}`;
      await prisma.team.upsert({
        where: { slug: tennisTeamSlug },
        create: {
          name: '서초 테니스 클럽',
          slug: tennisTeamSlug,
          sportType: 'TENNIS',
          description: '서초구에서 활동하는 테니스 동호회. 초중급 환영!',
          activityRegion: '서울 서초구',
          minMembers: 4,
          maxMembers: 16,
          currentMembers: 1,
          isRecruiting: true,
          status: 'ACTIVE',
        },
        update: {},
      });

      console.info(`Test teams created. Golf team id: ${golfTeam.id}`);
    }
  }

  const pinCount = await prisma.pin.count();
  const userCount = await prisma.user.count();
  const teamCount = await prisma.team.count();
  console.info(`Seeding complete. Pins: ${pinCount}, Users: ${userCount}, Teams: ${teamCount}`);
}

main()
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  })
  .finally(() => {
    prisma.$disconnect();
  });
