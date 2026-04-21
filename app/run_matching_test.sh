#!/bin/bash
# E2E 매칭 테스트 — 2대 iOS 시뮬레이터 병렬 실행
#
# 전제:
#   - iOS 시뮬레이터 'match' (User A), 'kids' (User B) Booted 상태
#   - 운영 API(api.pins.kr) + EC2 SSH 접근 가능 (DB UPDATE용)
#   - jq, curl 설치됨
#
# 실행: bash run_matching_test.sh

set -euo pipefail

API_URL="https://api.pins.kr/v1"
SSH_KEY="$HOME/WebProject2/match/spots-key.pem"
EC2="ec2-user@43.203.165.114"
TARGET="integration_test/matching_e2e_test.dart"
DRIVER="test_driver/integration_test.dart"

TS=$(date +%s)
EMAIL_A="e2e_a_${TS}@test.com"
EMAIL_B="e2e_b_${TS}@test.com"
PASSWORD="test123456"

SCREENSHOT_DIR="test_screenshots/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SCREENSHOT_DIR"

echo "=================================================="
echo "  Spots E2E 매칭 테스트"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "  로그: $SCREENSHOT_DIR"
echo "=================================================="

# ── 1. API로 유저 A/B 등록 ────────────────────────────────────────────
echo ""
echo "[1/6] 유저 등록 (API)"

reg() {
  local email="$1"
  curl -sf -X POST "$API_URL/auth/email/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}"
}

REG_A=$(reg "$EMAIL_A")
TOKEN_A=$(echo "$REG_A" | jq -r '.data.accessToken')
REFRESH_A=$(echo "$REG_A" | jq -r '.data.refreshToken')
ID_A=$(echo "$REG_A" | jq -r '.data.user.id')
echo "  A: $EMAIL_A → id=$ID_A"

REG_B=$(reg "$EMAIL_B")
TOKEN_B=$(echo "$REG_B" | jq -r '.data.accessToken')
REFRESH_B=$(echo "$REG_B" | jq -r '.data.refreshToken')
ID_B=$(echo "$REG_B" | jq -r '.data.user.id')
echo "  B: $EMAIL_B → id=$ID_B"

# ── 2. SSH + psql로 is_verified=true, gender, birth_date UPDATE ───────
echo ""
echo "[2/6] 본인인증 우회 (SSH psql: is_verified/gender/birth_date)"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2" \
  "cd spots-server && set -a && source .env && set +a && \
   DB=\$(echo \"\$DATABASE_URL\" | cut -d'?' -f1) && \
   psql \"\$DB\" -c \"UPDATE users SET is_verified=true, gender='MALE', birth_date='1990-01-01' WHERE id IN ('$ID_A','$ID_B');\"" \
  2>&1 | tail -5

# ── 3. 닉네임 설정 ─────────────────────────────────────────────────────
echo ""
echo "[3/6] 닉네임 설정"

set_nickname() {
  local token="$1"
  local nick="$2"
  curl -sf -X PATCH "$API_URL/users/me" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"nickname\":\"$nick\"}" > /dev/null
}

set_nickname "$TOKEN_A" "E2EA${TS}"
set_nickname "$TOKEN_B" "E2EB${TS}"
echo "  완료"

# ── 4. 스포츠 프로필 생성 (GOLF) ──────────────────────────────────────
echo ""
echo "[4/6] 스포츠 프로필 생성 (GOLF)"

create_sport() {
  local token="$1"
  local display="$2"
  curl -sf -X POST "$API_URL/sports-profiles" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"sportType\":\"GOLF\",\"displayName\":\"$display\",\"gHandicap\":30.0}" \
    > /dev/null
}

create_sport "$TOKEN_A" "E2E골퍼A" || echo "  A 스포츠 프로필 이미 존재"
create_sport "$TOKEN_B" "E2E골퍼B" || echo "  B 스포츠 프로필 이미 존재"
echo "  완료"

# ── 5. 위치 설정 (서울 중심, 반경 50km) ───────────────────────────────
echo ""
echo "[5/6] 위치 설정 (서울 중심)"

set_location() {
  local token="$1"
  curl -sf -X POST "$API_URL/users/me/location" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{"latitude":37.5665,"longitude":126.978,"address":"서울특별시 중구","matchRadiusKm":50}' \
    > /dev/null
}

set_location "$TOKEN_A"
set_location "$TOKEN_B"
echo "  완료"

# ── 6. 시뮬레이터 UDID 조회 + 프리빌드 + 병렬 drive ────────────────────
echo ""
echo "[6/6] 프리빌드 + flutter drive 병렬 실행"

UDID_A=$(xcrun simctl list devices | grep -E '^\s+match \(' | grep -oE '[A-F0-9-]{36}' | head -1)
UDID_B=$(xcrun simctl list devices | grep -E '^\s+kids \(' | grep -oE '[A-F0-9-]{36}' | head -1)
echo "  UDID_A (match) = $UDID_A"
echo "  UDID_B (kids)  = $UDID_B"

export UDID_A UDID_B
export SCREENSHOT_DIR_ABS="$(cd "$SCREENSHOT_DIR" && pwd)"

# ── 스크린샷 HTTP 서버 (127.0.0.1:9998) ────────────────────────────────
# Flutter 앱이 http.get('http://127.0.0.1:9998/userA_<name>') 호출 시
# 호스트에서 xcrun simctl io screenshot 즉시 실행 → 진짜 시뮬레이터 화면 캡처
SCREENSHOT_DIR="$SCREENSHOT_DIR_ABS" UDID_A="$UDID_A" UDID_B="$UDID_B" \
python3 -u -c '
import http.server, socketserver, subprocess, os
UDIDS = {"userA": os.environ["UDID_A"], "userB": os.environ["UDID_B"]}
DIR = os.environ["SCREENSHOT_DIR"]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        name = self.path.strip("/").split("?")[0]
        role = name.split("_")[0] if name else ""
        udid = UDIDS.get(role, "")
        if udid and name:
            out = os.path.join(DIR, f"{name}.png")
            try:
                subprocess.run(["xcrun","simctl","io",udid,"screenshot",out],
                               check=False, timeout=5)
                print(f"[📸] {name}.png", flush=True)
            except Exception as e:
                print(f"[📸-FAIL] {name}: {e}", flush=True)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 9998), H) as s:
    s.serve_forever()
' &
SHOT_SERVER_PID=$!
echo "  [Screenshot server] http://127.0.0.1:9998 (PID=$SHOT_SERVER_PID)"
sleep 1
# 종료 시 kill
trap "kill $SHOT_SERVER_PID 2>/dev/null || true" EXIT

# User A 실행 (빌드 + 테스트)
SCREENSHOT_DIR="$SCREENSHOT_DIR_ABS" UDID_A="$UDID_A" UDID_B="$UDID_B" \
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  --dart-define=TEST_USER_ROLE=A \
  --dart-define=TEST_API_BASE_URL="$API_URL" \
  --dart-define=TEST_ACCESS_TOKEN="$TOKEN_A" \
  --dart-define=TEST_REFRESH_TOKEN="$REFRESH_A" \
  --dart-define=TEST_USER_ID="$ID_A" \
  -d match \
  2>&1 | tee "$SCREENSHOT_DIR_ABS/userA_test.log" &
PID_A=$!
echo "  [User A] PID=$PID_A"

# 30초 sleep — A가 xcodebuild lock을 점유하는 초반만 회피 (이후 B는 캐시 덕에 빠름)
echo "  B 시작까지 30초 대기..."
sleep 30

SCREENSHOT_DIR="$SCREENSHOT_DIR_ABS" UDID_A="$UDID_A" UDID_B="$UDID_B" \
flutter drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  --dart-define=TEST_USER_ROLE=B \
  --dart-define=TEST_API_BASE_URL="$API_URL" \
  --dart-define=TEST_ACCESS_TOKEN="$TOKEN_B" \
  --dart-define=TEST_REFRESH_TOKEN="$REFRESH_B" \
  --dart-define=TEST_USER_ID="$ID_B" \
  -d kids \
  2>&1 | tee "$SCREENSHOT_DIR_ABS/userB_test.log" &
PID_B=$!
echo "  [User B] PID=$PID_B"

# 두 프로세스 대기
FAIL=0

wait $PID_A
EXIT_A=$?
[ $EXIT_A -ne 0 ] && { echo "[FAIL] User A (exit: $EXIT_A)"; FAIL=1; } || echo "[PASS] User A"

wait $PID_B
EXIT_B=$?
[ $EXIT_B -ne 0 ] && { echo "[FAIL] User B (exit: $EXIT_B)"; FAIL=1; } || echo "[PASS] User B"

# ── Cleanup: 테스트 유저 및 관련 데이터 삭제 ───────────────────────────
echo ""
echo "[Cleanup] 테스트 유저 삭제"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2" \
  "cd spots-server && set -a && source .env && set +a && \
   DB=\$(echo \"\$DATABASE_URL\" | cut -d'?' -f1) && \
   psql \"\$DB\" <<SQL
-- 의존 순서대로: match_acceptances / messages / score_histories / games /
-- matches / match_requests / pin_activities / ranking_entries /
-- sports_profiles / user_locations / social_accounts / users
DELETE FROM match_acceptances WHERE user_id IN ('$ID_A','$ID_B');
DELETE FROM messages WHERE sender_id IN ('$ID_A','$ID_B');
DELETE FROM score_histories WHERE sports_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B'));
DELETE FROM games WHERE match_id IN (SELECT id FROM matches WHERE requester_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B')) OR opponent_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B')));
DELETE FROM matches WHERE requester_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B')) OR opponent_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B'));
DELETE FROM match_requests WHERE requester_id IN ('$ID_A','$ID_B');
DELETE FROM pin_activities WHERE user_id IN ('$ID_A','$ID_B');
DELETE FROM ranking_entries WHERE sports_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B'));
DELETE FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B');
DELETE FROM user_locations WHERE user_id IN ('$ID_A','$ID_B');
DELETE FROM social_accounts WHERE user_id IN ('$ID_A','$ID_B');
DELETE FROM users WHERE id IN ('$ID_A','$ID_B');
SQL
" 2>&1 | tail -5

echo ""
echo "=================================================="
if [ $FAIL -eq 0 ]; then
  echo "  ✅ 결과: 전체 테스트 성공"
else
  echo "  ❌ 결과: 테스트 실패 — 로그 확인:"
  echo "    User A: $SCREENSHOT_DIR/userA_test.log"
  echo "    User B: $SCREENSHOT_DIR/userB_test.log"
fi
echo "  스크린샷: $SCREENSHOT_DIR"
echo "=================================================="

exit $FAIL
