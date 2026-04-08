#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)/test_results"
mkdir -p "$DIR"
SIM="4B7266B2-AD70-499A-9868-8F72264761F6"

screenshot() {
  xcrun simctl io "$SIM" screenshot "$DIR/$1.png" 2>/dev/null
  echo "📸 $1"
}

tap_sim() {
  # match 창 위치 직접 가져오기
  local info=$(osascript -e '
    tell application "System Events"
      tell process "Simulator"
        repeat with w in windows
          if name of w contains "match" then
            set p to position of w
            set s to size of w
            return "" & (item 1 of p) & " " & (item 2 of p) & " " & (item 1 of s) & " " & (item 2 of s)
          end if
        end repeat
      end tell
    end tell' 2>/dev/null)
  
  local wx=$(echo $info | awk '{print $1}')
  local wy=$(echo $info | awk '{print $2}')
  local ww=$(echo $info | awk '{print $3}')
  local wh=$(echo $info | awk '{print $4}')
  
  # 비율 → 정수 좌표 (타이틀바 28px)
  local pct_x=$1  # 퍼센트 (0-100)
  local pct_y=$2
  local ax=$(( wx + ww * pct_x / 100 ))
  local ay=$(( wy + 28 + (wh - 28) * pct_y / 100 ))
  
  echo "  탭: ${pct_x}%,${pct_y}% → ($ax,$ay)"
  cliclick c:$ax,$ay
}

echo "========================================="
echo "  핀돌 매칭 UI 테스트"
echo "========================================="

osascript -e 'tell application "Simulator" to activate'
sleep 1

screenshot "00_현재상태"

echo ">>> 1. 핀 탭"
tap_sim 30 97
sleep 3
screenshot "01_핀탭"

echo ">>> 2. 검색"
tap_sim 70 9
sleep 2
screenshot "02_검색"

echo ">>> 3. 첫번째 핀"
tap_sim 50 25
sleep 2
screenshot "03_핀선택"

echo ">>> 4. 랭크 매칭"
tap_sim 30 72
sleep 2
screenshot "04_매칭화면"

echo ">>> 5. 매칭 요청"
tap_sim 50 85
sleep 3
screenshot "05_요청완료"

echo "========================================="
echo "  완료! 스크린샷 확인:"
echo "========================================="
ls -1 "$DIR"/*.png | grep -E "0[0-5]_" | tail -6
