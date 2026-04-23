#!/bin/bash
# 한번에 설치 + 실행.
# ADMIN_PASSWORD 환경변수 필수. 미설정 시 프롬프트로 받음.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "${ADMIN_PASSWORD:-}" ]; then
  read -s -p "ADMIN_PASSWORD: " ADMIN_PASSWORD
  export ADMIN_PASSWORD
  echo ""
fi

if [ ! -d node_modules ]; then
  echo ">>> npm install"
  npm install
  echo ">>> playwright install chromium"
  npx playwright install chromium
fi

mkdir -p test-results/admin-e2e

echo ">>> Playwright tests"
npx playwright test "$@"
