#!/bin/bash
set -e

KEY="$HOME/WebProject2/match/spots-key.pem"
HOST="ec2-user@43.203.165.114"
SSH="ssh -i $KEY $HOST"
REMOTE_DIR="spots-server"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"
START=$(date +%s)

echo "=== PINS 서버 배포 ==="

# 1) package.json 변경 여부 체크 (로컬 vs 원격 md5)
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

# 4) PM2 reload (zero-downtime)
echo ">>> PM2 reload..."
$SSH "pm2 reload all 2>/dev/null || (cd $REMOTE_DIR && pm2 delete all 2>/dev/null; pm2 start ecosystem.config.cjs)"

# 5) health check (1초 간격, 최대 8초)
echo -n ">>> health check "
for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  STATUS=$($SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/health" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    END=$(date +%s)
    echo ""
    echo "=== 배포 완료 ($((END - START))초) ==="
    exit 0
  fi
  echo -n "."
done

echo ""
echo "=== 배포 실패 — 로그 ==="
$SSH "pm2 logs match-api --lines 10 --nostream 2>&1 | tail -10"
exit 1
