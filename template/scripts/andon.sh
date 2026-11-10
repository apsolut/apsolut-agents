#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# andon.sh raise "<reason>" | clear | status — stop the line for every lane.
# Any agent may RAISE (from a worktree too: the .primary pointer is followed) when it
# has evidence that continuing produces garbage: upstream work is wrong, the harness
# is broken, auth or infra is unrecoverable, a check was tampered with. One card's
# own dead end is a blocked handoff, not an Andon. Every runner checks before each
# claim and exits 5. Only the human clears it, like HOLD. clear refuses from a
# spawned worktree or a delegate. Pattern credit: orchestrate (cursor/plugins, MIT).
set -eu

WS=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$WS/.primary" ] && WS=$(cat "$WS/.primary")
F="$WS/ANDON"; LOG="$WS/agent-log.md"
WHO=${TRAIL_LANE:-${USER:-unknown}}

case "${1:-status}" in
  raise)
    [ -n "${2:-}" ] || { echo "usage: andon.sh raise \"<reason with evidence>\"" >&2; exit 2; }
    printf 'raised: %s by %s\nreason: %s\n' "$(date '+%Y-%m-%d %H:%M')" "$WHO" "$2" > "$F"
    printf '\n### andon.sh — %s\n- ANDON RAISED by %s: %s (only the human clears: sh scripts/andon.sh clear)\n' \
      "$(date +%Y-%m-%d)" "$WHO" "$2" >> "$LOG"
    sh "$WS/scripts/trail.sh" andon "line stopped" "$2" "ANDON" raised 2>/dev/null || true
    echo "ANDON raised — every lane stops before its next claim."
    ;;
  clear)
    case "$(basename "$(pwd)")" in *-wt-*)
      echo "error: clear refused inside a spawned worktree — only the human clears an Andon" >&2; exit 1;;
    esac
    [ -z "${APSOLUT_AGENT_DEPTH:-}" ] || { echo "error: clear refused for a delegate — only the human clears an Andon" >&2; exit 1; }
    [ -f "$F" ] || { echo "no Andon raised"; exit 0; }
    printf '\n### andon.sh — %s\n- ANDON CLEARED by %s (was: %s)\n' "$(date +%Y-%m-%d)" "$WHO" \
      "$(sed -n 's/^reason: //p' "$F")" >> "$LOG"
    rm -f "$F"
    echo "ANDON cleared."
    ;;
  status)
    if [ -f "$F" ]; then cat "$F"; exit 1; else echo "no Andon raised"; fi
    ;;
  *) echo "usage: andon.sh raise \"<reason>\" | clear | status" >&2; exit 2 ;;
esac
