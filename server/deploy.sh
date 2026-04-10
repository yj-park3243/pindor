#!/bin/bash
set -e

KEY="$HOME/WebProject2/match/spots-key.pem"
HOST="ec2-user@43.203.165.114"
SSH="ssh -i $KEY $HOST"
REMOTE_DIR="spots-server"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"
START=$(date +%s)

echo "=== PINDOR 서버 무중단 배포 ==="

# 1) package.json 변경 여부 체크
LOCAL_HASH=$(md5 -q "$LOCAL_DIR/package.json" 2>/dev/null || md5sum "$LOCAL_DIR/package.json" | cut -d' ' -f1)
REMOTE_HASH=$($SSH "md5sum $REMOTE_DIR/package.json 2>/dev/null | cut -d' ' -f1" 2>/dev/null || echo "none")
NEED_INSTALL=false
[ "$LOCAL_HASH" != "$REMOTE_HASH" ] && NEED_INSTALL=true

# 2) rsync — 변경된 파일만 전송
echo ">>> 코드 전송..."
rsync -az --delete \
  --exclude node_modules \
  --exclude logs \
  --exclude dist \
  --exclude .env \
  --exclude firebase-service-account.json \
  --exclude prisma \
  --exclude tmp \
  --exclude tests \
  -e "ssh -i $KEY" \
  "$LOCAL_DIR/" "$HOST:$REMOTE_DIR/"

# 3) npm install (package.json 바뀐 경우만)
if [ "$NEED_INSTALL" = true ]; then
  echo ">>> npm install (package.json 변경됨)..."
  $SSH "cd $REMOTE_DIR && npm install --silent 2>/dev/null"
else
  echo ">>> npm install 스킵 (변경 없음)"
fi

# 4) PM2 무중단 배포 — 프로세스별 순차 reload
echo ">>> PM2 무중단 reload..."

# PM2가 실행 중인지 확인
PM2_RUNNING=$($SSH "pm2 list --no-color 2>&1 | grep -c 'online'" 2>/dev/null || echo "0")

if [ "$PM2_RUNNING" -gt 0 ]; then
  # 실행 중이면 개별 프로세스 순차 reload (--update-env로 환경변수 갱신)
  # API를 마지막에 reload (Worker가 먼저 준비되도록)
  $SSH "pm2 reload match-worker --update-env 2>/dev/null" && echo "  ✓ match-worker"
  $SSH "pm2 reload match-queue --update-env 2>/dev/null" && echo "  ✓ match-queue"
  $SSH "pm2 reload match-api --update-env 2>/dev/null" && echo "  ✓ match-api"
else
  # 실행 중이 아니면 ecosystem.config.cjs로 시작
  echo "  PM2 프로세스 없음 — 신규 시작..."
  $SSH "cd $REMOTE_DIR && pm2 start ecosystem.config.cjs --update-env"
fi

# 5) health check (1초 간격, 최대 10초)
echo -n ">>> health check "
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  STATUS=$($SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/health" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    END=$(date +%s)
    echo ""
    echo "=== 무중단 배포 완료 ($((END - START))초) ==="
    exit 0
  fi
  echo -n "."
done

# health check 실패 시 로그 출력 (rollback은 하지 않음)
echo ""
echo "=== health check 실패 — 로그 확인 ==="
$SSH "pm2 logs match-api --lines 10 --nostream 2>&1 | tail -10"
exit 1
