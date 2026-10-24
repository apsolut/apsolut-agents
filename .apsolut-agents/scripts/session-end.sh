#!/bin/sh
# apsolut-agents: tier=0 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# session-end.sh <agent> <PUSHED|HOLD|FAILED> [--commit] [summary...]
# Verifies/append the session-end token heading, compacts an oversized log,
# regenerates the facts, and (optionally, primary worktree only) commits the
# workspace. It is a finisher, not an author — write your real prose entry first.
set -eu

usage() { echo "usage: session-end.sh <agent> <PUSHED|HOLD|FAILED> [--commit] [summary...]" >&2; exit 2; }
[ $# -ge 2 ] || usage
AGENT=$1; TOKEN=$2; shift 2
case "$TOKEN" in PUSHED|HOLD|FAILED) ;; *) echo "invalid token: $TOKEN" >&2; usage;; esac
COMMIT=no; SUMMARY=""
for a in "$@"; do
  case "$a" in
    --commit) COMMIT=yes;;
    *) SUMMARY="$SUMMARY $a";;
  esac
done
SUMMARY=${SUMMARY# }

WSLOCAL=$(cd "$(dirname "$0")/.." && pwd)
WS="$WSLOCAL"
IS_PRIMARY=yes
if [ -f "$WSLOCAL/.primary" ]; then WS=$(cat "$WSLOCAL/.primary"); IS_PRIMARY=no; fi
REPO=$(git -C "$WS" rev-parse --show-toplevel)
LOG="$WS/agent-log.md"
TODAY=$(date +%Y-%m-%d)

# 1. Token heading: append one if the last heading in the log doesn't carry a token.
LAST=$(grep '^### ' "$LOG" | tail -1 || true)
case "$LAST" in
  *PUSHED*|*HOLD*|*FAILED*)
    echo "token heading present: $LAST" ;;
  *)
    {
      echo
      echo "### $AGENT — $TODAY — $TOKEN"
      [ -n "$SUMMARY" ] && echo "$SUMMARY"
    } >> "$LOG"
    echo "appended: ### $AGENT — $TODAY — $TOKEN" ;;
esac

# 2. Compaction: past 400 lines, archive everything but the newest ~150,
#    cutting at an entry ("### ") boundary. Pointer line goes after the log header.
TOTAL=$(wc -l < "$LOG" | tr -d ' ')
if [ "$TOTAL" -gt 400 ]; then
  HDR=$(grep -n '^## Log' "$LOG" | head -1 | cut -d: -f1)
  [ -n "$HDR" ] || HDR=1
  FIRST=$(awk -v h="$HDR" 'NR>h && /^### /{print NR; exit}' "$LOG")
  TARGET=$((TOTAL - 150))
  CUT=$(awk -v t="$TARGET" 'NR>=t && /^### /{print NR; exit}' "$LOG")
  if [ -n "$FIRST" ] && [ -n "$CUT" ] && [ "$CUT" -gt "$FIRST" ]; then
    ARCH="$WS/archive/agent-log-$(date +%Y-%m).md"
    mkdir -p "$WS/archive"
    sed -n "${FIRST},$((CUT - 1))p" "$LOG" >> "$ARCH"
    PTR="_older entries: archive/$(basename "$ARCH")_"
    {
      sed -n "1,$((FIRST - 1))p" "$LOG"
      grep -qxF "$PTR" "$LOG" || { echo "$PTR"; echo; }
      sed -n "${CUT},\$p" "$LOG"
    } > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    echo "compacted: $((CUT - FIRST)) lines → archive/$(basename "$ARCH") ($(wc -l < "$LOG" | tr -d ' ') lines remain)"
  fi
fi

# 3. Regenerate facts + board.
sh "$WS/scripts/status.sh"

# 4. Optional workspace commit — primary worktree only.
if [ "$COMMIT" = yes ]; then
  if [ "$IS_PRIMARY" = no ]; then
    echo "skip --commit: coordination commits happen only from the primary worktree (WORKTREES.md §4)" >&2
  else
    WSREL=$(echo "$WS" | sed "s|^$REPO/||")
    git -C "$REPO" add "$WSREL"
    if git -C "$REPO" diff --cached --quiet; then
      echo "nothing to commit in $WSREL"
    else
      git -C "$REPO" commit -q -m "agents: $AGENT session end $TODAY ($TOKEN)"
      echo "committed workspace: agents: $AGENT session end $TODAY ($TOKEN)"
    fi
  fi
fi

# 5. Checklist.
echo "session-end: token=$TOKEN ✓ · facts regenerated ✓"
OPEN=$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ' || true)
if [ "$OPEN" -gt 1 ]; then
  echo "note: $((OPEN - 1)) secondary worktree(s) still open — worktree.sh review (read-only)"
  sh "$WS/scripts/worktree.sh" review || true
fi
[ "$TOKEN" = HOLD ] && echo "note: HOLD stands — only the human lifts it"
exit 0
