#!/usr/bin/env bash
# ============================================================
# 2대 시뮬레이터 E2E 테스트 오케스트레이터
#
# flutter는 동시 빌드를 지원하지 않으므로, A를 먼저 빌드+실행 후
# A가 매칭 대기에 들어간 뒤 B를 시작합니다.
#
# 사용법: bash run_e2e.sh --ios
# ============================================================

set -uo pipefail

DEVICE_A="match"
DEVICE_B="kids"
DRIVER="test_driver/integration_test.dart"
TARGET="integration_test/app_test.dart"

API_HOST="10.0.2.2"
if [[ "${1:-}" == "--ios" ]]; then
  API_HOST="127.0.0.1"
fi
API_BASE_URL="http://${API_HOST}:3000/v1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[E2E]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 에뮬레이터 확인
DEVICES=$(flutter devices 2>/dev/null || echo "")
echo "$DEVICES" | grep -q "$DEVICE_A" || { log_error "'$DEVICE_A' 없음"; exit 1; }
echo "$DEVICES" | grep -q "$DEVICE_B" || { log_error "'$DEVICE_B' 없음"; exit 1; }
log_info "에뮬레이터 확인 완료: '$DEVICE_A' / '$DEVICE_B'"
log_info "API 서버: $API_BASE_URL"

# ── User A 실행 (백그라운드) ──────────────────────────────
log_info "User A 시작 (device: $DEVICE_A) ..."
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  --dart-define="TEST_USER_ROLE=A" \
  --dart-define="TEST_API_BASE_URL=$API_BASE_URL" \
  -d "$DEVICE_A" \
  2>&1 | sed 's/^/[UserA] /' &
PID_A=$!

# A의 빌드+설치가 끝나고 매칭 요청까지 생성할 시간 대기
# flutter drive 빌드에 약 60-90초 소요
log_info "User A 빌드 완료 대기 (60초)..."
sleep 60

# ── User B 실행 (백그라운드) ──────────────────────────────
log_info "User B 시작 (device: $DEVICE_B) ..."
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  --dart-define="TEST_USER_ROLE=B" \
  --dart-define="TEST_API_BASE_URL=$API_BASE_URL" \
  -d "$DEVICE_B" \
  2>&1 | sed 's/^/[UserB] /' &
PID_B=$!

# ── 양쪽 모두 완료 대기 ──────────────────────────────────
log_info "두 에뮬레이터의 테스트 완료를 기다립니다..."

EXIT_A=0
EXIT_B=0
wait "$PID_A" || EXIT_A=$?
wait "$PID_B" || EXIT_B=$?

# ── 결과 출력 ─────────────────────────────────────────────
echo ""
echo "========================================"
[ "$EXIT_A" -eq 0 ] && log_info "User A ($DEVICE_A): PASSED" || log_error "User A ($DEVICE_A): FAILED ($EXIT_A)"
[ "$EXIT_B" -eq 0 ] && log_info "User B ($DEVICE_B): PASSED" || log_error "User B ($DEVICE_B): FAILED ($EXIT_B)"
echo "========================================"

TOTAL=$((EXIT_A + EXIT_B))
[ "$TOTAL" -eq 0 ] && log_info "E2E 테스트 전체 통과" || log_error "E2E 테스트 실패"
exit "$TOTAL"
