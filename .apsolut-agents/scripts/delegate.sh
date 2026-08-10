#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# delegate.sh — in-session delegation: one agent drives ANOTHER agent's CLI headless,
# tracks it, sends follow-up rounds, and stops it. The symmetric counterpart to
# runner.sh: same card / claim / spend state, but a foreman is present and decides.
#
#   delegate.sh run <agent> <task-id> [--detach] [--note "..."] [--budget <min>]
#   delegate.sh status                  # what's running, which round, spend so far
#   delegate.sh tail <task-id> [lines]  # live progress of a detached delegation
#   delegate.sh stop <task-id>          # kill, salvage-commit, release the claim
#
# Follow-up = `run` again on the same id with --note; the worktree and branch are reused.
# Shares claims/ + work/<id>.md + runs/.spend-<date> with runner.sh, so an in-session
# delegation and an overnight lane can never double-claim the same card.
# Full protocol, caps and rationale: DELEGATION.md.
set -eu

usage() {
  echo "usage: delegate.sh run <agent> <task-id> [--detach] [--note \"...\"] [--budget <min>]" >&2
  echo "       delegate.sh status | tail <task-id> [lines] | stop <task-id>" >&2
  exit 2
}
[ $# -ge 1 ] || usage
SUB=$1; shift

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: delegate from the primary worktree ($(cat "$WS/.primary")), not a secondary one" >&2
  exit 1
fi
HB="$WS/HEARTBEAT.md"; LOG="$WS/agent-log.md"
DATE=$(date +%Y-%m-%d)
SPENDF="$WS/runs/.spend-$DATE"
mkdir -p "$WS/claims" "$WS/runs"

cfg() { [ -f "$HB" ] && sed -n "s/^$1:[[:space:]]*//p" "$HB" | head -1 | tr -d '\r' || true; }
num_or() { case "$1" in ''|*[!0-9.]*|*.*.*) echo "$2";; *) echo "$1";; esac; }
fm_get() { awk -v k="$2" 'NR==1&&$0~/^---\r?$/{f=1;next} f&&$0~/^---\r?$/{exit}
  f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");sub(/\r$/,"");print;exit}' "$1"; }
fm_set() { awk -v k="$2" -v v="$3" 'NR==1&&$0~/^---\r?$/{f=1;print;next}
  f&&$0~/^---\r?$/{if(!done)print k": "v;f=0;print;next}
  f&&index($0,k":")==1{print k": "v;done=1;next}{print}' \
  "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
tick() { printf 'TICK: delegate %s %s\n' "$(date '+%m-%d %H:%M')" "$1" >> "$LOG"; }
spent() { num_or "$(cat "$SPENDF" 2>/dev/null || echo 0)" 0; }
add_spend() { awk "BEGIN{printf \"%.2f\", $(spent) + $(num_or "$1" 0)}" > "$SPENDF.tmp" && mv "$SPENDF.tmp" "$SPENDF"; }

# every cap has a built-in default: HEARTBEAT.md is kind=instance, so an existing
# install will NOT receive the new keys on --refresh. Never require them.
MAXDEPTH=$(num_or "$(cfg delegate_max_depth)" 2)
MAXCONC=$(num_or "$(cfg delegate_max_concurrent)" 2)
MAXROUNDS=$(num_or "$(cfg delegate_max_rounds)" 4)
TIMEOUT_MIN=$(num_or "$(cfg delegate_timeout_minutes)" "$(num_or "$(cfg card_timeout_minutes)" 45)")
BUDGET=$(num_or "$(cfg delegate_budget_usd)" "$(num_or "$(cfg night_budget_usd)" 25)")
FALLBACK_COST=$(num_or "$(cfg cost_fallback_usd)" 2)
GREEN=$(cfg green_cmd)

active_claims() { # ids of every claim except the runner lane singletons
  for c in "$WS"/claims/*/; do
    [ -d "$c" ] || continue
    id=$(basename "$c"); case "$id" in .lane-*) continue;; esac
    echo "$id"
  done
}

case "$SUB" in
# ---------------------------------------------------------------- status
status)
  printf '%-12s %-8s %-8s %-6s %-8s %s\n' ID AGENT VIA ROUND STATE OUTPUT
  found=no
  for id in $(active_claims); do
    found=yes
    c="$WS/claims/$id"
    ag=$(cat "$c/agent" 2>/dev/null || echo '?')
    via=$(cat "$c/via" 2>/dev/null || echo 'runner')
    rd=$(cat "$WS/runs/.rounds-$id" 2>/dev/null || echo '-')
    ap=$(cat "$c/agent.pid" 2>/dev/null || cat "$c/pid" 2>/dev/null || echo '')
    if [ -n "$ap" ] && kill -0 "$ap" 2>/dev/null; then st=running; else st=stale; fi
    out=$(ls -t "$WS"/runs/"$id"-delegate*.out 2>/dev/null | head -1 || true)
    printf '%-12s %-8s %-8s %-6s %-8s %s\n' "$id" "$ag" "$via" "$rd" "$st" "${out##*/}"
  done
  [ "$found" = no ] && echo "(no active claims)"
  echo
  echo "spend today: \$$(spent) / \$$BUDGET   caps: depth<$MAXDEPTH concurrent<=$MAXCONC rounds<=$MAXROUNDS"
  echo "cards in review (ready for you to judge):"
  for f in "$WS"/work/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _TEMPLATE.md) continue;; esac
    [ "$(fm_get "$f" status)" = "review" ] || continue
    echo "  $(fm_get "$f" id)  branch=$(fm_get "$f" branch)"
  done
  ;;

# ---------------------------------------------------------------- tail
tail)
  [ $# -ge 1 ] || usage
  ID=$1; N=$(num_or "${2:-40}" 40)
  OUT=$(ls -t "$WS"/runs/"$ID"-delegate*.out 2>/dev/null | head -1 || true)
  [ -n "$OUT" ] || { echo "error: no delegation output for '$ID' yet" >&2; exit 1; }
  c="$WS/claims/$ID"
  ap=$(cat "$c/agent.pid" 2>/dev/null || echo '')
  if [ -n "$ap" ] && kill -0 "$ap" 2>/dev/null; then
    echo "--- $ID: RUNNING (pid $ap) — last $N lines of ${OUT##*/} ---"
  else
    echo "--- $ID: not running — last $N lines of ${OUT##*/} ---"
  fi
  command tail -n "$N" "$OUT"
  ;;

# ---------------------------------------------------------------- stop
stop)
  [ $# -ge 1 ] || usage
  ID=$1
  c="$WS/claims/$ID"
  [ -d "$c" ] || { echo "error: no active claim for '$ID'" >&2; exit 1; }
  # flag first: the flag is what makes the parent stand down — its `wait` returns and
  # it sees `stopped`, so it neither releases the claim nor writes RESULT bookkeeping.
  # Read BOTH pids before killing anything (killing the parent can tear down the claim
  # dir contents), then kill the agent CLI FIRST: killing the parent first orphans a
  # bypass-permissions agent that keeps running and spending unsupervised.
  : > "$c/stopped"
  AP=$(cat "$c/agent.pid" 2>/dev/null || echo '')
  PP=$(cat "$c/pid" 2>/dev/null || echo '')
  for p in $AP $PP; do
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      sleep 2
      kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null || true
      echo "killed pid $p"
    fi
  done
  CARD="$WS/work/$ID.md"
  if [ -f "$CARD" ]; then
    WT=$(fm_get "$CARD" worktree)
    case "$(basename "${WT:-none}")" in
      *-wt-*)
        gd=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
        [ -n "$gd" ] && rm -f "$gd/index.lock" 2>/dev/null || true
        if [ -n "$(git -C "$WT" status --porcelain 2>/dev/null | grep -v '\.apsolut-agents' || true)" ]; then
          git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
          git -C "$WT" commit -q -m "$ID: work salvaged on delegate stop" || true
          echo "salvage-committed uncommitted work in $WT"
        fi ;;
    esac
    fm_set "$CARD" status waiting
  fi
  rm -rf "$c"
  # a killed round consumed tokens and still counts: charge the fallback and keep the
  # round counter as-is, or stop-and-redispatch would be an unlimited free retry loop.
  add_spend "$FALLBACK_COST"
  tick "STOP $ID (killed by foreman, claim released, work salvaged)"
  echo "stopped: $ID — card back to waiting, branch kept for inspection"
  echo "  charged \$$FALLBACK_COST to today's ledger (now \$$(spent)); the round still counts"
  ;;

# ---------------------------------------------------------------- run
run|--detached-child)
  [ $# -ge 2 ] || usage
  AGENT=$1; ID=$2; shift 2
  DETACH=no; NOTE=""; CBUDGET=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --detach) DETACH=yes ;;
      --note)   shift; NOTE=${1:?--note needs a value} ;;
      --budget) shift; CBUDGET=${1:?--budget needs a value} ;;
      *)        echo "unknown flag: $1" >&2; usage ;;
    esac
    shift
  done

  CMD=$(cfg "cmd_$AGENT")
  [ -n "$CMD" ] || { echo "error: no 'cmd_$AGENT:' in HEARTBEAT.md — the human defines each agent's headless command and its permission posture there" >&2; exit 1; }
  CARD="$WS/work/$ID.md"
  [ -f "$CARD" ] || { echo "error: no work/$ID.md — write the card first (copy work/_TEMPLATE.md). A delegation without a card has nothing to verify against. NOTE: the card's FILENAME must be exactly <id>.md." >&2; exit 1; }
  CID=$(fm_get "$CARD" id)
  [ "$CID" = "$ID" ] || { echo "error: work/$ID.md declares 'id: ${CID:-<none>}' — filename and id: must match (claims, deps and reports are all keyed by <id>.md)" >&2; exit 1; }

  # --- guards (all fail closed) -------------------------------------------------
  DEPTH=$(num_or "${APSOLUT_AGENT_DEPTH:-0}" 0)
  if [ "$DEPTH" -ge "$MAXDEPTH" ]; then
    echo "error: delegation depth $DEPTH >= delegate_max_depth ($MAXDEPTH) — you were yourself spawned as a delegate; do this work yourself or hand it back to the foreman" >&2
    exit 1
  fi
  # checked in the parent AND in the detached child: the parent holds no claim yet, so
  # N rapid `run --detach` calls all pass the parent check at the same instant. The child
  # re-checks after the others have claimed, which is what actually enforces the cap.
  NACTIVE=$(active_claims | grep -c . || true)
  if [ "${NACTIVE:-0}" -ge "$MAXCONC" ]; then
    echo "error: $NACTIVE active claims >= delegate_max_concurrent ($MAXCONC) — 'delegate.sh status', then stop or accept one before starting another" >&2
    exit 1
  fi
  if awk "BEGIN{exit !($(spent) >= $BUDGET)}"; then
    echo "error: today's spend \$$(spent) has reached \$$BUDGET (delegate_budget_usd) — a human raises this, not an agent" >&2
    exit 1
  fi
  ROUND=$(( $(num_or "$(cat "$WS/runs/.rounds-$ID" 2>/dev/null || echo 0)" 0) + 1 ))
  if [ "$ROUND" -gt "$MAXROUNDS" ]; then
    echo "error: $ID already had $MAXROUNDS delegation rounds (delegate_max_rounds) — more rounds is a smell: re-scope the card, take it yourself, or escalate to the human" >&2
    exit 1
  fi

  # --- detach: re-invoke self in the background so the parent holds no claim -----
  if [ "$DETACH" = yes ]; then
    set -- --detached-child "$AGENT" "$ID"
    [ -n "$NOTE" ] && set -- "$@" --note "$NOTE"
    [ -n "$CBUDGET" ] && set -- "$@" --budget "$CBUDGET"
    nohup sh "$0" "$@" >> "$WS/runs/$ID-delegate.launch" 2>&1 &
    echo "detached: $AGENT on $ID (round $ROUND) — track with:"
    echo "  sh .apsolut-agents/scripts/delegate.sh status"
    echo "  sh .apsolut-agents/scripts/delegate.sh tail $ID"
    exit 0
  fi

  # --- claim (same mutex runner.sh uses) ----------------------------------------
  mkdir "$WS/claims/$ID" 2>/dev/null || { echo "error: $ID is already claimed (a runner lane or another delegation owns it) — 'delegate.sh status'" >&2; exit 1; }
  CLAIM="$WS/claims/$ID"
  echo $$ > "$CLAIM/pid"; echo "$AGENT" > "$CLAIM/agent"; echo delegate > "$CLAIM/via"
  # count the round at DISPATCH, not completion: otherwise stop-and-redispatch evades the cap
  echo "$ROUND" > "$WS/runs/.rounds-$ID"
  RELEASED=no
  cleanup() {
    [ "$RELEASED" = yes ] && return 0
    RELEASED=yes
    # `delegate.sh stop` owns the teardown: it salvages, resets the card and removes
    # the claim itself. A parent killed by stop must not delete the stopped flag and
    # agent.pid out from under it — that would orphan the agent stop is about to kill.
    [ -f "$CLAIM/stopped" ] && return 0
    if [ -d "$CLAIM" ]; then
      [ "$(fm_get "$CARD" status)" = "writing" ] && fm_set "$CARD" status waiting
      rm -rf "$CLAIM"
      tick "released claim $ID on exit"
    fi
  }
  # a signal trap that returns is NOT enough: in POSIX sh, control resumes after the
  # interrupted `wait`, so the round would go on to write RESULT and charge spend for
  # work `delegate.sh stop` already accounted for. The signal handler must exit.
  on_signal() { cleanup; exit 143; }
  trap cleanup EXIT
  trap on_signal INT TERM

  fm_set "$CARD" owner "$AGENT"
  fm_set "$CARD" status writing
  fm_set "$CARD" claimed "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid:$$ via:delegate"
  fm_set "$CARD" updated "$DATE"

  # --- worktree: spawn on round 1, reuse afterwards ------------------------------
  BR=$(fm_get "$CARD" branch); WT=$(fm_get "$CARD" worktree)
  if [ -z "$BR" ] || [ "$BR" = "null" ] || [ ! -d "${WT:-/nonexistent}" ]; then
    sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" >/dev/null
    WT=$(fm_get "$CARD" worktree); BR=$(fm_get "$CARD" branch)
  fi
  case "$(basename "${WT:-none}")" in
    *-wt-*) ;;
    *) echo "error: '$WT' is not a spawned worktree — refusing to run a bypass-permission agent outside worktree isolation" >&2
       fm_set "$CARD" status blocked; exit 1;;
  esac
  PRE=$(git -C "$WT" rev-parse HEAD)

  CB=$(num_or "${CBUDGET:-}" "$(num_or "$(fm_get "$CARD" budget | tr -dc '0-9')" "$TIMEOUT_MIN")")
  OUT="$WS/runs/$ID-delegate$ROUND.out"
  PREV=$(ls -t "$WS"/runs/"$ID"-delegate*.out 2>/dev/null | head -1 || true)

  PROMPT="You are agent '$AGENT', running headless as a DELEGATE of another agent (the
foreman), in the isolated git worktree at $WT (your cwd) on branch $BR.
This is delegation round $ROUND of at most $MAXROUNDS. Time cap: ${CB} minutes.

Hard rules — the foreman is accountable for you:
- Work ONLY in this worktree. Never cd out of it, never switch branches.
- Commit your work here with clear messages. Do NOT push. Do NOT merge.
- Do NOT write anything under any .apsolut-agents/ folder — the foreman logs for you.
- Run the project's green check and iterate until it passes.
- Do NOT spawn further agents: you are already a delegate (depth cap).
- When you are done or genuinely stuck, print a short verdict and stop. If stuck, say
  exactly what you tried, why it failed, and what would unblock you.
$( [ "$ROUND" -gt 1 ] && [ -n "$PREV" ] && printf '\nYour previous round output is at %s — read it before starting.\n' "$PREV" )
$( [ -n "$NOTE" ] && printf '\n=== FOREMAN INSTRUCTION FOR THIS ROUND ===\n%s\n' "$NOTE" )
=== TASK CARD ===
$(cat "$CARD")"

  tick "DELEGATE round $ROUND: $AGENT → $ID on $BR (cap ${CB}m, depth $((DEPTH+1)))"
  printf '\n### delegate — %s\n- DISPATCH: %s → %s (round %s, branch %s). Output: runs/%s\n' \
    "$DATE" "$AGENT" "$ID" "$ROUND" "$BR" "$(basename "$OUT")" >> "$LOG"
  echo "dispatching $AGENT on $ID (round $ROUND, cap ${CB}m) → ${OUT##*/}"

  (
    cd "$WT"
    APSOLUT_AGENT_DEPTH=$((DEPTH+1)); export APSOLUT_AGENT_DEPTH
    exec timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" delegate "$PROMPT"
  ) > "$OUT" 2>&1 &
  APID=$!
  echo "$APID" > "$CLAIM/agent.pid"
  set +e; wait "$APID"; RC=$?; set -e
  rm -f "$CLAIM/agent.pid"

  # `delegate.sh stop` got here first — it owns the salvage and the card. Do nothing.
  if [ -f "$CLAIM/stopped" ]; then
    RELEASED=yes
    echo "$ID round $ROUND: stopped by foreman — see 'delegate.sh stop' output"
    exit 0
  fi

  gd=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$gd" ] && rm -f "$gd/index.lock" 2>/dev/null || true

  salvage() {
    if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
      git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
      git -C "$WT" commit -q -m "$ID: uncommitted work salvaged by delegate (round $ROUND)" || true
    fi
  }

  # provider trouble (429/5xx/quota) is not the delegate's failure and not a round —
  # same carve-out runner.sh makes, so a rate limit can't consume the correction budget.
  # Status codes only count NEXT TO an http/status/error marker: a bare (429|50x) match
  # false-positives on commit SHAs and ordinary app output (found by adversarial review).
  if grep -qiE 'rate.?limit|quota exceeded|overloaded|too many requests|service.{0,15}unavailable|internal server error|bad gateway|gateway time.?out|(http|status( code)?|api.?error|error.?code)[^0-9A-Za-z]{0,4}(429|50[0-4]|529)([^0-9]|$)' "$OUT"; then
    salvage
    printf '%s\n' "$(( ROUND - 1 ))" > "$WS/runs/.rounds-$ID"
    fm_set "$CARD" status waiting
    fm_set "$CARD" updated "$DATE"
    printf -- '- THROTTLED: %s round %s hit provider rate/quota limits — not counted as a round. Output: runs/%s\n' \
      "$ID" "$ROUND" "$(basename "$OUT")" >> "$LOG"
    tick "throttled $ID round $ROUND (provider limit — round not counted)"
    RELEASED=yes; rm -rf "$CLAIM"
    echo
    echo "$ID round $ROUND: THROTTLED — the provider rate-limited or errored, not the delegate."
    echo "  output:  runs/$(basename "$OUT")"
    echo "  next:    wait a few minutes and re-dispatch; this did NOT consume a round"
    echo "           (rounds used: $(( ROUND - 1 ))/$MAXROUNDS)"
    exit 0
  fi

  COST=$(grep -oE '"(total_cost_usd|costUSD|total_cost)"[: ]*[0-9.]+' "$OUT" | tail -1 | grep -o '[0-9.]*$' || true)
  add_spend "${COST:-$FALLBACK_COST}"

  NOWBR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
  [ "$NOWBR" = "$BR" ] || { RC=97; echo "delegate: branch assert failed ($NOWBR != $BR)" >> "$OUT"; }

  salvage

  # green is reported, NOT enforced by destroying work: a foreman is present and reads
  # the diff. (runner.sh resets on red because nobody is watching at 3am.)
  VERDICT=red
  if [ "$RC" -eq 0 ]; then
    case "$GREEN" in
      ''|*"SET green_cmd"*) VERDICT=unverified ;;
      *) echo "green_cmd @ $(git -C "$WT" rev-parse HEAD)" >> "$OUT"
         if ( cd "$WT" && sh -c "$GREEN" ) >> "$OUT" 2>&1; then VERDICT=green; fi ;;
    esac
  fi
  NCOMMITS=$(git -C "$WT" rev-list --count "$PRE..HEAD" 2>/dev/null || echo 0)
  DIFFSTAT=$(git -C "$WT" diff --stat "$PRE..HEAD" 2>/dev/null | command tail -1 || true)

  case "$VERDICT" in
    green)      fm_set "$CARD" status review ;;
    unverified) fm_set "$CARD" status review ;;
    *)          fm_set "$CARD" status waiting ;;
  esac
  fm_set "$CARD" updated "$DATE"

  printf -- '- RESULT: %s round %s → %s (rc=%s, %s commit(s), %s). Spend today $%s.\n' \
    "$ID" "$ROUND" "$VERDICT" "$RC" "$NCOMMITS" "${DIFFSTAT:-no diff}" "$(spent)" >> "$LOG"
  tick "result $ID round $ROUND: $VERDICT (rc=$RC)"

  RELEASED=yes; rm -rf "$CLAIM"

  echo
  echo "$ID round $ROUND: $VERDICT (rc=$RC, $NCOMMITS commit(s), ${DIFFSTAT:-no diff})"
  echo "  output:  runs/$(basename "$OUT")"
  echo "  branch:  $BR  (unmerged — nothing was pushed)"
  case "$VERDICT" in
    green)      echo "  next:    review the diff, then: sh .apsolut-agents/scripts/worktree.sh done $ID --merge" ;;
    unverified) echo "  next:    green_cmd is unset in HEARTBEAT.md — verify by hand before merging" ;;
    *)          echo "  next:    read the output, then either re-run with a correction:"
                echo "             sh .apsolut-agents/scripts/delegate.sh run $AGENT $ID --note \"...\""
                echo "           or take it yourself (rounds used: $ROUND/$MAXROUNDS)" ;;
  esac
  ;;

*) usage ;;
esac

exit 0
