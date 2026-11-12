#!/bin/bash
# Records the App Preview video: runs the scripted walkthrough (UITests/ScreenshotTests.swift,
# testPreviewWalkthrough) on a simulator while recording its screen, cuts the recording to the part between the
# test's PREVIEW_MARK start/end log lines, and encodes it the way App Store Connect requires
# (886×1920, 30 fps, H.264, 15–30 s, with a silent stereo track).
#
# Usage: scripts/record-preview.sh <simulator name or UDID> <out.mp4> [extra xcodebuild args…]
# Needs ffmpeg (brew install ffmpeg).
set -euo pipefail
DEVICE="${1:?usage: record-preview.sh <simulator> <out.mp4>}"
OUT="${2:?usage: record-preview.sh <simulator> <out.mp4>}"
shift 2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
case "$DEVICE" in
  *-*-*-*-*) DEST="platform=iOS Simulator,id=$DEVICE" ;;
  *) DEST="platform=iOS Simulator,name=$DEVICE" ;;
esac

xcrun simctl io "$DEVICE" recordVideo --codec h264 --force "$TMP/raw.mov" 2>"$TMP/rec.log" &
REC=$!
for _ in $(seq 100); do grep -q "Recording started" "$TMP/rec.log" && break; sleep 0.2; done
T0="$(python3 -c 'import time; print(time.time())')"

set +e
xcodebuild -project "$ROOT/BackcountryAI.xcodeproj" -scheme BackcountryAIScreenshots -destination "$DEST" \
  -only-testing:BackcountryAIUITests/ScreenshotTests/testPreviewWalkthrough \
  -skipMacroValidation -skipPackagePluginValidation "$@" test >"$TMP/test.log" 2>&1
STATUS=$?
set -e
kill -INT "$REC"; wait "$REC" || true
if [ "$STATUS" -ne 0 ]; then
  grep -E "error|failed" "$TMP/test.log" | tail -20
  echo "The preview walkthrough test failed; no video written." >&2
  exit 1
fi

# The test logs "PREVIEW_MARK start" / "end" with NSLog, whose lines begin with a wall-clock timestamp.
read -r START LENGTH SPEED < <(python3 - "$TMP/test.log" "$T0" <<'PY'
import re, sys
from datetime import datetime
marks = {}
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*PREVIEW_MARK (start|end)", line)
    if m:
        marks[m.group(2)] = datetime.strptime(m.group(1)[:26], "%Y-%m-%d %H:%M:%S.%f").timestamp()
if len(marks) != 2:
    sys.exit("PREVIEW_MARK lines not found in the test log")
start, length = marks["start"] - float(sys.argv[2]), marks["end"] - marks["start"]
if length < 15:
    sys.exit(f"The walkthrough ran {length:.1f}s; an App Preview must be 15-30 s. Add steps to the test.")
# Longer than 30 s: play it slightly faster rather than cutting the ending off.
print(f"{max(start, 0):.2f} {length:.2f} {max(1.0, length / 29.5):.4f}")
PY
)

mkdir -p "$(dirname "$OUT")"
ffmpeg -loglevel error -y -ss "$START" -t "$LENGTH" -i "$TMP/raw.mov" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -vf "setpts=PTS/$SPEED,scale=886:-2,crop=886:1920,fps=30,format=yuv420p" \
  -c:v libx264 -profile:v high -level 4.0 -b:v 10M -maxrate 12M -bufsize 20M \
  -c:a aac -b:a 256k -shortest -t 30 -movflags +faststart "$OUT"
echo "Wrote $OUT ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -c1-5)s, ${LENGTH}s recorded, speed ×$SPEED)"
