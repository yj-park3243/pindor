#!/bin/bash
# E2E 매칭 테스트 — 2대 iOS 시뮬레이터 순차 실행
#
# 전략: API로 계정/토큰 준비 → SecureStorage 토큰 주입 → 앱 실행(자동 로그인)
#        → 이후 모든 동작은 UI 조작
#
# 전제 조건:
#   - iOS 시뮬레이터 'match' (User A), 'kids' (User B) 이름으로 등록되어 있어야 함
#   - 로컬 API 서버가 127.0.0.1:3000에 실행 중이어야 함
#   - 서버에 핀 데이터가 최소 1개 이상 있어야 함
#
# 실행: bash run_matching_test.sh

set -e  # 에러 발생 시 중단

API_URL="https://api.pins.kr/v1"
TARGET="integration_test/matching_e2e_test.dart"
DRIVER="test_driver/integration_test.dart"

# 스크린샷 저장 디렉토리 초기화
SCREENSHOT_DIR="test_screenshots/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SCREENSHOT_DIR"
echo "스크린샷 저장 경로: $SCREENSHOT_DIR"

echo ""
echo "=================================================="
echo "  Spots E2E 매칭 테스트 (UI 조작 방식)"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo ""

# ── User A 빌드 + 실행 (백그라운드) ────────────────────────────────────
echo "[Step 1] User A 테스트 시작 (에뮬레이터: match)"
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  --dart-define=TEST_USER_ROLE=A \
  --dart-define=TEST_API_BASE_URL="$API_URL" \
  --screenshot="$SCREENSHOT_DIR/userA" \
  -d match \
  2>&1 | tee "$SCREENSHOT_DIR/userA_test.log" &
PID_A=$!
echo "  → User A PID: $PID_A"

# User B는 A가 빌드되는 동안 대기 (flutter build lock 방지)
# A의 빌드가 완료되어 실행에 들어갈 때쯤 B 시작
echo "[Step 2] User B 빌드 대기 중 (90초)..."
sleep 90

# ── User B 빌드 + 실행 (백그라운드) ────────────────────────────────────
echo "[Step 3] User B 테스트 시작 (에뮬레이터: kids)"
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  --dart-define=TEST_USER_ROLE=B \
  --dart-define=TEST_API_BASE_URL="$API_URL" \
  --screenshot="$SCREENSHOT_DIR/userB" \
  -d kids \
  2>&1 | tee "$SCREENSHOT_DIR/userB_test.log" &
PID_B=$!
echo "  → User B PID: $PID_B"

# ── 두 프로세스 종료 대기 ──────────────────────────────────────────────
echo ""
echo "[Step 4] 테스트 완료 대기 중..."
echo "  User A (PID $PID_A) + User B (PID $PID_B)"
echo ""

FAIL=0

wait $PID_A
EXIT_A=$?
if [ $EXIT_A -ne 0 ]; then
  echo "[FAIL] User A 테스트 실패 (exit: $EXIT_A)"
  FAIL=1
else
  echo "[PASS] User A 테스트 성공"
fi

wait $PID_B
EXIT_B=$?
if [ $EXIT_B -ne 0 ]; then
  echo "[FAIL] User B 테스트 실패 (exit: $EXIT_B)"
  FAIL=1
else
  echo "[PASS] User B 테스트 성공"
fi

echo ""
echo "=================================================="
if [ $FAIL -eq 0 ]; then
  echo "  결과: 전체 테스트 성공"
else
  echo "  결과: 테스트 실패 — 로그 확인:"
  echo "    User A: $SCREENSHOT_DIR/userA_test.log"
  echo "    User B: $SCREENSHOT_DIR/userB_test.log"
fi
echo "  스크린샷: $SCREENSHOT_DIR"
echo "=================================================="
echo ""

exit $FAIL
