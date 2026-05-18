#!/bin/bash
# 스토어 심사 제출 자동화
# - iOS: TestFlight 에 이미 업로드된 빌드를 App Store 심사로 제출 (binary 재업로드 X)
# - Android: alpha 트랙의 최신 빌드를 production 트랙으로 승급 (AAB 재업로드 X)
#
# 사용법:
#   bash submit.sh           # iOS + Android 모두 심사 제출
#   bash submit.sh ios       # iOS 만
#   bash submit.sh android   # Android 만
#
# 전제: 사전에 ./deploy.sh 로 TestFlight/Play alpha 업로드 + 처리 완료된 상태.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# .env 로드 (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_IDENTIFIER)
source ios/fastlane/.env

PLAY_KEY="$SCRIPT_DIR/../etc/PINS fastlane.json"
PLATFORM="${1:-all}"  # ios, android, all(기본)

# pubspec.yaml 에서 현재 버전/빌드번호 추출
CURRENT_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
VERSION_NAME=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)

echo "=============================="
echo "  PINDOR 스토어 심사 제출"
echo "  v$VERSION_NAME (build $BUILD_NUMBER)"
echo "=============================="

# ─── iOS App Store 심사 제출 ───
# ios/fastlane/Fastfile 의 :submit_review lane 실행
if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
  echo ""
  echo ">>> [iOS] App Store 심사 제출 중..."
  (cd ios && fastlane submit_review)
  echo ">>> [iOS] App Store 심사 제출 완료!"
fi

# ─── Android Play Store production 승급 ───
if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
  echo ""
  echo ">>> [Android] Play Store production 승급 중..."

  # internal → production 승급 (AAB 재업로드 X — 동일 빌드 트랙만 변경).
  # rollout 1.0 = 100% 즉시 출시. staged rollout 원하면 0.1 등으로 조정.
  fastlane supply \
    --json_key "$PLAY_KEY" \
    --package_name "kr.pins.spots" \
    --track internal \
    --track_promote_to production \
    --release_status completed \
    --rollout 1.0 \
    --skip_upload_apk true \
    --skip_upload_aab true \
    --skip_upload_metadata true \
    --skip_upload_images true \
    --skip_upload_screenshots true

  echo ">>> [Android] Play Store production 승급 완료!"
fi

echo ""
echo "=============================="
echo "  심사 제출 완료!"
echo "=============================="
