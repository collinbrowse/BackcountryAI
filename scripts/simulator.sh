#!/bin/bash
# Prints the UDID of the simulator this checkout's tests, screenshots and previews run on, creating it if needed.
#
# On this Mac every checkout gets its own simulator, "BackcountryAI <worktree folder>" (for the main checkout,
# "BackcountryAI BackcountryAI"), an iPhone 18 Pro Max. Worktrees then never install over each other's app (they all
# share one bundle id), and ~/.claude/scripts/devtrim.mjs, which knows that naming, shuts it down when the worktree
# goes idle and deletes it with the worktree.
# On CI, or with SCREENSHOT_DEVICE set, it's the shared simulator of that name, as before: SCREENSHOT_DEVICE names
# both the simulator and its device type (default "iPhone 18 Pro Max", a 6.9" iPhone: 1320x2868 screenshots).
#
# Usage: scripts/simulator.sh            the UDID (use it as -destination "platform=iOS Simulator,id=<UDID>")
#        scripts/simulator.sh --name     its name instead
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TYPE="${SCREENSHOT_DEVICE:-iPhone 18 Pro Max}"
if [ -n "${SCREENSHOT_DEVICE:-}" ] || [ -n "${CI:-}" ]; then
  NAME="$TYPE"
else
  NAME="BackcountryAI $(basename "$ROOT")"
fi
if [ "${1:-}" = "--name" ]; then echo "$NAME"; exit 0; fi

udid() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
found = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == name]
found.sort(key=lambda d: d["state"] != "Booted")   # a booted one first, if there are several
print(found[0]["udid"] if found else "")' "$NAME"
}

ID="$(udid)"
if [ -z "$ID" ]; then
  echo "Creating simulator \"$NAME\" ($TYPE)" >&2
  ID="$(xcrun simctl create "$NAME" "$TYPE")"
fi
echo "$ID"
