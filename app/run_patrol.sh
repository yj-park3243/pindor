#!/bin/bash
set -e
DEVICE="${1:-match}"
cd "$(dirname "$0")"

echo "=== 핀돌 Patrol 테스트 ($DEVICE) ==="

# 1. patrol로 test_bundle.dart 생성 (빌드 실패해도 OK)
rm -rf patrol_test/
patrol test -d "$DEVICE" -t integration_test/app_test.dart 2>/dev/null || true

# 2. import 경로 수정
if [ -f patrol_test/test_bundle.dart ]; then
  sed -i '' "s|import 'Users/.*/integration_test/|import '../integration_test/|g" patrol_test/test_bundle.dart
  sed -i '' "s|Users__[a-zA-Z0-9_]*__integration_test__app_test|app_test|g" patrol_test/test_bundle.dart
  echo "✅ import 경로 수정"
else
  echo "❌ test_bundle.dart 생성 실패"
  exit 1
fi

# 3. flutter 빌드 (PATROL_ENABLED 포함)
echo ">>> flutter 빌드..."
flutter build ios --no-codesign --debug --simulator \
  --target patrol_test/test_bundle.dart \
  --dart-define PATROL_ENABLED=true \
  --dart-define INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=true \
  --dart-define PATROL_TEST_LABEL_ENABLED=true \
  --dart-define PATROL_TEST_SERVER_PORT=8081 \
  --dart-define PATROL_APP_SERVER_PORT=8082 \
  2>&1 | tail -2

# 4. RunnerUITests 빌드
echo ">>> RunnerUITests 빌드..."
cd ios
xcodebuild build-for-testing \
  -workspace Runner.xcworkspace \
  -scheme RunnerUITests \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath ../build/ios_integ \
  OTHER_CFLAGS='$(inherited) -D PATROL_ENABLED=1 -D FULL_ISOLATION=0 -D CLEAR_PERMISSIONS=0' \
  -quiet 2>&1 | tail -2
cd ..

# 5. flutter 빌드 앱을 xcodebuild 위치로 복사 (PATROL_ENABLED dart-define 포함)
cp -R build/ios/iphonesimulator/Runner.app build/ios_integ/Build/Products/Debug-iphonesimulator/Runner.app
echo "✅ flutter 앱 복사"

# 6. 테스트 실행
echo ">>> 테스트 실행..."
XCTESTRUN=$(find build/ios_integ -name "RunnerUITests*.xctestrun" | head -1)
xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN" \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  2>&1 | grep -E "Test Case|passed|failed|flutter:|===|started|error" | head -20

echo "=== 완료 ==="
