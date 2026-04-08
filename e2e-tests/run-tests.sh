#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Playwright E2E 테스트 실행 스크립트
# =============================================================================

TEST_CLIENT_PORT=9090
API_SERVER_PORT=3000

# 색상 출력 헬퍼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# 포트가 사용 중인지 확인하는 함수
check_port() {
  local port=$1
  local name=$2

  if lsof -i ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    log_info "${name}이(가) 포트 ${port}에서 실행 중입니다."
    return 0
  else
    log_error "${name}이(가) 포트 ${port}에서 실행되고 있지 않습니다."
    return 1
  fi
}

# 헤더 출력
echo ""
echo "=============================================="
echo "  Spots 스포츠 매칭 플랫폼 E2E 테스트 실행"
echo "=============================================="
echo ""

# 1. 테스트 클라이언트 서버 확인
log_info "테스트 클라이언트 서버 확인 중 (포트 ${TEST_CLIENT_PORT})..."
if ! check_port "${TEST_CLIENT_PORT}" "테스트 클라이언트"; then
  log_error "테스트 클라이언트를 먼저 실행해 주세요."
  log_error "예: npx serve -l ${TEST_CLIENT_PORT} ./public"
  exit 1
fi

# 2. API 서버 확인
log_info "API 서버 확인 중 (포트 ${API_SERVER_PORT})..."
if ! check_port "${API_SERVER_PORT}" "API 서버"; then
  log_error "API 서버를 먼저 실행해 주세요."
  log_error "예: cd ../server && pm2 start ecosystem.config.js"
  exit 1
fi

echo ""
log_info "모든 서버가 실행 중입니다. 테스트를 시작합니다..."
echo ""

# 3. Playwright 테스트 실행
# 추가 인수를 그대로 npx playwright test에 전달
PLAYWRIGHT_ARGS="${@:-}"

if npx playwright test ${PLAYWRIGHT_ARGS}; then
  TEST_EXIT_CODE=0
else
  TEST_EXIT_CODE=$?
fi

# 4. 결과 출력 및 리포트 열기
echo ""
if [ "${TEST_EXIT_CODE}" -eq 0 ]; then
  log_info "모든 테스트가 통과했습니다."
  log_info "HTML 리포트를 열고 있습니다..."
  npx playwright show-report 2>/dev/null || true
else
  log_warn "일부 테스트가 실패했습니다. (종료 코드: ${TEST_EXIT_CODE})"
  log_warn "자세한 내용은 HTML 리포트를 확인하세요:"
  log_warn "  npx playwright show-report"
fi

echo ""
exit "${TEST_EXIT_CODE}"
