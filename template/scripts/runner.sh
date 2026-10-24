#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# runner.sh <agent> [--once] — Night Shift v0: single-lane overnight task runner.
# Per PRD (multi-model reviewed): rule-based only, no overnight merges (branches
# survive to morning), kill is terminal, claim = mkdir mutex + card rewrite,
# provider errors back off instead of tripping the breaker. See NIGHTSHIFT.md.
# Hardened per the AGY+Grok code-review round (see runs/ for the review artifacts).
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

cfg() { sed -n "s/^$1:[[:space:]]*//p" "$HB" | head -1 | tr -d '\r'; }
fm_get() { awk -v k="$2" 'NR==1&&$0~/^---\r?$/{f=1;next} f&&$0~/^---\r?$/{exit}
  f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");sub(/\r$/,"");print;exit}' "$1"; }
fm_set() { awk -v k="$2" -v v="$3" 'NR==1&&$0~/^---\r?$/{f=1;print;next}
  f&&$0~/^---\r?$/{if(!done)print k": "v;f=0;print;next}
  f&&index($0,k":")==1{print k": "v;done=1;next}{print}' \
  "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
num_or() { case "$1" in ''|*[!0-9.]*|*.*.*) echo "$2";; *) echo "$1";; esac; }

TIMEOUT_MIN=$(num_or "$(cfg card_timeout_minutes)" 45)
MAX_ATTEMPTS=$(num_or "$(cfg max_attempts_per_card)" 2)
MAX_FAILS=$(num_or "$(cfg max_consecutive_failures_lane)" 3)
BUDGET=$(num_or "$(cfg night_budget_usd)" "$(num_or "$(cfg night_budget)" 100)")
FALLBACK_COST=$(num_or "$(cfg cost_fallback_usd)" 2)
STOP=$(cfg stop_time | tr -d ':'); STOP=${STOP:-0700}
POLL=$(num_or "$(cfg idle_poll_seconds)" 300)
STALE_MIN=$(num_or "$(cfg stale_claim_minutes)" "$(num_or "$(cfg stall_claim_minutes)" 5)")
GREEN=$(cfg green_cmd)
NTFY=$(cfg notify_url)
CMD=$(cfg "cmd_$AGENT")
[ -n "$CMD" ] || { echo "error: no cmd_$AGENT in HEARTBEAT.md" >&2; exit 1; }
case "$GREEN" in ''|*"SET green_cmd"*)
  echo "error: green_cmd in HEARTBEAT.md is unset — define what green means before running nights" >&2; exit 1;;
esac

# --- card contract: filename must be exactly <id>.md ------------------------------
# pick_ready discovers cards by frontmatter id:, but claims, deps and reports all
# construct work/<id>.md from that id — a mismatched filename half-works, then every
# downstream step silently misses (cost a full night in the field, 2026-08-11).
CARD_ERRS=0
for f in "$WS"/work/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
  i=$(fm_get "$f" id)
  if [ -z "$i" ]; then
    echo "error: work/$(basename "$f") has no 'id:' in its frontmatter" >&2; CARD_ERRS=$((CARD_ERRS+1))
  elif [ "$(basename "$f")" != "$i.md" ]; then
    echo "error: work/$(basename "$f") declares 'id: $i' — rename the file to $i.md" >&2; CARD_ERRS=$((CARD_ERRS+1))
  fi
done
[ "$CARD_ERRS" -eq 0 ] || { echo "error: $CARD_ERRS bad card(s) — refusing to start the lane" >&2; exit 1; }

now_hhmm() { date +%H%M; }
in_stop_window() { awk -v n="$(now_hhmm)" -v s="$STOP" 'BEGIN{exit !(int(n)>=int(s) && int(n)<1200)}'; }
# started during the morning window (e.g. a supervised 08:00 run) → don't stop instantly;
# the stop gate re-arms once the clock leaves the window (past noon or past midnight).
ARMED=yes; in_stop_window && ARMED=no

notify() { [ -n "$NTFY" ] && curl -s -d "night-shift[$AGENT]: $1" "$NTFY" >/dev/null 2>&1 || true; }
tick() { printf 'TICK: %s %s %s\n' "$AGENT" "$(date '+%m-%d %H:%M')" "$1" >> "$LOG"; }
spent() { num_or "$(cat "$SPENDF" 2>/dev/null || echo 0)" 0; }
add_spend() { awk "BEGIN{printf \"%.2f\", $(spent) + $(num_or "$1" 0)}" > "$SPENDF.tmp" && mv "$SPENDF.tmp" "$SPENDF"; }

# --- lane singleton: one runner per agent name -----------------------------------
LANE="$WS/claims/.lane-$AGENT"
if ! mkdir "$LANE" 2>/dev/null; then
  lp=$(cat "$LANE/pid" 2>/dev/null || echo "")
  if [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null; then
    echo "error: runner for '$AGENT' already active (pid $lp)" >&2; exit 1
  fi
  rm -rf "$LANE"; mkdir "$LANE"
fi
echo $$ > "$LANE/pid"

CURRENT_ID=""
cleanup() {
  if [ -n "$CURRENT_ID" ] && [ -d "$WS/claims/$CURRENT_ID" ]; then
    rm -rf "$WS/claims/$CURRENT_ID"
    c="$WS/work/$CURRENT_ID.md"
    [ -f "$c" ] && [ "$(fm_get "$c" status)" = "writing" ] && fm_set "$c" status waiting
    tick "released claim $CURRENT_ID on exit"
  fi
  rm -rf "$LANE"
}
trap cleanup EXIT INT TERM

# --- lane preflight: prove the CLI can answer before burning cards -----------------
# One probe from an empty temp cwd (never the repo — the CLI runs with a bypassed
# permission posture). A lane whose CLI cannot answer at all — bad auth, refused
# account, dead binary — would otherwise march the whole board, charging an attempt
# plus fallback cost per card (cost a full night in the field, 2026-08-11).
probe_fail() {
  echo "error: preflight probe for '$AGENT' $1 — refusing to start the lane" >&2
  printf '%s\n' "$PROBE_OUT" | command tail -5 >&2
  tick "preflight probe FAILED ($AGENT): $1 — lane refused"
  notify "preflight probe failed ($1) — lane refused"
  exit 1
}
PROBE_DIR=$(mktemp -d)
PROBE_OUT=""
if PROBE_OUT=$( cd "$PROBE_DIR" && timeout -k 10 180 sh -c "$CMD \"\$1\"" runner "Reply with the single word: ok" 2>&1 ); then
  rm -rf "$PROBE_DIR"
else
  rm -rf "$PROBE_DIR"; probe_fail "exited non-zero"
fi
printf '%s' "$PROBE_OUT" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true' && probe_fail "returned is_error:true"
case "$PROBE_OUT" in *[Oo][Kk]*) ;; *) probe_fail "returned no 'ok'";; esac
tick "preflight probe ok ($AGENT)"

# --- boot recovery: release claims whose runner is dead ---------------------------
for c in "$WS"/claims/*/; do
  [ -d "$c" ] || continue
  id=$(basename "$c")
  case "$id" in .lane-*) continue;; esac
  pid=$(cat "$c/pid" 2>/dev/null || echo "")
  ft=$(date -r "$c" +%s 2>/dev/null || echo 0)
  age=$(( ( $(date +%s) - ft ) / 60 ))
  if { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; } && [ "$age" -ge "$STALE_MIN" ]; then
    rm -rf "$c"
    [ -f "$WS/work/$id.md" ] && fm_set "$WS/work/$id.md" status waiting
    tick "recovered stale claim $id (pid ${pid:-none} dead, ${age}m old)"
  fi
done

deps_met() { # $1 = card file → 0 if every id in after: is done (merged — review is NOT enough)
  a=$(fm_get "$1" after | tr -d '[]' | tr ',' ' ')
  for d in $a; do
    df="$WS/work/$d.md"; [ -f "$df" ] || return 1
    [ "$(fm_get "$df" status)" = "done" ] || return 1
  done
  return 0
}

pick_ready() { # print first claimable card id, or nothing
  for f in "$WS"/work/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
    i=$(fm_get "$f" id); [ -n "$i" ] || continue
    [ "$(fm_get "$f" status)" = "waiting" ] || continue
    o=$(fm_get "$f" owner)
    case "$o" in "$AGENT"|any|"<agent>"|"") ;; *) continue;; esac
    deps_met "$f" || continue
    echo "$i"; return 0
  done
  return 1
}

finish() { # $1 reason, $2 exit code
  {
    echo "# Night report — $DATE (lane: $AGENT)"
    echo
    echo "Ended: $(date '+%Y-%m-%d %H:%M') — reason: $1 — spend: \$$(spent) / \$$BUDGET"
    echo
    echo "| card | status | attempts | branch | diffstat vs $(git -C "$REPO" rev-parse --abbrev-ref HEAD) |"
    echo "|---|---|---|---|---|"
    for f in "$WS"/work/*.md; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
      id=$(fm_get "$f" id); st=$(fm_get "$f" status); br=$(fm_get "$f" branch)
      at=$(cat "$WS/runs/.attempts-$id" 2>/dev/null || echo 0)
      ds="—"
      [ -n "$br" ] && [ "$br" != "null" ] && \
        ds=$(git -C "$REPO" diff --stat "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)...$br" 2>/dev/null | tail -1 || echo "—")
      echo "| $id | $st | $at | $br | ${ds:-—} |"
    done
    echo
    echo "Branches are UNMERGED by design — \`worktree.sh review\`, then \`done <id> --merge\` for the ones you accept."
  } > "$REPORT"
  tick "night end: $1 (report: runs/$(basename "$REPORT"))"
  notify "ended: $1 — spend \$$(spent). Report ready."
  sh "$WS/scripts/status.sh" >/dev/null 2>&1 || true
  exit "${2:-0}"
}

echo "runner[$AGENT]: timeout=${TIMEOUT_MIN}m attempts=$MAX_ATTEMPTS breaker=$MAX_FAILS budget=\$$BUDGET stop=$STOP"
tick "night start (budget \$$BUDGET, stop $STOP)"
FAILS=0
BASELINE_OK=no

while :; do
  if [ "$ARMED" = no ]; then in_stop_window || ARMED=yes
  elif in_stop_window; then finish "stop_time" 0; fi
  awk "BEGIN{exit !($(spent) >= $BUDGET)}" && { notify "BUDGET CAP hit (\$$(spent))"; finish "budget" 3; }
  [ "$FAILS" -ge "$MAX_FAILS" ] && { notify "CIRCUIT BREAKER: $FAILS consecutive failures"; finish "breaker" 2; }

  ID=$(pick_ready || true)
  if [ -z "$ID" ]; then
    [ "$ONCE" = yes ] && finish "board empty" 0
    tick "idle — no ready cards"; sleep "$POLL"; continue
  fi

  mkdir "$WS/claims/$ID" 2>/dev/null || { sleep 5; continue; }
  CURRENT_ID=$ID
  echo $$ > "$WS/claims/$ID/pid"
  CARD="$WS/work/$ID.md"

  # test-first gate (PLAYBOOK §2): night cards must name a test somewhere, or declare spike: true
  if [ "$(fm_get "$CARD" spike)" != "true" ] && ! grep -qi "test" "$CARD"; then
    fm_set "$CARD" status blocked
    printf '\nAttempted: claim by runner\nFailed because: no test named on the card and spike is not true (PLAYBOOK §2)\nWould unblock: add a failing-test criterion to Done-when, or set spike: true\n' >> "$CARD"
    tick "refused $ID: test-first gate (PLAYBOOK §2)"
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
  fi
  fm_set "$CARD" owner "$AGENT"
  fm_set "$CARD" status writing
  fm_set "$CARD" claimed "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid:$$"
  fm_set "$CARD" updated "$DATE"

  BR=$(fm_get "$CARD" branch); WT=$(fm_get "$CARD" worktree)
  if [ -z "$BR" ] || [ "$BR" = "null" ] || [ ! -d "${WT:-/nonexistent}" ]; then
    sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" >/dev/null
    WT=$(fm_get "$CARD" worktree); BR=$(fm_get "$CARD" branch)
  fi
  # never run destructive git ops anywhere but a spawned worktree
  case "$(basename "$WT")" in
    *-wt-*) ;;
    *) tick "SKIP $ID: worktree path '$WT' is not a spawned worktree — refusing"
       fm_set "$CARD" status blocked
       rm -rf "$WS/claims/$ID"; CURRENT_ID=""; FAILS=$((FAILS+1)); continue;;
  esac
  PRE=$(git -C "$WT" rev-parse HEAD)

  # harness-vs-card attribution: green must pass on the PRISTINE worktree before any
  # agent runs. A worktree contains only TRACKED files and green_cmd runs with cwd
  # set to it — a relative path or untracked helper makes every card read as "card
  # failed" while the harness is broken, blocking good work and tripping the breaker
  # (field incident 2026-08-11: cost 3 cards). Checked once per night, first worktree.
  if [ "$BASELINE_OK" != yes ]; then
    if ( cd "$WT" && sh -c "$GREEN" ) > "$WS/runs/.baseline-$DATE.out" 2>&1; then
      BASELINE_OK=yes
      tick "baseline green ok on pristine worktree"
    else
      fm_set "$CARD" status waiting
      rm -rf "$WS/claims/$ID"; CURRENT_ID=""
      notify "HARNESS: green_cmd fails on a pristine worktree — night refused, no cards charged"
      tick "HARNESS FAILURE: green_cmd red on pristine worktree $WT (not a card failure) — runs/.baseline-$DATE.out"
      finish "harness: green_cmd red on pristine worktree" 4
    fi
  fi

  N=$(( $(cat "$WS/runs/.attempts-$ID" 2>/dev/null || echo 0) + 1 ))
  CB=$(num_or "$(fm_get "$CARD" budget | tr -dc '0-9')" "$TIMEOUT_MIN")
  OUT="$WS/runs/$ID-attempt$N.out"
  PREVFAIL="$WS/runs/$ID-attempt$(( N - 1 )).fail"
  PROMPT="You are agent '$AGENT' working alone, headless, in the isolated git worktree at $WT (your cwd), on branch $BR. Implement the task card below. Rules: commit your work in this worktree with clear messages; run the project's green check and iterate until it passes; do NOT touch any .apsolut-agents folder; do NOT push (this worktree's pushurl is sealed); do NOT switch branches. When done, stop.
$( [ -f "$PREVFAIL" ] && printf '\n=== PREVIOUS ATTEMPT FAILED — read this, do NOT repeat the same approach ===\n%s\n' "$(command tail -120 "$PREVFAIL")" )
=== TASK CARD ===
$(cat "$CARD")"

  tick "start $ID attempt $N (cap ${CB}m)"
  set +e
  ( cd "$WT" && timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" runner "$PROMPT" ) > "$OUT" 2>&1
  RC=$?
  set -e

  GD=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$GD" ] && rm -f "$GD/index.lock" 2>/dev/null || true

  # provider trouble (429/5xx/quota) = backoff, not a failure, not an attempt.
  # Status codes only count NEXT TO an http/status/error marker: a bare (429|50x) match
  # false-positives on commit SHAs and ordinary app output (found by adversarial review).
  if grep -qiE 'rate.?limit|quota exceeded|overloaded|too many requests|service.{0,15}unavailable|internal server error|bad gateway|gateway time.?out|(http|status( code)?|api.?error|error.?code)[^0-9A-Za-z]{0,4}(429|50[0-4]|529)([^0-9]|$)' "$OUT"; then
    tick "provider backoff on $ID (not a failure, not an attempt)"
    # salvage + pin BEFORE the reset: a throttle is not the agent's failure, and
    # destroying its uncommitted work on a 429 was pure evidence loss. The pinned
    # ref is gc-proof and invisible to branch listings; humans list/delete
    # refs/apsolut/* manually, same posture as worktree folders.
    if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
      git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
      git -C "$WT" commit -q -m "$ID: salvaged before throttle backoff (attempt $N)" || true
    fi
    [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N-backoff" HEAD 2>/dev/null || true
    git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
    git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
    fm_set "$CARD" status waiting
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""
    sleep 900; continue
  fi
  echo "$N" > "$WS/runs/.attempts-$ID"

  COST=$(grep -oE '"(total_cost_usd|costUSD|total_cost)"[: ]*[0-9.]+' "$OUT" | tail -1 | grep -o '[0-9.]*$' || true)
  add_spend "${COST:-$FALLBACK_COST}"

  # agent must still be on its card branch — anything else is a hard fail
  NOWBR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  [ "$NOWBR" = "$BR" ] || { RC=97; echo "runner: branch assert failed ($NOWBR != $BR)" >> "$OUT"; }

  if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
    git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
    git -C "$WT" commit -q -m "$ID: uncommitted work salvaged by runner (attempt $N)" || true
  fi

  echo "green_cmd @ $(git -C "$WT" rev-parse HEAD)" >> "$OUT"
  if [ "$RC" -eq 0 ] && ( cd "$WT" && sh -c "$GREEN" ) >> "$OUT" 2>&1; then
    fm_set "$CARD" status review
    FAILS=0
    printf '\n### %s — %s (night shift)\n- %s done (attempt %s): green passed, branch ready for morning review. Output: runs/%s\n' \
      "$AGENT" "$DATE" "$ID" "$N" "$(basename "$OUT")" >> "$LOG"
    tick "green $ID"
  else
    FAILS=$(( FAILS + 1 ))
    # preserve the evidence before the reset destroys it: pin the salvage commit
    # under refs/apsolut/ (gc-proof), and keep the attempt's diff + output tail as
    # failure context for the NEXT attempt — a blind retry repeats the same dead
    # end at full token cost (the Ralph-loop lesson; delegate.sh already feeds
    # humans the previous round via PREV/--note, this is the runner's equivalent).
    [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N" HEAD 2>/dev/null || true
    {
      echo "attempt $N failed (rc=$RC). Diff it tried (vs $PRE):"
      git -C "$WT" diff "$PRE" HEAD 2>/dev/null | head -400
      echo; echo "Last output (incl. green_cmd):"
      command tail -60 "$OUT"
    } > "$WS/runs/$ID-attempt$N.fail" 2>/dev/null || true
    git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
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
  rm -rf "$WS/claims/$ID"; CURRENT_ID=""
done
