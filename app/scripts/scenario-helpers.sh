#!/bin/bash
# 공통 헬퍼 — 다른 시나리오 sh에서 `source`해서 사용.
# 함수:
#   se_init       — API_URL/EC2/PIN/유저 ID 변수 설정 + jq 의존
#   se_cleanup_db — test1/test2 매칭/게임/노쇼/이의 상태 초기화
#   se_tokens     — TOKEN_A, REFRESH_A, TOKEN_B, REFRESH_B 발급
#   se_setup_match — 매칭 요청 → 성사 → 양쪽 수락 → confirm-met. MATCH_ID, GAME_ID 세팅.
#   se_psql "SQL" — 운영 RDS 한 줄 쿼리

set -u

API_URL="${API_URL:-https://api-staging.pins.kr/v1}"
SSH_KEY="${SSH_KEY:-$HOME/WebProject2/match/spots-key.pem}"
EC2="${EC2:-ec2-user@43.203.165.114}"
FB_KEY="${FB_KEY:-AIzaSyBx002T-XCQuNOsUo0azC6-uQxejKz2EP0}"

EMAIL_A="test1@gmail.com"
EMAIL_B="test2@gmail.com"
PASSWORD="clfrwmq12"
ID_A="faf5f8ff-d996-4e10-9c91-aa5d09bf1503"
ID_B="5997ec54-36f8-437b-99b4-cd09f951d290"
PIN_NAME="몬테로이"
PIN_ID="4043f7db-9d52-434e-a5b4-e202e982110a"

se_psql() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2" "
    cd spots-server-staging && set -a && source .env && set +a
    DB=\$(echo \"\$DATABASE_URL\" | cut -d'?' -f1)
    psql \"\$DB\" -A -F '|' -t -c \"$1\"
  "
}

se_cleanup_db() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2" "
    cd spots-server-staging && set -a && source .env && set +a
    DB=\$(echo \"\$DATABASE_URL\" | cut -d'?' -f1)
    psql \"\$DB\" -v ON_ERROR_STOP=1 <<SQL
-- 매 시나리오 시작 전 테스트 계정 점수 동기화 (score range fix 회피)
UPDATE sports_profiles SET current_score=1000, display_score=1000, glicko_rating=1000, glicko_rd=80
 WHERE user_id IN ('$ID_A','$ID_B') AND sport_type='GOLF';
UPDATE matches SET status='CANCELLED', cancel_reason='scenario cleanup'
 WHERE (requester_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B'))
     OR opponent_profile_id IN (SELECT id FROM sports_profiles WHERE user_id IN ('$ID_A','$ID_B')))
   AND status IN ('PENDING_ACCEPT','CHAT','CONFIRMED','DISPUTED');
UPDATE match_requests SET status='EXPIRED' WHERE requester_id IN ('$ID_A','$ID_B') AND status='WAITING';
-- E2E 환경 한정: 24시간 중복 신고 차단을 회피하기 위해 row 자체 삭제
DELETE FROM noshow_reports
 WHERE reporter_id IN ('$ID_A','$ID_B') OR reported_user_id IN ('$ID_A','$ID_B');
UPDATE sports_profiles SET noshow_confirmed_count=0, match_ban_until=NULL, match_request_ban_until=NULL
 WHERE user_id IN ('$ID_A','$ID_B');
UPDATE users SET noshow_report_ban_until=NULL, false_noshow_count=0, status='ACTIVE'
 WHERE id IN ('$ID_A','$ID_B');
SQL
  " > /dev/null
}

_fb_login() {
  local tok=""
  for i in 1 2 3 4 5; do
    tok=$(curl -sf -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$FB_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$1\",\"password\":\"$PASSWORD\",\"returnSecureToken\":true}" 2>/dev/null \
      | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('idToken',''))" 2>/dev/null)
    if [ -n "$tok" ]; then
      echo "$tok"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: fb_login failed after 5 retries for $1" >&2
  return 1
}

_srv_login() {
  local resp=""
  for i in 1 2 3 4 5; do
    resp=$(curl -sf -X POST "$API_URL/auth/firebase/login" \
      -H "Content-Type: application/json" \
      -d "{\"idToken\":\"$1\"}" 2>/dev/null)
    if [ -n "$resp" ]; then
      echo "$resp"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: srv_login failed after 5 retries" >&2
  return 1
}

se_tokens() {
  local fa fb sa sb
  fa=$(_fb_login "$EMAIL_A")
  fb=$(_fb_login "$EMAIL_B")
  sa=$(_srv_login "$fa")
  sb=$(_srv_login "$fb")
  TOKEN_A=$(echo "$sa" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['accessToken'])" 2>/dev/null)
  REFRESH_A=$(echo "$sa" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['refreshToken'])" 2>/dev/null)
  TOKEN_B=$(echo "$sb" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['accessToken'])" 2>/dev/null)
  REFRESH_B=$(echo "$sb" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['refreshToken'])" 2>/dev/null)
  # 동적으로 user.id 추출 — staging DB는 운영과 다른 UUID 사용
  ID_A=$(echo "$sa" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['user']['id'])" 2>/dev/null)
  ID_B=$(echo "$sb" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['user']['id'])" 2>/dev/null)
  # fail-fast: 토큰 누락 시 즉시 종료해서 의미 없는 후속 호출 방지
  if [ -z "$TOKEN_A" ] || [ -z "$TOKEN_B" ] || [ -z "$ID_A" ] || [ -z "$ID_B" ]; then
    echo "ERROR: se_tokens — 토큰/ID 발급 실패 (TOKEN_A=${TOKEN_A:+set}/${TOKEN_A:-empty} TOKEN_B=${TOKEN_B:+set}/${TOKEN_B:-empty})" >&2
    exit 1
  fi
  export TOKEN_A REFRESH_A TOKEN_B REFRESH_B ID_A ID_B
}

# 매칭 요청 → 성사 → 양쪽 수락 → CHAT → confirm-met. MATCH_ID, GAME_ID 세팅.
se_setup_match() {
  local today=$(date +%Y-%m-%d)
  # 양쪽 위치/자주가는핀 세팅
  for tok in "$TOKEN_A" "$TOKEN_B"; do
    curl -sf -X POST "$API_URL/users/me/location" \
      -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
      -d '{"latitude":37.3454,"longitude":127.2592,"address":"경기 광주","matchRadiusKm":50}' >/dev/null
    curl -sf -X POST "$API_URL/pins/favorite" \
      -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
      -d "{\"pinId\":\"$PIN_ID\"}" >/dev/null
  done
  # 양쪽 매칭 요청
  for tok in "$TOKEN_A" "$TOKEN_B"; do
    curl -sf -X POST "$API_URL/matches/requests" \
      -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
      -d "{\"sportType\":\"GOLF\",\"requestType\":\"SCHEDULED\",\"pinId\":\"$PIN_ID\",\"desiredDate\":\"$today\",\"desiredTimeSlot\":\"ANY\",\"genderPreference\":\"ANY\",\"isCasual\":false}" >/dev/null
  done
  # 매칭 성사 폴링 (A 기준)
  MATCH_ID=""
  for i in $(seq 1 30); do
    local body=$(curl -sf -H "Authorization: Bearer $TOKEN_A" "$API_URL/matches")
    MATCH_ID=$(echo "$body" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('data')
if isinstance(items, dict): items=items.get('items',[])
for m in (items or []):
  if m.get('status') in ('PENDING_ACCEPT','CHAT','CONFIRMED'):
    print(m['id']); break
")
    [ -n "$MATCH_ID" ] && break
    sleep 1
  done
  [ -z "$MATCH_ID" ] && { echo "ERROR: 매칭 성사 실패" >&2; return 1; }

  # 양쪽 수락
  for tok in "$TOKEN_A" "$TOKEN_B"; do
    curl -sf -X POST "$API_URL/matches/$MATCH_ID/accept" \
      -H "Authorization: Bearer $tok" >/dev/null 2>&1 || true
  done
  sleep 2

  # 양쪽 confirm-met
  for tok in "$TOKEN_A" "$TOKEN_B"; do
    curl -sf -X POST "$API_URL/matches/$MATCH_ID/confirm-met" \
      -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
      -d '{"latitude":37.3454,"longitude":127.2592}' >/dev/null
  done

  # gameId 폴링
  GAME_ID=""
  for i in $(seq 1 30); do
    local detail=$(curl -sf -H "Authorization: Bearer $TOKEN_A" "$API_URL/matches/$MATCH_ID")
    GAME_ID=$(echo "$detail" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',{})
gid=d.get('gameId')
both=d.get('bothMetConfirmed')
if both and gid: print(gid)
")
    [ -n "$GAME_ID" ] && break
    sleep 1
  done
  [ -z "$GAME_ID" ] && { echo "ERROR: gameId 생성 실패" >&2; return 1; }

  export MATCH_ID GAME_ID
}
