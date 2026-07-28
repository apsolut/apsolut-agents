#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# runner.sh <agent> [--once] — Night Shift v0: single-lane overnight task runner.
# Per PRD (multi-model reviewed): rule-based only, no overnight merges (branches
# survive to morning), kill is terminal, claim = mkdir mutex + card rewrite,
# provider errors back off instead of tripping the breaker. See NIGHTSHIFT.md.
set -eu

AGENT=${1:?usage: runner.sh <agent> [--once]}
ONCE=no; [ "${2:-}" = "--once" ] && ONCE=yes

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree" >&2; exit 1
fi
REPO=$(git -C "$WS" rev-parse --show-toplevel)
HB="$WS/HEARTBEAT.md"; LOG="$WS/agent-log.md"
DATE=$(date +%Y-%m-%d)
REPORT="$WS/runs/night-$DATE.md"; SPENDF="$WS/runs/.spend-$DATE"
mkdir -p "$WS/claims" "$WS/runs"

cfg() { sed -n "s/^$1:[[:space:]]*//p" "$HB" | head -1; }
fm_get() { awk -v k="$2" 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit}
  f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");print;exit}' "$1"; }
fm_set() { awk -v k="$2" -v v="$3" 'NR==1&&$0=="---"{f=1;print;next}
  f&&$0=="---"{f=0;print;next} f&&index($0,k":")==1{print k": "v;next}{print}' \
  "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

TIMEOUT_MIN=$(cfg card_timeout_minutes); TIMEOUT_MIN=${TIMEOUT_MIN:-45}
MAX_ATTEMPTS=$(cfg max_attempts_per_card); MAX_ATTEMPTS=${MAX_ATTEMPTS:-2}
MAX_FAILS=$(cfg max_consecutive_failures_lane); MAX_FAILS=${MAX_FAILS:-3}
BUDGET=$(cfg night_budget_usd); BUDGET=${BUDGET:-25}
FALLBACK_COST=$(cfg cost_fallback_usd); FALLBACK_COST=${FALLBACK_COST:-2}
STOP=$(cfg stop_time | tr -d ':'); STOP=${STOP:-0700}
POLL=$(cfg idle_poll_seconds); POLL=${POLL:-300}
STALE_MIN=$(cfg stale_claim_minutes); STALE_MIN=${STALE_MIN:-90}
GREEN=$(cfg green_cmd)
NTFY=$(cfg notify_url)
CMD=$(cfg "cmd_$AGENT")
[ -n "$CMD" ] || { echo "error: no cmd_$AGENT in HEARTBEAT.md" >&2; exit 1; }
[ -n "$GREEN" ] || { echo "error: no green_cmd in HEARTBEAT.md" >&2; exit 1; }

notify() { [ -n "$NTFY" ] && curl -s -d "night-shift[$AGENT]: $1" "$NTFY" >/dev/null 2>&1 || true; }
tick() { printf 'TICK: %s %s %s\n' "$AGENT" "$(date '+%m-%d %H:%M')" "$1" >> "$LOG"; }
spent() { cat "$SPENDF" 2>/dev/null || echo 0; }
add_spend() { awk "BEGIN{printf \"%.2f\", $(spent) + $1}" > "$SPENDF"; }

# --- boot recovery: clear claims whose runner is dead and old -------------------
for c in "$WS"/claims/*/; do
  [ -d "$c" ] || continue
  id=$(basename "$c"); pid=$(cat "$c/pid" 2>/dev/null || echo 0)
  age=$(( ( $(date +%s) - $(date -r "$c" +%s 2>/dev/null || date +%s) ) / 60 ))
  if ! kill -0 "$pid" 2>/dev/null && [ "$age" -ge "$STALE_MIN" ]; then
    rm -rf "$c"
    [ -f "$WS/work/$id.md" ] && fm_set "$WS/work/$id.md" status waiting
    tick "recovered stale claim $id (pid $pid dead, ${age}m old)"
  fi
done

deps_met() { # $1 = card file → 0 if every id in after: is done/review
  a=$(fm_get "$1" after | tr -d '[]' | tr ',' ' ')
  for d in $a; do
    df="$WS/work/$d.md"; [ -f "$df" ] || return 1
    case "$(fm_get "$df" status)" in done|review) ;; *) return 1;; esac
  done
  return 0
}

pick_ready() { # print first claimable card id, or nothing
  for f in "$WS"/work/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
    [ "$(fm_get "$f" status)" = "waiting" ] || continue
    o=$(fm_get "$f" owner)
    case "$o" in "$AGENT"|any|"<agent>"|"") ;; *) continue;; esac
    deps_met "$f" || continue
    fm_get "$f" id; return 0
  done
  return 1
}

finish() {
  {
    echo "# Night report — $DATE (lane: $AGENT)"
    echo
    echo "Ended: $(date '+%Y-%m-%d %H:%M') — reason: $1 — spend: \$$(spent) / \$$BUDGET"
    echo
    echo "| card | status | attempts | branch | diffstat vs $(git -C "$REPO" rev-parse --abbrev-ref HEAD) |"
    echo "|---|---|---|---|---|"
    for f in "$WS"/work/*.md; do
      case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
      id=$(fm_get "$f" id); st=$(fm_get "$f" status); br=$(fm_get "$f" branch)
      at=$(cat "$WS/runs/.attempts-$id" 2>/dev/null || echo 0)
      ds="—"
      [ -n "$br" ] && [ "$br" != "null" ] && \
        ds=$(git -C "$REPO" diff --stat "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)...$br" 2>/dev/null | tail -1 || echo "—")
      echo "| $id | $st | $at | $br | ${ds:-—} |"
    done
    echo
    echo "Branches are UNMERGED by design — review and merge selectively (\`worktree.sh done <id> --merge\`)."
  } > "$REPORT"
  tick "night end: $1 (report: runs/$(basename "$REPORT"))"
  notify "ended: $1 — spend \$$(spent). Report ready."
  sh "$WS/scripts/status.sh" >/dev/null 2>&1 || true
  exit 0
}

echo "runner[$AGENT]: timeout=${TIMEOUT_MIN}m attempts=$MAX_ATTEMPTS breaker=$MAX_FAILS budget=\$$BUDGET stop=$STOP"
tick "night start (budget \$$BUDGET, stop $STOP)"
FAILS=0

while :; do
  NOW=$(date +%H%M | sed 's/^0*//'); S=$(echo "$STOP" | sed 's/^0*//')
  [ "${NOW:-0}" -ge "${S:-700}" ] && [ "${NOW:-0}" -lt 1200 ] && finish "stop_time"
  awk "BEGIN{exit !($(spent) >= $BUDGET)}" && { notify "BUDGET CAP hit (\$$(spent))"; finish "budget"; }
  [ "$FAILS" -ge "$MAX_FAILS" ] && { notify "CIRCUIT BREAKER: $FAILS consecutive failures"; finish "breaker"; }

  ID=$(pick_ready || true)
  if [ -z "$ID" ]; then
    if ls "$WS"/claims/ 2>/dev/null | grep -q . || [ "$ONCE" = yes ]; then :; fi
    [ "$ONCE" = yes ] && finish "board empty"
    tick "idle — no ready cards"; sleep "$POLL"; continue
  fi

  mkdir "$WS/claims/$ID" 2>/dev/null || { sleep 5; continue; }
  echo $$ > "$WS/claims/$ID/pid"
  CARD="$WS/work/$ID.md"
  fm_set "$CARD" owner "$AGENT"; fm_set "$CARD" updated "$DATE"

  BR=$(fm_get "$CARD" branch); WT=$(fm_get "$CARD" worktree)
  if [ -z "$BR" ] || [ "$BR" = "null" ] || [ ! -d "${WT:-/nonexistent}" ]; then
    sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" >/dev/null
    WT=$(fm_get "$CARD" worktree)
  else
    fm_set "$CARD" status writing
  fi

  N=$(( $(cat "$WS/runs/.attempts-$ID" 2>/dev/null || echo 0) + 1 ))
  echo "$N" > "$WS/runs/.attempts-$ID"
  CB=$(fm_get "$CARD" budget); case "$CB" in ''|null) CB=$TIMEOUT_MIN;; esac
  OUT="$WS/runs/$ID-attempt$N.out"
  PROMPT="You are agent '$AGENT' working alone, headless, in the isolated git worktree at $WT (your cwd). Implement the task card below. Rules: commit your work in this worktree with clear messages; run the project's green check and iterate until it passes; do NOT touch any .apsolut-agents folder; do NOT push; do NOT switch branches. When done, stop.

=== TASK CARD ===
$(cat "$CARD")"

  tick "start $ID attempt $N (cap ${CB}m)"
  set +e
  ( cd "$WT" && timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" runner "$PROMPT" ) > "$OUT" 2>&1
  RC=$?
  set -e

  GD=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$GD" ] && rm -f "$GD/index.lock" 2>/dev/null || true

  if grep -qiE '(^|[^0-9])429([^0-9]|$)|rate.?limit|quota exceeded|overloaded' "$OUT"; then
    tick "provider backoff on $ID (not a failure)"; rm -rf "$WS/claims/$ID"
    fm_set "$CARD" status waiting; sleep 900; continue
  fi

  COST=$(grep -o '"total_cost_usd"[: ]*[0-9.]*' "$OUT" | tail -1 | grep -o '[0-9.]*$' || true)
  add_spend "${COST:-$FALLBACK_COST}"

  if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
    git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
    git -C "$WT" commit -q -m "$ID: uncommitted work salvaged by runner (attempt $N)" || true
  fi

  if [ "$RC" -eq 0 ] && ( cd "$WT" && sh -c "$GREEN" ) >> "$OUT" 2>&1; then
    fm_set "$CARD" status review
    FAILS=0
    printf '\n### %s — %s (night shift)\n- %s done (attempt %s): green passed, branch ready for morning review. Output: runs/%s\n' \
      "$AGENT" "$DATE" "$ID" "$N" "$(basename "$OUT")" >> "$LOG"
    tick "green $ID"
  else
    FAILS=$(( FAILS + 1 ))
    git -C "$WT" reset --hard -q 2>/dev/null || true
    git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
    if [ "$N" -ge "$MAX_ATTEMPTS" ]; then
      fm_set "$CARD" status blocked
      printf '\n### %s — %s (night shift)\n- %s BLOCKED after %s attempts (rc=%s). See runs/%s\n' \
        "$AGENT" "$DATE" "$ID" "$N" "$RC" "$(basename "$OUT")" >> "$LOG"
      notify "$ID blocked after $N attempts"
      tick "blocked $ID"
    else
      fm_set "$CARD" status waiting
      tick "red $ID attempt $N (rc=$RC) — will retry"
    fi
  fi
  rm -rf "$WS/claims/$ID"
done
