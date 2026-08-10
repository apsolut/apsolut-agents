#!/bin/sh
# apsolut-agents: tier=0 kind=doc
# status.sh — render STATUS.md + the facts block of state/PROJECT_STATE.md from git.
# Pure derivation: run it as often as you like; only the timestamp changes.
# Works from the primary worktree or a secondary one (follows .primary).
set -eu

WS=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$WS/.primary" ] && WS=$(cat "$WS/.primary")
REPO=$(git -C "$WS" rev-parse --show-toplevel)
NOW=$(date '+%Y-%m-%d %H:%M')

# --- helper: read one key from a work file's flat-YAML frontmatter ---------------
fm_get() { # $1=file $2=key
  awk -v k="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm {
      if (index($0, k ":") == 1) {
        sub("^" k ":[ \t]*", "")
        sub("[ \t]*#.*$", "")
        print; exit
      }
    }' "$1"
}

# --- git facts -------------------------------------------------------------------
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
if UPSTREAM=$(git -C "$REPO" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null); then
  BEHIND=$(echo "$UPSTREAM" | awk '{print $1}')
  AHEAD=$(echo "$UPSTREAM" | awk '{print $2}')
  SHIP="$AHEAD ahead / $BEHIND behind upstream"
else
  SHIP="no upstream configured"
fi
DIRTY=$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')
LOG="$WS/agent-log.md"
LOGLINES=0; [ -f "$LOG" ] && LOGLINES=$(wc -l < "$LOG" | tr -d ' ')
LASTTOKEN="(none)"
if [ -f "$LOG" ]; then
  # -vF '<' drops the protocol's own example line ("### <Agent> — <date> — PUSHED | …"),
  # which otherwise reports as the last session forever on a fresh install.
  t=$(grep '^### ' "$LOG" | grep -E 'PUSHED|HOLD|FAILED' | grep -vF '<' | tail -1 || true)
  [ -n "$t" ] && LASTTOKEN=$(echo "$t" | sed 's/^### //')
fi

# --- worktrees (porcelain: blocks of "worktree <path>" / "HEAD" / "branch") ------
WT_ROWS=""
WT_PATHS=$(git -C "$REPO" worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')
PRIMARY_WT=$(echo "$WT_PATHS" | head -1)
for wt in $WT_PATHS; do
  [ "$wt" = "$PRIMARY_WT" ] && continue
  wb=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  wc_=$(git -C "$wt" log -1 --oneline 2>/dev/null || echo "?")
  wd=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  WT_ROWS="${WT_ROWS}| \`$wt\` | \`$wb\` | $wc_ | $wd |
"
done
[ -z "$WT_ROWS" ] && WT_ROWS="| _(none)_ | — | — | — |
"

# --- work units + stale detection ------------------------------------------------
WORK_ROWS=""
WARNINGS=""
if [ -d "$WS/work" ]; then
  for f in "$WS"/work/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
    id=$(fm_get "$f" id);       [ -n "$id" ] || id="?"
    if [ "$id" != "?" ] && [ "$(basename "$f")" != "$id.md" ]; then
      WARNINGS="${WARNINGS}- ⚠ \`work/$(basename "$f")\` declares \`id: $id\` — runner/delegate key everything on \`work/$id.md\` and will silently miss it; rename the file
"
    fi
    st=$(fm_get "$f" status);   [ -n "$st" ] || st="?"
    if [ "$st" = "waiting" ]; then
      ok=yes
      for d in $(fm_get "$f" after | tr -d '[]' | tr ',' ' '); do
        # done ONLY — mirrors runner.sh deps_met: review is unmerged, so its code is
        # invisible to a dependent branch and the night runner will not start the card.
        case "$(fm_get "$WS/work/$d.md" status 2>/dev/null)" in done) ;; *) ok=no;; esac
      done
      if [ "$ok" = yes ]; then st="waiting (ready)"; else
        st="waiting (deps)"
        WARNINGS="${WARNINGS}- ⚠ \`$id\` waits on cards that are not done — \`after:\` clears only on MERGE, so an overnight run will never start it (NIGHTSHIFT.md)
"
      fi
    fi
    ow=$(fm_get "$f" owner);    [ -n "$ow" ] || ow="?"
    ti=$(fm_get "$f" title);    [ -n "$ti" ] || ti="?"
    ne=$(fm_get "$f" needs);    [ -n "$ne" ] || ne="[]"
    br=$(fm_get "$f" branch);   [ -n "$br" ] || br="null"
    up=$(fm_get "$f" updated);  [ -n "$up" ] || up="?"
    WORK_ROWS="${WORK_ROWS}| $id | $st | $ow | $ti | $ne | $br | $up |
"
    if [ "$st" = "writing" ] && [ "$br" != "null" ] && [ -n "$br" ]; then
      if ! echo "$WT_PATHS" | while read -r p; do git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null; done | grep -qx "$br"; then
        WARNINGS="${WARNINGS}- ⚠ \`$id\` claims \`writing\` on \`$br\` but no live worktree is on that branch (stale?)
"
      fi
    fi
  done
fi
[ -z "$WORK_ROWS" ] && WORK_ROWS="| _(none)_ | — | — | — | — | — | — |
"

# --- more warnings ----------------------------------------------------------------
[ "$LOGLINES" -gt 400 ] && WARNINGS="${WARNINGS}- ⚠ agent-log.md is $LOGLINES lines (>400) — run scripts/session-end.sh to compact
"
for f in README.md INSTALL.md PROJECT.md PROTOCOL.md WORKTREES.md CLAUDE-SNIPPET.md \
         STATUS.md agent-log.md state/PROJECT_STATE.md decisions/DECISIONS.md \
         agents/agent-TEMPLATE.md work/_TEMPLATE.md runs/README.md; do
  [ -f "$WS/$f" ] || continue
  head -5 "$WS/$f" | grep -q "apsolut-agents: tier=" || \
    WARNINGS="${WARNINGS}- ⚠ \`$f\` is missing its tier label
"
done
NEXTD=""
if [ -f "$WS/decisions/DECISIONS.md" ]; then
  hi=$(grep -o 'D-[0-9][0-9]*' "$WS/decisions/DECISIONS.md" | sed 's/D-//' | sort -n | tail -1 || true)
  [ -n "$hi" ] && NEXTD="- next decision id: D-$(printf '%03d' $((hi + 1)))
"
fi
[ -z "$WARNINGS" ] && WARNINGS="- _(none)_
"

# --- render STATUS.md (Tier 2 file — only if it exists) ---------------------------
if [ -f "$WS/STATUS.md" ]; then
  cat > "$WS/STATUS.md" <<EOF
<!-- apsolut-agents: tier=2 kind=generated -->
<!-- GENERATED by scripts/status.sh — do not hand-edit. Source of truth: work/*.md + git. -->

# STATUS board

_Last generated: $NOW by status.sh_

## Work units

| id | status | owner | title | needs | branch | updated |
|----|--------|-------|-------|-------|--------|---------|
$(printf '%s' "$WORK_ROWS")

Status set: \`waiting\` · \`writing\` · \`need-feedback\` · \`review\` · \`done\` · \`hold\` · \`blocked\` · \`abandoned\`

## Worktrees

| path | branch | last commit | dirty files |
|------|--------|-------------|-------------|
$(printf '%s' "$WT_ROWS")

## Ship

| | |
|--|--|
| Branch | \`$BRANCH\` |
| Ahead/behind upstream | $SHIP |
| Dirty files | $DIRTY |
| Last session token | $LASTTOKEN |

## Warnings

$(printf '%s' "$WARNINGS")
$(printf '%s' "$NEXTD")
EOF
fi

# --- refresh the facts block in state/PROJECT_STATE.md ----------------------------
STATE="$WS/state/PROJECT_STATE.md"
if [ -f "$STATE" ] && grep -q "facts:begin" "$STATE"; then
  FACTS=$(mktemp)
  {
    echo "_Generated $NOW by status.sh — do not hand-edit this block._"
    echo
    echo "| | |"
    echo "|--|--|"
    echo "| Branch | \`$BRANCH\` |"
    echo "| Ahead/behind upstream | $SHIP |"
    echo "| Dirty files | $DIRTY |"
    echo "| Worktrees | $(echo "$WT_PATHS" | wc -l | tr -d ' ') (incl. primary) |"
    echo "| Last session token | $LASTTOKEN |"
    echo "| agent-log.md | $LOGLINES lines |"
    echo
    echo "Recent commits:"
    echo '```'
    git -C "$REPO" log -5 --oneline 2>/dev/null || echo "(no commits)"
    echo '```'
  } > "$FACTS"
  awk -v factsfile="$FACTS" '
    /facts:begin/ { print; while ((getline l < factsfile) > 0) print l; close(factsfile); inblock=1; next }
    /facts:end/   { inblock=0; print; next }
    !inblock      { print }
  ' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  rm -f "$FACTS"
fi

# --- console summary --------------------------------------------------------------
echo "status.sh — $NOW"
echo "  branch: $BRANCH · $SHIP · dirty: $DIRTY"
echo "  last session: $LASTTOKEN"
[ -f "$WS/STATUS.md" ] && echo "  wrote: STATUS.md"
echo "  wrote: state/PROJECT_STATE.md (facts block)"
printf '%s' "$WARNINGS" | grep -v '(none)' || true
