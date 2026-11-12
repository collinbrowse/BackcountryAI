#!/bin/bash
# Pulls the screenshots a UI test run kept (attachments named "NN_name") out of its result bundle.
#
# Usage: scripts/export-screenshots.sh <run.xcresult> <out-folder>
# Output: <out-folder>/NN_name.png, one per screenshot, at the simulator's native resolution.
set -euo pipefail
RESULT="${1:?usage: export-screenshots.sh <run.xcresult> <out-folder>}"
OUT="${2:?usage: export-screenshots.sh <run.xcresult> <out-folder>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$TMP" >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
python3 - "$TMP" "$OUT" <<'PY'
import json, os, re, shutil, sys
tmp, out = sys.argv[1], sys.argv[2]
count = 0
for test in json.load(open(os.path.join(tmp, "manifest.json"))):
    for a in test.get("attachments", []):
        m = re.match(r"(\d\d_[a-z0-9_]+?)(_\d+_[0-9A-F-]{36})?\.png$", a.get("suggestedHumanReadableName", ""))
        if m:
            shutil.copy(os.path.join(tmp, a["exportedFileName"]), os.path.join(out, m.group(1) + ".png"))
            count += 1
if not count:
    sys.exit("No screenshots found in the result bundle. Did the UI test fail before its first snap()?")
print(f"Exported {count} screenshots to {out}")
PY
