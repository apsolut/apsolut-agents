#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# worktree.sh spawn <agent> <task-id> — isolated checkout + branch for an agent
# worktree.sh review [task-id] — read-only morning packet (never deletes)
# worktree.sh done  <task-id> [--merge|--jar|--reject <reason>] — human cleanup
# worktree.sh list — worktree table
# See WORKTREES.md. Run from the primary worktree (spawn/done/review refuse elsewhere).
# Agents never call done. Plain done refuses a dirty tree. --jar and --reject are
# human flags: they archive runs/evidence/<id>/ first, then remove.
set -eu

usage() {
  echo "usage: worktree.sh spawn <agent> <task-id> | review [task-id] | list" >&2
  echo "       worktree.sh done <task-id> [--merge] [--jar] [--reject <reason>]" >&2
  exit 2
}
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

# Seal every remote's push URL inside this worktree only. extensions.worktreeConfig
# lives in the shared config and merely ALLOWS a per-worktree file; the pushurl
# itself is written with --worktree so the primary checkout can still push.
# A normal `git config remote.x.pushurl` (no --worktree) would block the primary.
seal_push() { # $1=worktree abs path
  git -C "$REPO" config extensions.worktreeConfig true
  sealed=0
  for r in $(git -C "$1" remote); do
    [ -n "$r" ] || continue
    git -C "$1" config --worktree "remote.${r}.pushurl" "no_push://refused"
    echo "no-push: remote.$r.pushurl = no_push://refused (this worktree only)"
    sealed=$((sealed + 1))
  done
  if [ "$sealed" -eq 0 ]; then
    echo "no-push: no remotes — nothing to seal"
  fi
}

wt_size() { # $1=path — POSIX du -sk, printed short. "-" when du is missing.
  if command -v du >/dev/null 2>&1; then
    kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
    if [ -n "${kb:-}" ]; then
      awk -v k="$kb" 'BEGIN{
        if (k >= 1048576) printf "%.1fG", k/1048576;
        else if (k >= 1024) printf "%.0fM", k/1024;
        else printf "%dK", k
      }'
      return 0
    fi
  fi
  printf '%s' "-"
}

dirty_count() { # $1=worktree — .primary is expected dirt, not the agent's work
  git -C "$1" status --porcelain 2>/dev/null | grep -v '\.apsolut-agents/\.primary' | wc -l | tr -d ' '
}

# Print one sibling. Sets nothing. Read-only.
emit_wt() { # $1=path
  path=$1
  base=$(basename "$path")
  prefix="$NAME-wt-"
  id="?"
  case "$base" in
    "$prefix"*)
      rest=${base#"$prefix"}
      id=${rest#*-}
      [ "$id" = "$rest" ] && id="$rest"
      ;;
  esac
  if [ ! -d "$path" ]; then
    echo "$id  MISSING  $path"
    echo "      next: directory is gone — inspect \`git worktree list\`, then prune by hand if you mean to"
    return 0
  fi
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  dirty=$(dirty_count "$path")
  size=$(wt_size "$path")
  if [ "$branch" = "?" ] || [ "$branch" = "HEAD" ]; then
    ahead="?"; behind="?"; contained="?"
  elif git -C "$REPO" rev-parse --verify --quiet "$branch" >/dev/null; then
    ahead=$(git -C "$REPO" rev-list --count "HEAD..$branch" 2>/dev/null || echo "?")
    behind=$(git -C "$REPO" rev-list --count "$branch..HEAD" 2>/dev/null || echo "?")
    if git -C "$REPO" merge-base --is-ancestor "$branch" HEAD 2>/dev/null; then
      contained=yes
    else
      contained=no
    fi
  else
    ahead="?"; behind="?"; contained="?"
  fi
  echo "$id  $branch  ahead=$ahead behind=$behind in-HEAD=$contained dirty=$dirty size=$size"
  echo "      path: $path"
  if [ ! -f "$WS/work/$id.md" ]; then
    echo "      next: no work/$id.md — not a spawned card; leave it until you decide by hand"
    return 0
  fi
  if [ "$dirty" -gt 0 ] && [ "$contained" = "yes" ]; then
    echo "      next: sh .apsolut-agents/scripts/worktree.sh done $id --jar"
  elif [ "$dirty" -gt 0 ]; then
    echo "      next: sh .apsolut-agents/scripts/worktree.sh done $id --reject \"<why>\""
  elif [ "$contained" = "yes" ]; then
    echo "      next: sh .apsolut-agents/scripts/worktree.sh done $id"
  else
    echo "      next: sh .apsolut-agents/scripts/worktree.sh done $id --merge"
  fi
}

archive_evidence() { # $1=worktree $2=id — copy status, diff, and small untracked files
  ev="$WS/runs/evidence/$2"
  mkdir -p "$ev/untracked"
  {
    echo "id: $2"
    echo "date: $TODAY"
    echo "worktree: $1"
    echo "branch: ${BRANCH:-?}"
  } > "$ev/meta.txt"
  git -C "$1" status --porcelain > "$ev/status.txt" 2>/dev/null || true
  git -C "$1" diff HEAD > "$ev/diff.patch" 2>/dev/null || true
  git -C "$1" ls-files --others --exclude-standard > "$ev/untracked.txt" 2>/dev/null || true
  : > "$ev/untracked-skipped.txt"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      /*|../*|*/../*) echo "skipped odd path: $f" >> "$ev/untracked-skipped.txt"; continue ;;
    esac
    src="$1/$f"
    [ -f "$src" ] || continue
    sz=$(wc -c < "$src" | tr -d ' ')
    if [ "$sz" -le 1048576 ]; then
      mkdir -p "$ev/untracked/$(dirname "$f")"
      cp "$src" "$ev/untracked/$f"
    else
      echo "skipped $sz bytes: $f" >> "$ev/untracked-skipped.txt"
    fi
  done < "$ev/untracked.txt"
  printf '%s\n' "$ev"
}

record_verdict() { # $1=verdict $2=reason $3=commit
  vf="$WS/runs/verdicts-$(date +%Y-%m).md"
  mkdir -p "$WS/runs"
  if [ ! -f "$vf" ]; then
    printf '# Verdicts %s\n\ndate | id | agent | verdict | commit | reason\n' "$(date +%Y-%m)" > "$vf"
  fi
  agent=$(printf '%s' "${BRANCH:-?/?/?}" | awk -F/ '{print $2}')
  [ -n "$agent" ] || agent="?"
  reason=$(printf '%s' "$2" | tr '\n|' ' /')
  printf '%s | %s | %s | %s | %s | %s\n' "$TODAY" "$ID" "$agent" "$1" "$3" "$reason" >> "$vf"
  echo "verdict: $1 → runs/$(basename "$vf")"
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
  seal_push "$WTABS"

  if [ -d "$WTABS/.apsolut-agents" ]; then
    printf '%s\n' "$WS" > "$WTABS/.apsolut-agents/.primary"
  else
    mkdir -p "$WTABS/.apsolut-agents"
    printf '%s\n' "$WS" > "$WTABS/.apsolut-agents/.primary"
  fi

  printf '\n### worktree.sh — %s\n- SPAWN: %s → %s at %s (pushurl sealed)\n' "$TODAY" "$AGENT" "$BRANCH" "$WTABS" >> "$LOG"

  echo "spawned: $BRANCH at $WTABS"
  echo
  echo "--- paste this to the new agent session (working dir: $WTABS) ---"
  echo "You are agent '$AGENT' working task $ID in an isolated git worktree at $WTABS"
  echo "on branch $BRANCH. This repo uses a shared multi-agent workspace: read"
  echo "$WS/README.md first. Your coordination workspace is $WS (the .primary pointer"
  echo "in your local .apsolut-agents/ points there) — talk/log/state/work files live"
  echo "there, code edits happen here. Your task file: $WS/work/$ID.md."
  echo "Push from this worktree is sealed (remote pushurl = no_push://refused)."
  echo "-------------------------------------------------------------------"
  ;;

review)
  [ $# -le 1 ] || usage
  ID=${1:-}
  paths=$(mktemp)
  git -C "$REPO" worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' > "$paths"
  if [ -n "$ID" ]; then
    found=0
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      base=$(basename "$path")
      case "$base" in
        "$NAME-wt-"*"-$ID") emit_wt "$path"; found=1 ;;
      esac
    done < "$paths"
    rm -f "$paths"
    card="$WS/work/$ID.md"
    if [ -f "$card" ]; then
      echo "  card: status=$(fm_get "$card" status) owner=$(fm_get "$card" owner) updated=$(fm_get "$card" updated)"
      br=$(fm_get "$card" branch)
      if [ -n "$br" ] && [ "$br" != "null" ] && git -C "$REPO" rev-parse --verify --quiet "$br" >/dev/null; then
        echo "  diffstat vs HEAD:"
        git -C "$REPO" diff --stat "HEAD...$br" 2>/dev/null | tail -8 | sed 's/^/    /' || true
      fi
    fi
    out=$(ls -t "$WS"/runs/"$ID"-*.out 2>/dev/null | head -1 || true)
    if [ -n "$out" ] && [ -f "$out" ]; then
      echo "  output tail: runs/$(basename "$out")"
      tail -15 "$out" | sed 's/^/    /'
    fi
    [ "$found" -eq 1 ] || echo "review: no sibling worktree found for $ID"
    exit 0
  fi
  n=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    base=$(basename "$path")
    case "$base" in
      "$NAME-wt-"*) emit_wt "$path"; n=$((n + 1)) ;;
    esac
  done < "$paths"
  rm -f "$paths"
  echo "review: $n sibling worktree(s). Read-only — nothing was removed."
  ;;

done)
  [ $# -ge 1 ] || usage
  ID=$1; shift
  MERGE=no; JAR=no; REJECT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --merge) MERGE=yes ;;
      --jar) JAR=yes ;;
      --reject)
        shift
        [ $# -ge 1 ] || { echo "error: --reject needs a reason in quotes" >&2; exit 1; }
        REJECT=$1
        ;;
      *) echo "error: unknown argument: $1" >&2; usage ;;
    esac
    shift
  done
  if [ "$MERGE" = yes ] && [ -n "$REJECT" ]; then
    echo "error: --merge and --reject cannot be combined" >&2
    exit 1
  fi
  if [ -n "$REJECT" ]; then
    case "$REJECT" in
      *[![:space:]]*) ;;
      *) echo "error: --reject reason is empty" >&2; exit 1 ;;
    esac
  fi

  WORK="$WS/work/$ID.md"
  [ -f "$WORK" ] || { echo "error: no work/$ID.md" >&2; exit 1; }
  BRANCH=$(fm_get "$WORK" branch)
  WT=$(fm_get "$WORK" worktree)
  [ -n "$BRANCH" ] && [ "$BRANCH" != "null" ] || { echo "error: work/$ID.md has no branch set" >&2; exit 1; }

  DIRTY=0
  if [ -n "$WT" ] && [ "$WT" != "null" ] && [ -d "$WT" ]; then
    DIRTY=$(dirty_count "$WT")
  fi
  if [ "$DIRTY" -gt 0 ] && [ "$JAR" = no ] && [ -z "$REJECT" ]; then
    echo "error: worktree $WT has $DIRTY uncommitted path(s) — commit them, or re-run with --jar / --reject \"reason\"" >&2
    git -C "$WT" status --porcelain | grep -v '\.apsolut-agents/\.primary' | head -30 >&2 || true
    exit 1
  fi

  EV=""
  if [ "$JAR" = yes ] || [ -n "$REJECT" ]; then
    if [ -n "$WT" ] && [ "$WT" != "null" ] && [ -d "$WT" ]; then
      EV=$(archive_evidence "$WT" "$ID")
      echo "evidence: $EV"
    else
      echo "evidence: worktree directory already gone — nothing to archive"
    fi
  fi

  HASH=$(git -C "$REPO" rev-parse --short "$BRANCH" 2>/dev/null || echo none)
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

  if [ -n "$REJECT" ]; then
    VERDICT=rejected
    fm_set "$WORK" status abandoned
    LOGACT="REJECTED"
    LOGNOTE=" [worktree removed, branch NOT merged] $REJECT"
  elif [ "$JAR" = yes ]; then
    VERDICT=jar
    fm_set "$WORK" status done
    LOGACT="JAR"
    LOGNOTE=" [worktree removed, branch NOT merged, evidence archived]"
  elif [ "$MERGE" = yes ]; then
    VERDICT=merged
    fm_set "$WORK" status done
    LOGACT="MERGED"
    LOGNOTE=""
  else
    VERDICT=removed
    fm_set "$WORK" status done
    LOGACT="REMOVED"
    LOGNOTE=" [worktree removed, branch NOT merged]"
  fi
  fm_set "$WORK" commit "$HASH"
  fm_set "$WORK" updated "$TODAY"
  record_verdict "$VERDICT" "${REJECT:-$LOGNOTE}" "$HASH"
  printf '\n### worktree.sh — %s\n- %s: %s → %s (%s)%s\n' "$TODAY" "$LOGACT" "$BRANCH" \
    "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" "$HASH" "$LOGNOTE" >> "$LOG"
  sh "$WS/scripts/status.sh"
  ;;

list)
  git -C "$REPO" worktree list
  ;;

*)
  usage
  ;;
esac
