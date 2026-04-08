#!/bin/bash
# 핀돌 매칭 테스트 스크립트 (시뮬레이터 터치 기반)
# 사용법: ./run_matching_test.sh <simulator_id> <device_name>

set -e
SIM_ID="${1:-4B7266B2-AD70-499A-9868-8F72264761F6}"
NAME="${2:-match}"
DIR="$(dirname "$0")"
STEP=0

screenshot() {
  STEP=$((STEP + 1))
  local file="$DIR/${NAME}_$(printf '%02d' $STEP)_${1}.png"
  xcrun simctl io "$SIM_ID" screenshot "$file" 2>/dev/null
  echo "[$NAME] 스텝 $STEP: $1 → $file"
}

tap() {
  # iOS 시뮬레이터 좌표 (논리적 포인트: 393x852 for iPhone 15 Pro)
  xcrun simctl io "$SIM_ID" sendkey --type tap --x "$1" --y "$2" 2>/dev/null || \
  python3 -c "
import subprocess
subprocess.run(['xcrun', 'simctl', 'io', '$SIM_ID', 'sendkey', 'tap', '$1', '$2'], capture_output=True)
" 2>/dev/null || true
}

echo "=== $NAME 매칭 테스트 시작 ==="

# 앱 실행
xcrun simctl terminate "$SIM_ID" kr.pins 2>/dev/null || true
sleep 1
xcrun simctl launch "$SIM_ID" kr.pins
sleep 8
screenshot "01_home"

# 핀 탭 탭 (바텀 네비 2번째, x=118 y=830 근처)
echo "[$NAME] 핀 탭 이동..."
# 바텀 네비 위치: 5개 아이템 균등 배분 (393/5 = 78.6)
# 홈=39, 핀=118, 매칭=197, 채팅=275, 마이=354
# y 좌표: 하단 안전영역 포함 약 820
xcrun simctl io "$SIM_ID" sendkey --type tap --x 118 --y 820 2>/dev/null || true
sleep 3
screenshot "02_pin_tab"

echo "=== $NAME 테스트 완료 ==="
