#!/bin/bash
# 마지막 시나리오 실행 결과를 test_results/latest/ 로 정리 + webm→mp4 변환.
# 이전 test_results 는 통째로 삭제 후 새로 생성 (누적 X).
#
# 사용:  bash scripts/organize-results.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$APP_DIR/.." && pwd)"

OUT_DIR="$ROOT_DIR/test_results/latest"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/flutter" "$OUT_DIR/admin" "$OUT_DIR/logs"

echo "▶ 결과 정리 시작 → $OUT_DIR"

# ─── Flutter 스크린샷 — 모든 시나리오를 한 폴더에 flat 저장 ─────
# 파일명: S{N}_{role}_{step}.png  (예: S1_A_01_home.png)
for scn in 1 2 3; do
  LATEST=$(ls -1dt "$APP_DIR/test_screenshots/scenario${scn}_"* 2>/dev/null | head -1)
  if [ -n "$LATEST" ] && [ -d "$LATEST" ]; then
    cnt=0
    for f in "$LATEST"/userA_*.png; do
      [ -f "$f" ] || continue
      bn=$(basename "$f")
      # userA_01_home.png → S1_A_01_home.png
      newname="S${scn}_A_${bn#userA_}"
      cp -a "$f" "$OUT_DIR/flutter/$newname"
      cnt=$((cnt+1))
    done
    for f in "$LATEST"/userB_*.png; do
      [ -f "$f" ] || continue
      bn=$(basename "$f")
      newname="S${scn}_B_${bn#userB_}"
      cp -a "$f" "$OUT_DIR/flutter/$newname"
      cnt=$((cnt+1))
    done
    # 로그는 별도 폴더에
    cp -a "$LATEST"/*.log "$OUT_DIR/logs/S${scn}_" 2>/dev/null || true
    for lf in "$LATEST"/*.log; do
      [ -f "$lf" ] || continue
      cp -a "$lf" "$OUT_DIR/logs/S${scn}_$(basename "$lf")"
    done
    echo "  flutter S${scn}: PNG ${cnt}건  ($(basename "$LATEST"))"
  fi
done

# ─── Admin Playwright — 시나리오 sh가 archive한 폴더 + 최신 test-results ─
# 통합 sh가 각 시나리오 직후 _admin_archive_<stamp>/ 로 즉시 복사함 → 가장 최근 archive를 사용
ADMIN_ARCH=$(ls -1dt "$APP_DIR/test_screenshots/_admin_archive_"* 2>/dev/null | head -1)
PW_RESULTS="${ADMIN_ARCH:-$ROOT_DIR/admin-e2e/test-results}"
if [ -d "$PW_RESULTS" ]; then
  for d in "$PW_RESULTS"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    # 한글 이름 → ASCII 약식 디렉터리명
    case "$name" in
      *scenario-1-noshow*) short="scenario-1-noshow" ;;
      *scenario-2-dispute*) short="scenario-2-dispute" ;;
      *scenario-verify-pages*) short="scenario-verify-pages" ;;
      *) short="$name" ;;
    esac
    DEST="$OUT_DIR/admin/$short"
    mkdir -p "$DEST"
    cp -a "$d"/*.png "$DEST/" 2>/dev/null || true
    cp -a "$d"/*.zip "$DEST/" 2>/dev/null || true
    # webm → mp4 변환 (ffmpeg 있을 때만)
    if [ -f "$d/video.webm" ]; then
      if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -i "$d/video.webm" \
          -c:v libx264 -profile:v baseline -level 3.0 -pix_fmt yuv420p \
          -preset fast -crf 23 -movflags +faststart \
          "$DEST/video.mp4" 2>/dev/null
        if [ -f "$DEST/video.mp4" ]; then
          echo "  admin/$short: video.webm → video.mp4 변환 완료"
        else
          cp "$d/video.webm" "$DEST/"
          echo "  admin/$short: ffmpeg 실패 — webm 그대로 복사"
        fi
      else
        cp "$d/video.webm" "$DEST/"
        echo "  admin/$short: ffmpeg 미설치 — webm 그대로 복사 (brew install ffmpeg)"
      fi
    fi
    PNG_COUNT=$(ls "$DEST"/*.png 2>/dev/null | wc -l | xargs)
    echo "  admin/$short: PNG ${PNG_COUNT}건"
  done
fi

# ─── Summary 로그 (가장 최근) ─────────────────────────────────
LATEST_SUMMARY=$(ls -1t "$APP_DIR/test_screenshots/all_scenarios_"*.log 2>/dev/null | head -1)
if [ -n "$LATEST_SUMMARY" ]; then
  cp "$LATEST_SUMMARY" "$OUT_DIR/summary.log"
fi

# ─── README.md ───────────────────────────────────────────────
cat > "$OUT_DIR/README.md" <<EOF
# 마지막 E2E 회귀 결과

생성: $(date '+%Y-%m-%d %H:%M:%S')

## 구조

\`\`\`
test_results/latest/
├── summary.log              # 7개 시나리오 PASS/FAIL 요약
├── flutter/
│   ├── scenario1/           # 시뮬레이터 'match'(A) / 'kids'(B) 스크린샷
│   │   ├── userA_01_home.png ~ userA_05_*.png
│   │   ├── userB_01_*.png ~ userB_05_*.png
│   │   ├── userA.log  userB.log
│   │   └── admin.log
│   ├── scenario2/           # (동일 구조)
│   └── scenario3/
└── admin/
    ├── scenario-1-noshow/
    │   ├── 01_dashboard.png  02_noshow_list.png
    │   │   03_approve_modal.png  04_after_approve.png
    │   ├── video.mp4        # mac QuickTime 재생 가능
    │   └── trace.zip        # npx playwright show-trace 로 인터랙티브 재생
    ├── scenario-2-dispute/  # 5장 + video.mp4 + trace.zip
    └── scenario-verify-pages/  # admin 7개 페이지 캡처
\`\`\`

## 빠른 명령

\`\`\`bash
# Finder로 열기
open test_results/latest

# Playwright HTML 리포트 (스텝별 인라인 스크린샷)
cd admin-e2e && npx playwright show-report

# trace 재생
cd admin-e2e && npx playwright show-trace test-results/scenario-2-dispute-*-chromium/trace.zip
\`\`\`
EOF

echo ""
echo "✅ 정리 완료 → $OUT_DIR"
echo "  open $OUT_DIR"
