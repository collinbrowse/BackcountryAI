#!/bin/bash
# Fails if a library folder contains any source whose license forbids commercial use (NC) or changes (ND).
# Usage: scripts/check-licenses.sh <library-folder>
set -euo pipefail
LIB="${1:?usage: check-licenses.sh <library-folder>}"
DB="$LIB/index.sqlite"
[ -f "$DB" ] || { echo "No index.sqlite in $LIB" >&2; exit 1; }

echo "Sources in $LIB:"
sqlite3 -separator ' | ' "file:$DB?immutable=1" \
  "SELECT key, label, COALESCE(license,'(none)'), docs FROM sources WHERE done=1 ORDER BY docs DESC"

BAD=$(sqlite3 "file:$DB?immutable=1" "SELECT key || ' (' || COALESCE(license,'no license recorded') || ')' FROM sources
  WHERE done=1 AND (license IS NULL OR license = ''
    OR license GLOB '*-NC*' OR license GLOB '*-ND*' OR license GLOB '* NC *' OR license GLOB '* ND *'
    OR license LIKE '%non-commercial%' OR license LIKE '%noncommercial%' OR license LIKE '%noderivative%')")
if [ -n "$BAD" ]; then
  echo >&2
  echo "Not allowed in a paid app (non-commercial, no-derivatives or unknown license):" >&2
  echo "$BAD" | sed 's/^/  /' >&2
  exit 1
fi
echo "OK: every source allows commercial use."
