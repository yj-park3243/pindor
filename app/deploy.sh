#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# .env 로드
source ios/fastlane/.env

PLAY_KEY="$SCRIPT_DIR/../etc/PINS fastlane.json"
PLATFORM="${1:-all}"  # ios, android, all(기본)
BUMP_FLAG="${2:-}"    # --bump: 패치 버전(x.y.Z)도 증가

# ─── 빌드번호 자동 증가 ───
CURRENT_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
VERSION_NAME=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))

# --bump 플래그: 패치 버전(x.y.Z) 함께 증가
if [ "$BUMP_FLAG" = "--bump" ]; then
  PATCH=$(echo "$VERSION_NAME" | cut -d'.' -f3)
  NEW_PATCH=$((PATCH + 1))
  VERSION_NAME=$(echo "$VERSION_NAME" | sed "s/\.[0-9]*$/.$NEW_PATCH/")
  echo "패치 버전 증가: $VERSION_NAME"
fi

sed -i '' "s/version: $CURRENT_VERSION/version: $VERSION_NAME+$NEW_BUILD_NUMBER/" pubspec.yaml

echo "=============================="
echo "  PINDOR 배포 v$VERSION_NAME+$NEW_BUILD_NUMBER"
echo "=============================="

# ─── iOS ───
# 빌드 시각 (개발자 메뉴 노출용)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
  echo ""
  echo ">>> [iOS] Flutter IPA 빌드 중..."
  flutter build ipa --release \
    --dart-define=ENVIRONMENT=production \
    --dart-define=BUILD_TIME="$BUILD_TIME"

  IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -1)
  if [ -z "$IPA_PATH" ]; then
    echo "IPA 파일을 찾을 수 없습니다"
    exit 1
  fi

  echo ">>> [iOS] TestFlight 업로드 중..."
  xcrun altool --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

  echo ">>> [iOS] TestFlight 업로드 완료!"
fi

# ─── Android ───
if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
  echo ""
  echo ">>> [Android] AAB 빌드 중..."
  flutter build appbundle --release \
    --dart-define=ENVIRONMENT=production \
    --dart-define=BUILD_TIME="$BUILD_TIME"

  AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
  if [ ! -f "$AAB_PATH" ]; then
    echo "AAB 파일을 찾을 수 없습니다"
    exit 1
  fi

  PLAY_TRACK="${PLAY_TRACK:-alpha}"
  echo ">>> [Android] Google Play 업로드 중 (track=$PLAY_TRACK)..."
  fastlane supply \
    --aab "$AAB_PATH" \
    --json_key "$PLAY_KEY" \
    --package_name "kr.pins.spots" \
    --track "$PLAY_TRACK" \
    --release_status completed \
    --skip_upload_metadata \
    --skip_upload_images \
    --skip_upload_screenshots \
    --skip_upload_apk

  echo ">>> [Android] Google Play 업로드 완료!"
fi

echo ""
echo "=============================="
echo "  배포 완료!"
echo "=============================="
