#!/bin/bash
# Runs a heavy command through this Mac's shared job queue (~/.claude/bin/slot) when it's installed, so parallel
# builds, tests and MLX jobs wait their turn instead of overloading the machine. Elsewhere (GitHub's runners, another
# Mac) it runs the command straight away.
#
# Usage: scripts/queue.sh [--credits N] [--lock NAME]... [--label TEXT] -- CMD [ARGS...]
#   --credits  CPU credits the job needs, out of one per core (slot's default is 4)
#   --lock     a named lock held exclusively for the job, e.g. "mlx": only one MLX job runs at a time
# While it waits, slot prints "slot: queued ..." now and then. That's normal: the job starts by itself.
#        scripts/queue.sh --self-test     checks the option handling with and without slot
set -euo pipefail
SLOT="${SLOT_BIN:-$HOME/.claude/bin/slot}"

if [ "${1:-}" = "--self-test" ]; then
  out="$(SLOT_BIN=/nonexistent "$0" --credits 4 --lock mlx --label "a -- b" -- printf '%s|' one "two words")"
  [ "$out" = "one|two words|" ] || { echo "without slot: got '$out'" >&2; exit 1; }
  if [ -x "$SLOT" ]; then
    out="$("$0" --credits 1 --label "BackcountryAI queue.sh self-test" -- printf '%s|' one "two words")"
    [ "$out" = "one|two words|" ] || { echo "with slot: got '$out'" >&2; exit 1; }
    echo "queue.sh: ok (with and without $SLOT)"
  else
    echo "queue.sh: ok (no $SLOT here, so only the fallback was checked)"
  fi
  exit 0
fi

[ -x "$SLOT" ] && exec "$SLOT" run "$@"

# No queue: drop the options (each takes one value) and run the command.
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  case "$1" in
    --credits|--lock|--label|--kind) shift 2 ;;
    *) echo "queue.sh: unknown option $1" >&2; exit 2 ;;
  esac
done
[ "${1:-}" = "--" ] || { echo "queue.sh: put -- before the command" >&2; exit 2; }
shift
exec "$@"
