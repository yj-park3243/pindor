/// E2E 테스트 설정 상수
///
/// - apiBaseUrl: 로컬 서버 (에뮬레이터에서 localhost:3000 접근 시 10.0.2.2 사용)
/// - TEST_USER_ROLE: 환경변수로 'A' 또는 'B' 지정
class TestConfig {
  TestConfig._();

  // Android 에뮬레이터에서 호스트 localhost는 10.0.2.2로 접근
  // iOS 시뮬레이터는 127.0.0.1 (localhost) 그대로 사용
  static const String apiBaseUrl = String.fromEnvironment(
    'TEST_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/v1',
  );

  // 테스트 유저 A (에뮬레이터 'match')
  static const String userAEmail = 'test_match@spots.test';
  static const String userAPassword = 'test123456';
  static const String userANickname = 'E2E매칭유저A';
  static const String userADisplayName = 'E2E골퍼A';

  // 테스트 유저 B (에뮬레이터 'kids')
  static const String userBEmail = 'test_kids@spots.test';
  static const String userBPassword = 'test123456';
  static const String userBNickname = 'E2E매칭유저B';
  static const String userBDisplayName = 'E2E골퍼B';

  // 테스트 역할 (환경변수로 주입)
  static const String testUserRole = String.fromEnvironment(
    'TEST_USER_ROLE',
    defaultValue: 'A',
  );

  static bool get isRoleA => testUserRole == 'A';
  static bool get isRoleB => testUserRole == 'B';

  // 폴링 설정
  static const Duration pollInterval = Duration(seconds: 3);
  static const int maxPollAttempts = 200; // 최대 10분 대기

  // 테스트 타임아웃
  static const Duration testTimeout = Duration(minutes: 10);

  // 테스트용 스포츠 타입
  static const String testSportType = 'GOLF';

  // 테스트 경기 결과
  static const int userAScore = 3;
  static const int userBScore = 1;

  // 테스트 경기 확정 정보
  static const String testScheduledDate = '2026-04-10';
  static const String testScheduledTime = '14:00';
  static const String testVenueName = 'E2E 테스트 골프장';
  static const double testVenueLatitude = 37.5665;
  static const double testVenueLongitude = 126.9780;

  // 채팅 메시지
  static const String userAChatMessage = '안녕하세요!';
  static const String userBChatMessage = '반갑습니다!';

  // 테스트 위치 (서울 중심)
  static const double testLatitude = 37.5665;
  static const double testLongitude = 126.9780;
  static const String testAddress = '서울특별시 중구 을지로1가';
}
