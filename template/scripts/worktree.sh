#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# worktree.sh spawn <agent> <task-id> — isolated checkout + branch for an agent
# worktree.sh done  <task-id> [--merge] — verify, (merge,) remove, record
# worktree.sh list — worktree table
# See WORKTREES.md. Run from the primary worktree (spawn/done refuse elsewhere).
set -eu

usage() { echo "usage: worktree.sh spawn <agent> <task-id> | done <task-id> [--merge] | list" >&2; exit 2; }
[ $# -ge 1 ] || usage
CMD=$1; shift

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run this from the primary worktree ($(cat "$WS/.primary")), not a secondary one" >&2
  exit 1
fi
REPO=$(git -C "$WS" rev-parse --show-toplevel)
NAME=$(basename "$REPO")
LOG="$WS/agent-log.md"
TODAY=$(date +%Y-%m-%d)

fm_set() { # $1=file $2=key $3=value — set (replace, or INSERT if missing) a frontmatter value.
  # Insert-if-missing matters: hand-written cards often lack branch:/worktree: keys, and a
  # replace-only fm_set silently drops the spawn record — the runner then refuses the card
  # with "worktree path '' is not a spawned worktree" (found by the doctor test board).
  awk -v k="$2" -v v="$3" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { if (!done) print k ": " v; infm=0; print; next }
    infm && index($0, k ":") == 1 { print k ": " v; done=1; next }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
fm_get() { # $1=file $2=key
  awk -v k="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && index($0, k ":") == 1 { sub("^" k ":[ \t]*", ""); sub("[ \t]*#.*$", ""); print; exit }
  ' "$1"
}

case "$CMD" in
spawn)
  [ $# -eq 2 ] || usage
  AGENT=$1; ID=$2
  BRANCH="agent/$AGENT/$ID"
  WT="$REPO/../$NAME-wt-$AGENT-$ID"
  WORK="$WS/work/$ID.md"

  if [ ! -f "$WORK" ]; then
    mkdir -p "$WS/work"
    sed -e "s|<ID e.g. FEAT-12 / T-01>|$ID|" \
        -e "s|^status: waiting|status: writing|" \
        -e "s|^owner: <agent>|owner: $AGENT|" \
        -e "s|^updated: <date>|updated: $TODAY|" \
        -e "s|^# <ID> — <title>|# $ID — <title>|" \
        "$WS/work/_TEMPLATE.md" > "$WORK"
    echo "created work/$ID.md — fill in title/goal"
  else
    fm_set "$WORK" status writing
    fm_set "$WORK" owner "$AGENT"
    fm_set "$WORK" updated "$TODAY"
  fi

  git -C "$REPO" worktree add "$WT" -b "$BRANCH"
  WTABS=$(cd "$WT" && pwd -P)
  fm_set "$WORK" branch "$BRANCH"
  fm_set "$WORK" worktree "$WTABS"

  if [ -d "$WTABS/.apsolut-agents" ]; then
    printf '%s\n' "$WS" > "$WTABS/.apsolut-agents/.primary"
  else
    mkdir -p "$WTABS/.apsolut-agents"
    printf '%s\n' "$WS" > "$WTABS/.apsolut-agents/.primary"
  fi

  printf '\n### worktree.sh — %s\n- SPAWN: %s → %s at %s\n' "$TODAY" "$AGENT" "$BRANCH" "$WTABS" >> "$LOG"

  echo "spawned: $BRANCH at $WTABS"
  echo
  echo "--- paste this to the new agent session (working dir: $WTABS) ---"
  echo "You are agent '$AGENT' working task $ID in an isolated git worktree at $WTABS"
  echo "on branch $BRANCH. This repo uses a shared multi-agent workspace: read"
  echo "$WS/README.md first. Your coordination workspace is $WS (the .primary pointer"
  echo "in your local .apsolut-agents/ points there) — talk/log/state/work files live"
  echo "there, code edits happen here. Your task file: $WS/work/$ID.md."
  echo "-------------------------------------------------------------------"
  ;;

done)
  [ $# -ge 1 ] || usage
  ID=$1; shift
  MERGE=no
  [ "${1:-}" = "--merge" ] && MERGE=yes
  WORK="$WS/work/$ID.md"
  [ -f "$WORK" ] || { echo "error: no work/$ID.md" >&2; exit 1; }
  BRANCH=$(fm_get "$WORK" branch)
  WT=$(fm_get "$WORK" worktree)
  [ -n "$BRANCH" ] && [ "$BRANCH" != "null" ] || { echo "error: work/$ID.md has no branch set" >&2; exit 1; }

  if [ -n "$WT" ] && [ "$WT" != "null" ] && [ -d "$WT" ]; then
    if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents/\.primary' || true)" ]; then
      echo "error: worktree $WT has uncommitted changes — commit or discard them first" >&2
      exit 1
    fi
  fi

  HASH=$(git -C "$REPO" rev-parse --short "$BRANCH")
  if [ "$MERGE" = yes ]; then
    if [ -n "$(git -C "$REPO" status --porcelain | grep -v "^.. $(basename "$WS")/" || true)" ]; then
      echo "error: primary worktree has uncommitted non-workspace changes — commit or stash before merging" >&2
      exit 1
    fi
    git -C "$REPO" merge --no-ff "$BRANCH" -m "merge $BRANCH ($ID)"
    HASH=$(git -C "$REPO" rev-parse --short HEAD)
    echo "merged: $BRANCH → $(git -C "$REPO" rev-parse --abbrev-ref HEAD) ($HASH)"
  fi

  if [ -n "$WT" ] && [ "$WT" != "null" ] && [ -d "$WT" ]; then
    case "$(basename "$WT")" in
      "$NAME"-wt-*)
        git -C "$REPO" worktree remove "$WT" --force
        echo "removed worktree: $WT" ;;
      *)
        echo "refusing to remove '$WT' — not a spawned worktree path ($NAME-wt-*); remove manually if intended" >&2 ;;
    esac
  fi
  if [ "$MERGE" = yes ]; then
    git -C "$REPO" branch -d "$BRANCH" && echo "deleted branch: $BRANCH"
  else
    echo "kept branch: $BRANCH (not merged — delete manually when settled)"
  fi

  fm_set "$WORK" status done
  fm_set "$WORK" commit "$HASH"
  fm_set "$WORK" updated "$TODAY"
  printf '\n### worktree.sh — %s\n- MERGED: %s → %s (%s)%s\n' "$TODAY" "$BRANCH" \
    "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" "$HASH" \
    "$( [ "$MERGE" = yes ] || echo ' [worktree removed, branch NOT merged]')" >> "$LOG"
  sh "$WS/scripts/status.sh"
  ;;

list)
  git -C "$REPO" worktree list
  ;;

*)
  usage
  ;;
esac
