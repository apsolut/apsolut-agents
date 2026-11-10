#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# runner.sh <agent> [--once] — Night Shift: overnight task runner, one lane per agent.
# Rule-based control only. The default branch never moves overnight, kill is
# terminal, and a claim is a mkdir mutex plus a card rewrite. Provider errors back
# off instead of tripping the breaker. See NIGHTSHIFT.md.
# v0.9 goal loop: with GOAL.md done_cmd set, cards whose verification passes
# integrate onto one night branch. When the board is empty, the runner checks the
# predicate there and a planner writes the next cards, until the predicate passes.
# Role prompts live in prompts/*.md. Every decision goes to runs/trail-<date>.tsv.
set -eu

AGENT=${1:?usage: runner.sh <agent> [--once]}
ONCE=no; [ "${2:-}" = "--once" ] && ONCE=yes

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree" >&2; exit 1
fi
REPO=$(git -C "$WS" rev-parse --show-toplevel)
HB="$WS/HEARTBEAT.md"; LOG="$WS/agent-log.md"; GOALF="$WS/GOAL.md"
DATE=$(date +%Y-%m-%d)
REPORT="$WS/runs/night-$DATE.md"; SPENDF="$WS/runs/.spend-$DATE"
HO="$WS/runs/handoffs"
mkdir -p "$WS/claims" "$WS/runs" "$HO"

cfg() { sed -n "s/^$1:[[:space:]]*//p" "$HB" | head -1 | tr -d '\r'; }
gcfg() { if [ -f "$GOALF" ]; then sed -n "s/^$1:[[:space:]]*//p" "$GOALF" | head -1 | tr -d '\r'; fi; }
fm_get() { awk -v k="$2" 'NR==1&&$0~/^---\r?$/{f=1;next} f&&$0~/^---\r?$/{exit}
  f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");sub(/\r$/,"");print;exit}' "$1"; }
fm_set() { awk -v k="$2" -v v="$3" 'NR==1&&$0~/^---\r?$/{f=1;print;next}
  f&&$0~/^---\r?$/{if(!done)print k": "v;f=0;print;next}
  f&&index($0,k":")==1{print k": "v;done=1;next}{print}' \
  "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
num_or() { case "$1" in ''|*[!0-9.]*|*.*.*) echo "$2";; *) echo "$1";; esac; }

TIMEOUT_MIN=$(num_or "$(cfg card_timeout_minutes)" 45)
HELPER_MIN=$(num_or "$(cfg helper_timeout_minutes)" 20)
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
VERIFIER=$(cfg verifier_agent); ADVISOR=$(cfg advisor_agent); REVIEWER=$(cfg review_agent)
VERIFY_LEVEL=$(cfg verify_level); VERIFY_LEVEL=${VERIFY_LEVEL:-test}
[ -n "$CMD" ] || { echo "error: no cmd_$AGENT in HEARTBEAT.md" >&2; exit 1; }
case "$GREEN" in ''|*"SET green_cmd"*)
  echo "error: green_cmd in HEARTBEAT.md is unset — define what green means before running nights" >&2; exit 1;;
esac

# --- goal loop config (GOAL.md; absent or empty done_cmd = plain board mode) -------
DONE_CMD=$(gcfg done_cmd)
GOAL_MODE=no; [ -n "$DONE_CMD" ] && GOAL_MODE=yes
if [ "$GOAL_MODE" = yes ]; then
  v=$(gcfg verify_level); [ -n "$v" ] && VERIFY_LEVEL=$v
fi
MAX_ROUNDS=$(num_or "$(gcfg max_plan_rounds)" 4)
MAX_CARDS=$(num_or "$(gcfg max_cards_per_round)" 5)
PLANNER=$(gcfg planner_agent); PLANNER=${PLANNER:-$AGENT}
NIGHT_ID="NIGHT-$DATE"; NIGHT_CARD="$WS/work/$NIGHT_ID.md"; NIGHT_BR=""; NIGHT_WT=""

ROLES="$AGENT"
for r in "$VERIFIER" "$ADVISOR" "$REVIEWER"; do [ -n "$r" ] && ROLES="$ROLES $r"; done
[ "$GOAL_MODE" = yes ] && ROLES="$ROLES $PLANNER"
ROLES=$(printf '%s\n' $ROLES | awk '!s[$0]++' | tr '\n' ' ')
for r in $ROLES; do
  [ -n "$(cfg "cmd_$r")" ] || { echo "error: role agent '$r' has no cmd_$r in HEARTBEAT.md" >&2; exit 1; }
done
for p in worker verifier planner advisor review; do
  [ -f "$WS/prompts/$p.md" ] || { echo "error: prompts/$p.md missing — run scripts/upgrade.sh" >&2; exit 1; }
done

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
trail() { TRAIL_LANE=$AGENT TRAIL_DATE=$DATE sh "$WS/scripts/trail.sh" "$@" 2>/dev/null || true; }
spent() { num_or "$(cat "$SPENDF" 2>/dev/null || echo 0)" 0; }
add_spend() { awk "BEGIN{printf \"%.2f\", $(spent) + $(num_or "$1" 0)}" > "$SPENDF.tmp" && mv "$SPENDF.tmp" "$SPENDF"; }
charge() { # $1 = CLI output file → add its reported cost, else the fallback
  c=$(grep -oE '"(total_cost_usd|costUSD|total_cost)"[: ]*[0-9.]+' "$1" 2>/dev/null | tail -1 | grep -o '[0-9.]*$' || true)
  add_spend "${c:-$FALLBACK_COST}"
}
# provider trouble (429/5xx/quota) = backoff, not a failure, not an attempt.
# Status codes only count NEXT TO an http/status/error marker: a bare (429|50x) match
# false-positives on commit SHAs and ordinary app output (found by adversarial review).
throttled() {
  grep -qiE 'rate.?limit|quota exceeded|overloaded|too many requests|service.{0,15}unavailable|internal server error|bad gateway|gateway time.?out|(http|status( code)?|api.?error|error.?code)[^0-9A-Za-z]{0,4}(429|50[0-4]|529)([^0-9]|$)' "$1"
}

# --- prompt rendering: prompts/<role>.md with {{KEY}} filled from files -----------
# Values travel through files, never argv or env, so cards and diffs of any size or
# byte content survive. Marker lines (apsolut-agents: tier=) are stripped.
P_DIR=""
p_begin() { P_DIR=$(mktemp -d); : > "$P_DIR/.spec"; }
pv()  { printf '%s\n' "$2" > "$P_DIR/$1"; printf '%s\t%s\n' "$1" "$P_DIR/$1" >> "$P_DIR/.spec"; }
pvf() { if [ -f "$2" ]; then cp "$2" "$P_DIR/$1"; else : > "$P_DIR/$1"; fi
        printf '%s\t%s\n' "$1" "$P_DIR/$1" >> "$P_DIR/.spec"; }
p_render() { # $1 role, $2 output file
  awk -v spec="$P_DIR/.spec" '
    BEGIN { while ((getline line < spec) > 0) {
              t = index(line, "\t"); k = substr(line, 1, t-1); p = substr(line, t+1)
              v = ""; first = 1
              while ((getline l < p) > 0) { v = first ? l : v "\n" l; first = 0 }
              close(p); val[k] = v }
            close(spec) }
    /apsolut-agents: tier=/ { next }
    { s = $0; out = ""
      while (match(s, /[{][{][A-Z_]+[}][}]/)) {
        k = substr(s, RSTART+2, RLENGTH-4)
        out = out substr(s, 1, RSTART-1) ((k in val) ? val[k] : substr(s, RSTART, RLENGTH))
        s = substr(s, RSTART+RLENGTH) }
      print out s }' "$WS/prompts/$1.md" > "$2"
  rm -rf "$P_DIR"; P_DIR=""
}
run_cli() { # $1 agent, $2 cwd, $3 minutes, $4 prompt file, $5 output file → CLI exit code
  c=$(cfg "cmd_$1")
  set +e
  ( cd "$2" && APSOLUT_AGENT_DEPTH=1 && export APSOLUT_AGENT_DEPTH && \
    timeout -k 30 $(( $3 * 60 )) sh -c "$c \"\$1\"" runner "$(cat "$4")" ) > "$5" 2>&1
  rc=$?
  set -e
  return $rc
}

# --- tamper canary: no agent may edit the rules it runs under --------------------
# Every agent runs with a bypass permission posture, and the .primary pointer leads
# back here. Checksum the files no lane writes at night around every agent run. A
# mismatch raises the Andon and ends the night, because the caps are no longer the
# caps. Prevention needs Docker (FUTURE.md). This is detection.
ws_sum() { ( cd "$WS" && for f in HEARTBEAT.md GOAL.md prompts/*.md scripts/*.sh; do
               [ -f "$f" ] && cksum "$f"; done ) 2>/dev/null || true; }
SUM0=""
guard_begin() { SUM0=$(ws_sum); }
guard_end() { # $1 who → 0 clean, 1 tampered (Andon raised)
  s1=$(ws_sum)
  [ "$SUM0" = "$s1" ] && return 0
  what=$(printf '%s\n%s\n' "$SUM0" "$s1" | sort | uniq -u | awk '{print $3}' | sort -u | tr '\n' ' ')
  TRAIL_LANE=$AGENT sh "$WS/scripts/andon.sh" raise "tamper: $1 changed ${what}during its run" >/dev/null 2>&1 || true
  trail tamper "stopped the night" "$1 changed rule files" "$what" ANDON
  return 1
}
tree_state() { printf '%s %s' "$(git -C "$1" rev-parse HEAD 2>/dev/null)" \
  "$(git -C "$1" status --porcelain 2>/dev/null | grep -v '\.apsolut-agents' | cksum)"; }
restore_tree() { # $1 worktree, $2 commit, $3 stray-diff file — undo a read-only role's writes
  { git -C "$1" status --porcelain; git -C "$1" diff HEAD; } > "$3" 2>/dev/null || true
  git -C "$1" reset --hard -q "$2" 2>/dev/null || true
  git -C "$1" clean -fdq -e .apsolut-agents 2>/dev/null || true
}

# --- handoff parsing ----------------------------------------------------------------
md_first() { # $1 file, $2 heading → first non-empty line under "## <heading>"
  [ -f "$1" ] || return 0
  awk -v h="## $2" '{sub(/\r$/,"")} $0==h{f=1;next} f&&/^## /{exit} f&&NF{print;exit}' "$1"
}
md_body() { # $1 file, $2 heading, $3 max lines → section body
  [ -f "$1" ] || return 0
  awk -v h="## $2" -v m="$3" '{sub(/\r$/,"")} $0==h{f=1;next} f&&/^## /{exit} f&&NF&&n<m{print;n++}' "$1"
}
h_status() { md_first "$1" Status | grep -oiE 'success|partial|blocked' | head -1 | tr 'A-Z' 'a-z' || true; }
h_level() { md_first "$1" Verification | grep -oiE 'live-verified|test-verified|typecheck-only|verifier-blocked|verifier-failed|not-verified' | head -1 | tr 'A-Z' 'a-z' || true; }
rank() { case "$1" in live-verified) echo 3;; test-verified) echo 2;; typecheck-only) echo 1;; *) echo 0;; esac; }
need_rank() { case "$1" in live) echo 3;; typecheck) echo 1;; *) echo 2;; esac; }
goal_text() {
  if [ "$GOAL_MODE" = yes ]; then
    printf 'goal: %s\nfinish predicate: %s\n\n' "$(gcfg goal)" "$DONE_CMD"
    awk '/^## Final product means/{f=1} f&&!/^<!--|-->$/' "$GOALF"
  else
    echo "(no GOAL.md contract tonight — the card below is the whole goal)"
  fi
}

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
  for l in .planning .integrate; do
    [ "$(cat "$WS/claims/$l/pid" 2>/dev/null || true)" = "$$" ] && rm -rf "${WS:?}/claims/$l"
  done
  [ -n "$P_DIR" ] && rm -rf "$P_DIR"
  rm -rf "$LANE"
}
trap cleanup EXIT INT TERM

lock() { # $1 name → spin up to ~10 min for a cross-lane mutex
  n=0
  until mkdir "$WS/claims/$1" 2>/dev/null; do
    lp=$(cat "$WS/claims/$1/pid" 2>/dev/null || true)
    if [ -n "$lp" ] && ! kill -0 "$lp" 2>/dev/null; then rm -rf "${WS:?}/claims/$1"; continue; fi
    n=$((n+1)); [ "$n" -ge 120 ] && return 1
    sleep 5
  done
  echo $$ > "$WS/claims/$1/pid"
}
unlock() { rm -rf "${WS:?}/claims/$1"; }

# --- lane preflight: prove every role CLI can answer before burning cards ----------
# One probe from an empty temp cwd (never the repo — the CLI runs with a bypassed
# permission posture). A lane whose CLI cannot answer at all — bad auth, refused
# account, dead binary — would otherwise march the whole board, charging an attempt
# plus fallback cost per card (cost a full night in the field, 2026-08-11). A dead
# verifier would make every card unverified, so roles are probed too.
for r in $ROLES; do
  PROBE_DIR=$(mktemp -d); PROBE_OUT=""; rc=0
  rcmd=$(cfg "cmd_$r")
  PROBE_OUT=$( cd "$PROBE_DIR" && timeout -k 10 180 sh -c "$rcmd \"\$1\"" runner "Reply with the single word: ok" 2>&1 ) || rc=$?
  rm -rf "$PROBE_DIR"
  why=""
  [ "$rc" -ne 0 ] && why="exited non-zero"
  [ -z "$why" ] && printf '%s' "$PROBE_OUT" | grep -q '"is_error"[[:space:]]*:[[:space:]]*true' && why="returned is_error:true"
  [ -z "$why" ] && case "$PROBE_OUT" in *[Oo][Kk]*) ;; *) why="returned no 'ok'";; esac
  if [ -n "$why" ]; then
    echo "error: preflight probe for '$r' $why — refusing to start the lane" >&2
    printf '%s\n' "$PROBE_OUT" | command tail -5 >&2
    tick "preflight probe FAILED ($r): $why — lane refused"
    notify "preflight probe for $r failed ($why) — lane refused"
    exit 1
  fi
done
tick "preflight probe ok ($ROLES)"

# --- boot recovery: release claims whose runner is dead ---------------------------
for c in "$WS"/claims/*/; do
  [ -d "$c" ] || continue
  id=$(basename "$c")
  case "$id" in .lane-*|.planning|.integrate) continue;; esac
  pid=$(cat "$c/pid" 2>/dev/null || echo "")
  ft=$(date -r "$c" +%s 2>/dev/null || echo 0)
  age=$(( ( $(date +%s) - ft ) / 60 ))
  if { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; } && [ "$age" -ge "$STALE_MIN" ]; then
    rm -rf "$c"
    [ -f "$WS/work/$id.md" ] && fm_set "$WS/work/$id.md" status waiting
    tick "recovered stale claim $id (pid ${pid:-none} dead, ${age}m old)"
  fi
done

# --- night integration branch (goal mode) ------------------------------------------
# One card-shaped worktree per night: agent/night/NIGHT-<date>. Cards that pass
# green and verification are merged here with --no-ff, one merge commit per card, so
# a single card can be reverted. Later cards spawn FROM this branch, so a dependent
# card sees its dependency's code the same night. The default branch never moves.
# In the morning, `worktree.sh done NIGHT-<date> --merge` lands the night as one
# proven merge.
night_setup() {
  NIGHT_WT=""; [ -f "$NIGHT_CARD" ] && NIGHT_WT=$(fm_get "$NIGHT_CARD" worktree)
  if [ -z "$NIGHT_WT" ] || [ "$NIGHT_WT" = null ] || [ ! -d "$NIGHT_WT" ]; then
    lock .integrate || { echo "error: could not take the integration lock" >&2; exit 1; }
    sh "$WS/scripts/worktree.sh" spawn night "$NIGHT_ID" >/dev/null
    fm_set "$NIGHT_CARD" title "Night integration $DATE — $(gcfg goal | cut -c1-60)"
    fm_set "$NIGHT_CARD" spike true
    fm_set "$NIGHT_CARD" owner night
    fm_set "$NIGHT_CARD" base "$(git -C "$REPO" rev-parse HEAD)"
    printf '\n## Night integration\nCards verified tonight are merged here (--no-ff, one merge per card).\nFinish predicate: `%s`\nMorning: `sh .apsolut-agents/scripts/worktree.sh done %s --merge`\n' \
      "$DONE_CMD" "$NIGHT_ID" >> "$NIGHT_CARD"
    unlock .integrate
    trail night "opened the night integration branch" "goal mode: verified cards accumulate here" "$NIGHT_ID" open
  fi
  fm_set "$NIGHT_CARD" status writing
  NIGHT_WT=$(fm_get "$NIGHT_CARD" worktree); NIGHT_BR=$(fm_get "$NIGHT_CARD" branch)
}
integrate() { # $1 id, $2 branch, $3 log → 0 merged and green on the night branch
  lock .integrate || return 1
  pre=$(git -C "$NIGHT_WT" rev-parse HEAD); ok=yes
  echo "=== integrate $1 into $NIGHT_BR @ $pre ===" >> "$3"
  git -C "$NIGHT_WT" merge --no-ff --no-edit -q -m "night: integrate $1 ($2)" "$2" >> "$3" 2>&1 || ok=no
  if [ "$ok" = yes ]; then
    echo "green_cmd @ $(git -C "$NIGHT_WT" rev-parse HEAD) (night)" >> "$3"
    ( cd "$NIGHT_WT" && sh -c "$GREEN" ) >> "$3" 2>&1 || ok=no
  fi
  [ "$ok" = yes ] && [ -n "$(git -C "$NIGHT_WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ] && {
    echo "green_cmd changed the night tree — refusing" >> "$3"; ok=no; }
  if [ "$ok" = no ]; then
    git -C "$NIGHT_WT" merge --abort >/dev/null 2>&1 || true
    git -C "$NIGHT_WT" reset --hard -q "$pre" 2>/dev/null || true
    git -C "$NIGHT_WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  fi
  unlock .integrate
  [ "$ok" = yes ]
}
goal_met() { # 0 = the finish predicate passes on the night branch
  lock .integrate || return 1
  at=$(git -C "$NIGHT_WT" rev-parse HEAD); rc=0
  { echo "done_cmd @ $at: $DONE_CMD"; ( cd "$NIGHT_WT" && sh -c "$DONE_CMD" ); } > "$WS/runs/.done-$DATE.out" 2>&1 || rc=$?
  if [ "$(tree_state "$NIGHT_WT")" != "$at $(printf '' | cksum)" ]; then
    restore_tree "$NIGHT_WT" "$at" "$WS/runs/.done-$DATE.stray.diff"
    echo "done_cmd changed the night tree — result ignored (see runs/.done-$DATE.stray.diff)" >> "$WS/runs/.done-$DATE.out"
    rc=99
  fi
  unlock .integrate
  trail goal "checked the finish predicate" "the board ran dry" "runs/.done-$DATE.out @ $(printf '%.7s' "$at")" "$( [ "$rc" -eq 0 ] && echo met || echo "not met (rc=$rc)")"
  [ "$rc" -eq 0 ]
}

deps_met() { # $1 = card file → 0 if every id in after: is done (merged) or integrated tonight
  a=$(fm_get "$1" after | tr -d '[]' | tr ',' ' ')
  for d in $a; do
    df="$WS/work/$d.md"; [ -f "$df" ] || return 1
    [ "$(fm_get "$df" status)" = "done" ] && continue
    [ -n "$NIGHT_BR" ] && [ "$(fm_get "$df" integrated)" = "$NIGHT_BR" ] && continue
    return 1
  done
  return 0
}

is_card() { [ -f "$1" ] || return 1; case "$(basename "$1")" in _TEMPLATE.md) return 1;; esac; }

pick_ready() { # print first claimable card id, or nothing
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    i=$(fm_get "$f" id); [ -n "$i" ] || continue
    [ "$(fm_get "$f" status)" = "waiting" ] || continue
    o=$(fm_get "$f" owner)
    case "$o" in "$AGENT"|any|"<agent>"|"") ;; *) continue;; esac
    deps_met "$f" || continue
    echo "$i"; return 0
  done
  return 1
}

# --- planner round (goal mode, board dry, predicate red) ---------------------------
ROUND_FILE="$WS/runs/.plan-rounds-$DATE"
card_ok() { # $1 staged card → prints why not, returns 1; silent 0 when acceptable
  id=$(fm_get "$1" id)
  [ -n "$id" ] || { echo "no id:"; return 1; }
  [ "$(basename "$1")" = "$id.md" ] || { echo "filename is not $id.md"; return 1; }
  case "$id" in *[!A-Za-z0-9._-]*|NIGHT-*) echo "bad id '$id'"; return 1;; esac
  [ ! -e "$WS/work/$id.md" ] || { echo "id $id already on the board"; return 1; }
  [ "$(fm_get "$1" status)" = waiting ] || { echo "status is not waiting"; return 1; }
  grep -q '^## Goal' "$1" && grep -q '^## Done when' "$1" || { echo "missing ## Goal or ## Done when"; return 1; }
  [ "$(fm_get "$1" spike)" = true ] || grep -qi test "$1" || { echo "names no test and is not spike: true"; return 1; }
  return 0
}
board_table() {
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    printf '%s | %s | %s | %s\n' "$(fm_get "$f" id)" "$(fm_get "$f" status)" \
      "$(fm_get "$f" verified)" "$(fm_get "$f" title)"
  done
}
handoff_digest() { # latest handoff per card touched tonight: notes, follow-ups, blocks
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    id=$(fm_get "$f" id)
    h=$(ls -t "$HO/$id"-attempt*.md 2>/dev/null | head -1 || true)
    [ -n "$h" ] || continue
    echo "### $id ($(fm_get "$f" status), handoff status: $(h_status "$h"))"
    md_body "$h" Notes 8
    md_body "$h" "Suggested follow-ups" 8
    sed -n 's/^Would unblock: /would unblock: /p' "$f" | tail -1
  done | head -200
}
LAST_ROUND_IDS=""; NOPROG=0
plan_round() { # 0 = cards accepted, 1 = STUCK, 2 = no usable cards, 3 = rounds exhausted, 4 = throttled
  R=$(( $(num_or "$(cat "$ROUND_FILE" 2>/dev/null || echo 0)" 0) + 1 ))
  [ "$R" -le "$MAX_ROUNDS" ] || return 3
  echo "$R" > "$ROUND_FILE"
  STAGE="$WS/runs/plan-$DATE-r$R"; mkdir -p "$STAGE"
  if [ -n "$LAST_ROUND_IDS" ]; then
    lr=$(for i in $LAST_ROUND_IDS; do f="$WS/work/$i.md"; [ -f "$f" ] || continue
      printf '%s -> %s%s\n' "$i" "$(fm_get "$f" status)" \
        "$(sed -n 's/^Failed because: / — failed because: /p' "$f" | tail -1)"; done)
    [ "$NOPROG" -gt 0 ] && lr="$lr
NONE of these reached the night branch. Attack the premise the last round shared before planning again."
  else lr="(first round tonight)"; fi
  p_begin
  pv AGENT "$PLANNER"; pv WT "$NIGHT_WT"; pv BRANCH "$NIGHT_BR"; pv GOAL "$(goal_text)"
  pv DONE_CMD "$DONE_CMD"; pv DONE_OUT "$(command tail -40 "$WS/runs/.done-$DATE.out" 2>/dev/null)"
  pv BOARD "$(board_table)"; pv HANDOFFS "$(handoff_digest)"; pv LAST_ROUND "$lr"
  pv MAX_CARDS "$MAX_CARDS"; pv STAGE "$STAGE"; pv NEXT_ID "G$(date +%m%d)r$R-1"
  PF="$STAGE/.prompt.md"; p_render planner "$PF"
  st0=$(tree_state "$NIGHT_WT"); at=$(git -C "$NIGHT_WT" rev-parse HEAD)
  guard_begin; tick "plan round $R ($PLANNER)"
  run_cli "$PLANNER" "$NIGHT_WT" "$HELPER_MIN" "$PF" "$STAGE/.out" || true
  charge "$STAGE/.out"
  guard_end "planner $PLANNER" || finish "andon: tamper by the planner" 5
  if [ "$(tree_state "$NIGHT_WT")" != "$st0" ]; then
    restore_tree "$NIGHT_WT" "$at" "$STAGE/.stray.diff"
    trail plan "threw away planner edits to the night branch" "the planner may only write cards" "$STAGE/.stray.diff" reverted
  fi
  if throttled "$STAGE/.out" && ! ls "$STAGE"/*.md >/dev/null 2>&1; then
    echo $(( R - 1 )) > "$ROUND_FILE"
    trail plan "backed off the planner" "provider throttle; the round is not counted" "$STAGE/.out" backoff
    return 4
  fi
  if [ -f "$STAGE/STUCK.md" ]; then
    cp "$STAGE/STUCK.md" "$WS/runs/STUCK-$DATE.md"
    trail plan "planner says the goal needs a human" "$(head -c 200 "$STAGE/STUCK.md")" "runs/STUCK-$DATE.md" stuck
    return 1
  fi
  ACC=""; n=0
  for f in "$STAGE"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in STUCK.md|.*) continue;; esac
    [ "$n" -lt "$MAX_CARDS" ] || { trail plan "dropped $(basename "$f")" "over max_cards_per_round" "$f" dropped; continue; }
    if why=$(card_ok "$f"); then
      cp "$f" "$WS/work/"; id=$(fm_get "$f" id)
      fm_set "$WS/work/$id.md" planned_by "$PLANNER r$R"
      fm_set "$WS/work/$id.md" updated "$DATE"
      [ -n "$(fm_get "$WS/work/$id.md" owner)" ] || fm_set "$WS/work/$id.md" owner any
      ACC="$ACC $id"; n=$((n+1))
      trail plan "accepted card $id" "$(fm_get "$f" title)" "work/$id.md" accepted
    else
      trail plan "rejected $(basename "$f")" "$why" "$f" rejected
    fi
  done
  [ -n "$ACC" ] || { LAST_ROUND_IDS=""; return 2; }
  LAST_ROUND_IDS=$ACC
  printf '\n### %s — %s (night shift)\n- plan round %s (%s): %s\n' "$AGENT" "$DATE" "$R" "$PLANNER" "$ACC" >> "$LOG"
  return 0
}
round_progressed() { # did any card from the last round reach the night branch?
  for i in $LAST_ROUND_IDS; do
    f="$WS/work/$i.md"; [ -f "$f" ] || continue
    [ "$(fm_get "$f" integrated)" = "$NIGHT_BR" ] && return 0
    [ "$(fm_get "$f" status)" = "done" ] && return 0
  done
  return 1
}

# --- morning packet -----------------------------------------------------------------
finish() { # $1 reason, $2 exit code
  BASEBR=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
  GOALSTATE=""
  if [ "$GOAL_MODE" = yes ] && [ -n "$NIGHT_BR" ]; then
    ahead=$(git -C "$REPO" rev-list --count "HEAD..$NIGHT_BR" 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ]; then fm_set "$NIGHT_CARD" status review
    else fm_set "$NIGHT_CARD" status abandoned; fi
    GOALSTATE=$(command tail -15 "$WS/runs/.done-$DATE.out" 2>/dev/null || echo "(predicate never checked)")
  fi
  {
    echo "# Night report — $DATE (lane: $AGENT)"
    echo
    echo "Ended: $(date '+%Y-%m-%d %H:%M') — reason: $1 — spend: \$$(spent) / \$$BUDGET"
    echo
    if [ "$GOAL_MODE" = yes ]; then
      echo "## Goal"
      echo
      echo "- goal: $(gcfg goal)"
      echo "- finish predicate: \`$DONE_CMD\` — last result below"
      echo "- plan rounds used: $(cat "$ROUND_FILE" 2>/dev/null || echo 0) / $MAX_ROUNDS"
      [ -n "$NIGHT_BR" ] && echo "- night branch: \`$NIGHT_BR\` (+$(git -C "$REPO" rev-list --count "HEAD..$NIGHT_BR" 2>/dev/null || echo 0) commits) — land it with \`sh .apsolut-agents/scripts/worktree.sh done $NIGHT_ID --merge\`"
      echo
      echo '```'; printf '%s\n' "$GOALSTATE"; echo '```'
      echo
    fi
    echo "## Cards"
    echo
    echo "| card | status | verified | integrated | attempts | branch | diffstat vs $BASEBR |"
    echo "|---|---|---|---|---|---|---|"
    for f in "$WS"/work/*.md; do is_card "$f" || continue;
      id=$(fm_get "$f" id); [ "$id" = "$NIGHT_ID" ] && continue
      st=$(fm_get "$f" status); br=$(fm_get "$f" branch)
      at=$(cat "$WS/runs/.attempts-$id" 2>/dev/null || echo 0)
      ds="—"
      [ -n "$br" ] && [ "$br" != "null" ] && \
        ds=$(git -C "$REPO" diff --stat "$BASEBR...$br" 2>/dev/null | tail -1 || echo "—")
      echo "| $id | $st | $(fm_get "$f" verified) | $( [ -n "$NIGHT_BR" ] && [ "$(fm_get "$f" integrated)" = "$NIGHT_BR" ] && echo yes || echo —) | $at | $br | ${ds:-—} |"
    done
    echo
    echo "## Waiting on you"
    echo
    w=0
    [ -f "$WS/ANDON" ] && { echo "- **Andon raised:** $(sed -n 's/^reason: //p' "$WS/ANDON") — clear with \`sh .apsolut-agents/scripts/andon.sh clear\`"; w=1; }
    [ -f "$WS/runs/STUCK-$DATE.md" ] && { echo "- **Planner is stuck:** runs/STUCK-$DATE.md — $(head -c 300 "$WS/runs/STUCK-$DATE.md" | tr '\n' ' ')"; w=1; }
    for f in "$WS"/work/*.md; do is_card "$f" || continue;
      id=$(fm_get "$f" id); st=$(fm_get "$f" status); vf=$(fm_get "$f" verified)
      [ "$st" = blocked ] && [ "$(fm_get "$f" updated)" = "$DATE" ] && {
        echo "- $id blocked — $(sed -n 's/^Would unblock: //p' "$f" | tail -1)"; w=1; }
      [ "$st" = review ] && [ "$vf" = blocked ] && { echo "- $id green but UNVERIFIED (verifier blocked) — runs/handoffs/$id-verify*.md"; w=1; }
    done
    [ "$w" -eq 0 ] && echo "(nothing)"
    echo
    echo "Decision trail: runs/trail-$DATE.tsv (\`column -s\$'\\t' -t runs/trail-$DATE.tsv\`) · handoffs: runs/handoffs/"
    echo
    echo "Nothing merged into \`$BASEBR\` — \`worktree.sh review\`, then \`done <id> --merge\` for what you accept."
  } > "$REPORT"
  trail stop "ended the night" "$1" "runs/$(basename "$REPORT")" "spend \$$(spent)"
  # cross-model morning audit of the trail (show-me-your-work's "Attention" section)
  if [ -n "$REVIEWER" ] && awk "BEGIN{exit !($(spent) < $BUDGET)}" && [ -s "$WS/runs/trail-$DATE.tsv" ]; then
    AP="$WS/runs/night-$DATE-attention.md"; rm -f "$AP"
    p_begin
    pv AGENT "$REVIEWER"; pv REPORT "$REPORT"; pv TRAIL "$WS/runs/trail-$DATE.tsv"; pv HANDOFFS_DIR "$HO"
    pv NIGHT_BRANCH "${NIGHT_BR:-(none — plain board night)}"; pv BASE "$BASEBR"; pv REPO "$REPO"; pv OUT_PATH "$AP"
    p_render review "$WS/runs/.review-$DATE.prompt"
    RD=${NIGHT_WT:-$(mktemp -d)}; st0=$(tree_state "$RD"); at=$(git -C "$RD" rev-parse HEAD 2>/dev/null || true)
    guard_begin
    run_cli "$REVIEWER" "$RD" "$HELPER_MIN" "$WS/runs/.review-$DATE.prompt" "$WS/runs/.review-$DATE.out" || true
    charge "$WS/runs/.review-$DATE.out"
    guard_end "reviewer $REVIEWER" || true
    [ -n "$at" ] && [ "$(tree_state "$RD")" != "$st0" ] && restore_tree "$RD" "$at" "$WS/runs/.review-$DATE.stray.diff"
    if [ -s "$AP" ]; then
      { echo; cat "$AP"; } >> "$REPORT"
    else
      printf '\n## Attention\nreviewer %s produced no attention file — see runs/.review-%s.out\n' "$REVIEWER" "$DATE" >> "$REPORT"
    fi
  fi
  tick "night end: $1 (report: runs/$(basename "$REPORT"))"
  notify "ended: $1 — spend \$$(spent). Report ready."
  sh "$WS/scripts/status.sh" >/dev/null 2>&1 || true
  exit "${2:-0}"
}

# --- one red attempt: pin the evidence, reset, decide retry or block ----------------
# $1 reason (one line), $2 "block" to skip the retry (agent or advisor says dead end)
red() {
  FAILS=$(( FAILS + 1 ))
  [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N" HEAD 2>/dev/null || true
  {
    echo "attempt $N failed: $1 (rc=$RC). Diff it tried (vs $PRE):"
    git -C "$WT" diff "$PRE" HEAD 2>/dev/null | head -400
    [ -f "$HF" ] && { echo; echo "Its handoff:"; head -60 "$HF"; }
    [ -n "${VP:-}" ] && [ -f "$VP" ] && { echo; echo "The independent verifier's verdict:"; head -80 "$VP"; }
    echo; echo "Last output (incl. green_cmd):"
    command tail -60 "$OUT"
  } > "$WS/runs/$ID-attempt$N.fail" 2>/dev/null || true
  git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
  git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  if [ "${2:-}" = block ] || [ "$N" -ge "$MAX_ATTEMPTS" ]; then
    fm_set "$CARD" status blocked
    fm_set "$CARD" updated "$DATE"
    unb=$(md_body "$HF" Notes 1)
    printf '\nAttempted: %s attempt(s) by %s, night %s (runs/%s)\nFailed because: %s\nWould unblock: %s\n' \
      "$N" "$AGENT" "$DATE" "$(basename "$OUT")" "$1" "${unb:-a human reading runs/$ID-attempt$N.fail}" >> "$CARD"
    printf '\n### %s — %s (night shift)\n- %s BLOCKED after %s attempt(s): %s. See runs/%s\n' \
      "$AGENT" "$DATE" "$ID" "$N" "$1" "$ID-attempt$N.fail" >> "$LOG"
    notify "$ID blocked: $1"
    tick "blocked $ID"
    trail card "blocked $ID" "$1" "runs/$ID-attempt$N.fail" blocked
  else
    fm_set "$CARD" status waiting
    tick "red $ID attempt $N ($1) — will retry"
    trail card "red $ID attempt $N, will retry with the failure in the prompt" "$1" "runs/$ID-attempt$N.fail" red
  fi
}

echo "runner[$AGENT]: timeout=${TIMEOUT_MIN}m attempts=$MAX_ATTEMPTS breaker=$MAX_FAILS budget=\$$BUDGET stop=$STOP goal=$GOAL_MODE verifier=${VERIFIER:-none}"
tick "night start (budget \$$BUDGET, stop $STOP, goal mode $GOAL_MODE)"
trail start "started the lane" "goal mode $GOAL_MODE, verifier ${VERIFIER:-none}, advisor ${ADVISOR:-none}" "pid $$" "budget \$$BUDGET"
FAILS=0
BASELINE_OK=no
[ "$GOAL_MODE" = yes ] && night_setup

while :; do
  [ -f "$WS/ANDON" ] && finish "andon: $(sed -n 's/^reason: //p' "$WS/ANDON")" 5
  if [ "$ARMED" = no ]; then in_stop_window || ARMED=yes
  elif in_stop_window; then finish "stop_time" 0; fi
  awk "BEGIN{exit !($(spent) >= $BUDGET)}" && { notify "BUDGET CAP hit (\$$(spent))"; finish "budget" 3; }
  [ "$FAILS" -ge "$MAX_FAILS" ] && { notify "CIRCUIT BREAKER: $FAILS consecutive failures"; finish "breaker" 2; }

  ID=$(pick_ready || true)
  if [ -z "$ID" ]; then
    if [ "$GOAL_MODE" = yes ]; then
      busy=no
      for f in "$WS"/work/*.md; do is_card "$f" || continue; [ "$(fm_get "$f" status)" = writing ] && [ "$(fm_get "$f" id)" != "$NIGHT_ID" ] && busy=yes; done
      if [ "$busy" = no ]; then
        if goal_met; then notify "GOAL MET on $NIGHT_BR"; finish "goal met" 0; fi
        if [ -n "$LAST_ROUND_IDS" ]; then
          if round_progressed; then NOPROG=0; else NOPROG=$((NOPROG+1)); fi
          [ "$NOPROG" -ge 2 ] && { notify "PLATEAU: two plan rounds landed nothing"; finish "plateau: two plan rounds in a row landed nothing" 6; }
        fi
        if lock .planning; then
          prc=0; plan_round || prc=$?
          unlock .planning
          case "$prc" in
            0) continue ;;
            1) notify "goal needs a human (STUCK)"; finish "planner: goal needs a human (runs/STUCK-$DATE.md)" 6 ;;
            2) trail plan "planner produced no usable card" "see the rejected rows above" "runs/plan-$DATE-r$(cat "$ROUND_FILE")/" empty
               NOPROG=$((NOPROG+1))
               [ "$NOPROG" -ge 2 ] && finish "plateau: planner produced no usable cards" 6
               continue ;;
            3) finish "plan rounds exhausted ($MAX_ROUNDS) — goal not met" 6 ;;
            4) sleep 900; continue ;;
          esac
        fi
      fi
    fi
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
    trail claim "refused $ID" "test-first gate: no test named and not a spike" "work/$ID.md" blocked
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
  fi
  fm_set "$CARD" owner "$AGENT"
  fm_set "$CARD" status writing
  fm_set "$CARD" claimed "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid:$$"
  fm_set "$CARD" updated "$DATE"

  BR=$(fm_get "$CARD" branch); WT=$(fm_get "$CARD" worktree)
  if [ -z "$BR" ] || [ "$BR" = "null" ] || [ ! -d "${WT:-/nonexistent}" ]; then
    if [ -n "$NIGHT_BR" ]; then
      sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" --base "$NIGHT_BR" >/dev/null
    else
      sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" >/dev/null
    fi
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
      trail harness "baseline green passed on a pristine worktree" "a red harness must not read as red cards" "runs/.baseline-$DATE.out" green
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
  HF="$HO/$ID-attempt$N.md"; rm -f "$HF"; VP=""
  PREVFAIL="$WS/runs/$ID-attempt$(( N - 1 )).fail"

  # advisor checkpoint ("stuck"): a different model reads the failure before the retry
  ADVICE=""
  if [ -f "$PREVFAIL" ] && [ -n "$ADVISOR" ]; then
    AP="$HO/$ID-advice$N.md"; rm -f "$AP"
    p_begin; pv AGENT "$ADVISOR"; pv ID "$ID"; pv WT "$WT"; pvf CARD "$CARD"
    pv PREVFAIL "$(command tail -150 "$PREVFAIL")"; pv ADVICE_PATH "$AP"
    p_render advisor "$WS/runs/$ID-advice$N.prompt"
    st0=$(tree_state "$WT"); guard_begin
    run_cli "$ADVISOR" "$WT" "$HELPER_MIN" "$WS/runs/$ID-advice$N.prompt" "$WS/runs/$ID-advice$N.out" || true
    charge "$WS/runs/$ID-advice$N.out"
    guard_end "advisor $ADVISOR" || finish "andon: tamper by the advisor" 5
    [ "$(tree_state "$WT")" != "$st0" ] && restore_tree "$WT" "$PRE" "$WS/runs/$ID-advice$N.stray.diff"
    if [ -s "$AP" ]; then
      ADVICE=$(head -60 "$AP")
      trail advise "advisor $ADVISOR read the failure of $ID" "retry gets a second model's diagnosis" "runs/handoffs/$ID-advice$N.md" advised
      if grep -q 'CARD IS WRONG:' "$AP"; then
        fm_set "$CARD" status blocked; fm_set "$CARD" updated "$DATE"
        printf '\nAttempted: %s attempt(s), then advisor %s\nFailed because: advisor says the card is wrong — %s\nWould unblock: a human rewrites the card (runs/handoffs/%s)\n' \
          "$(( N - 1 ))" "$ADVISOR" "$(grep -m1 'CARD IS WRONG:' "$AP" | sed 's/.*CARD IS WRONG:[[:space:]]*//')" "$ID-advice$N.md" >> "$CARD"
        trail card "blocked $ID without a retry" "the advisor says the card itself is wrong" "runs/handoffs/$ID-advice$N.md" blocked
        rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
      fi
    fi
  fi

  p_begin
  pv AGENT "$AGENT"; pv WT "$WT"; pv BRANCH "$BR"; pv GOAL "$(goal_text)"; pv GREEN "$GREEN"
  pv HANDOFF_PATH "$HF"; pvf CARD "$CARD"
  if [ -f "$PREVFAIL" ]; then
    pv PREVFAIL "$(printf '\n=== PREVIOUS ATTEMPT FAILED — read this, do NOT repeat the same approach ===\n%s\n' "$(command tail -120 "$PREVFAIL")")"
  else pv PREVFAIL ""; fi
  if [ -n "$ADVICE" ]; then
    pv ADVICE "$(printf '\n=== ADVISOR (%s read that failure; weigh it, you are accountable) ===\n%s\n' "$ADVISOR" "$ADVICE")"
  else pv ADVICE ""; fi
  p_render worker "$WS/runs/$ID-attempt$N.prompt"

  tick "start $ID attempt $N (cap ${CB}m)"
  trail claim "started $ID attempt $N" "$(fm_get "$CARD" title)" "$BR @ $(printf '%.7s' "$PRE")" running
  guard_begin
  RC=0; run_cli "$AGENT" "$WT" "$CB" "$WS/runs/$ID-attempt$N.prompt" "$OUT" || RC=$?
  guard_end "worker $AGENT on $ID" || { RC=96; fm_set "$CARD" status blocked; finish "andon: tamper by the worker on $ID" 5; }

  GD=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$GD" ] && rm -f "$GD/index.lock" 2>/dev/null || true

  if throttled "$OUT"; then
    tick "provider backoff on $ID (not a failure, not an attempt)"
    trail card "backed off $ID" "provider throttle, not the agent's failure" "runs/$(basename "$OUT")" backoff
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
  charge "$OUT"

  # agent must still be on its card branch — anything else is a hard fail
  NOWBR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  [ "$NOWBR" = "$BR" ] || { RC=97; echo "runner: branch assert failed ($NOWBR != $BR)" >> "$OUT"; }

  if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
    git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
    git -C "$WT" commit -q -m "$ID: uncommitted work salvaged by runner (attempt $N)" || true
  fi

  # the handoff: the agent's own report, or a synthetic one that says why there is none
  if [ ! -s "$HF" ]; then
    case "$RC" in
      124|137) fm="timeout after ${CB}m — the card is probably too big; split it" ;;
      97) fm="left its branch" ;;
      0) fm="finished without writing a handoff" ;;
      *) fm="CLI exited $RC" ;;
    esac
    grep -q '"is_error"[[:space:]]*:[[:space:]]*true' "$OUT" 2>/dev/null && fm="CLI reported is_error:true"
    printf '## Status\n(none — synthetic handoff written by runner.sh)\n\n## Failure mode\n%s\n\n## Notes\n- output tail: runs/%s\n' "$fm" "$(basename "$OUT")" > "$HF"
  fi
  HSTAT=$(h_status "$HF"); VSELF=$(h_level "$HF")

  if [ "$HSTAT" = blocked ]; then
    red "the agent reported a dead end: $(md_body "$HF" Notes 1)" block
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
  fi

  echo "green_cmd @ $(git -C "$WT" rev-parse HEAD)" >> "$OUT"
  if [ "$RC" -ne 0 ]; then
    fmode=$(md_first "$HF" "Failure mode")
    red "${fmode:-the agent CLI exited $RC}"
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
  fi
  if ! ( cd "$WT" && sh -c "$GREEN" ) >> "$OUT" 2>&1; then
    red "green_cmd red at $(git -C "$WT" rev-parse --short HEAD)"
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
  fi
  trail card "green $ID attempt $N" "green_cmd is the gate, not the agent's claim" "runs/$(basename "$OUT") @ $(git -C "$WT" rev-parse --short HEAD)" "green (self: ${VSELF:-none}, handoff: ${HSTAT:-none})"

  # independent verification: a different agent runs the change; the author's word is a claim
  VLEVEL="self:${VSELF:-none}"; PASS=yes
  NEED=$(fm_get "$CARD" verify); NEED=${NEED:-$VERIFY_LEVEL}
  if [ -n "$VERIFIER" ]; then
    VP="$HO/$ID-verify$N.md"; rm -f "$VP"; SCR=$(mktemp -d)
    HEADC=$(git -C "$WT" rev-parse HEAD)
    p_begin
    pv AGENT "$VERIFIER"; pv ID "$ID"; pv WT "$WT"; pv BRANCH "$BR"; pv BASE "$PRE"; pv SCRATCH "$SCR"
    pv GREEN "$GREEN"; pvf CARD "$CARD"; pvf HANDOFF "$HF"; pv VERDICT_PATH "$VP"
    p_render verifier "$WS/runs/$ID-verify$N.prompt"
    st0=$(tree_state "$WT"); guard_begin
    run_cli "$VERIFIER" "$WT" "$HELPER_MIN" "$WS/runs/$ID-verify$N.prompt" "$WS/runs/$ID-verify$N.out" || true
    charge "$WS/runs/$ID-verify$N.out"
    guard_end "verifier $VERIFIER on $ID" || finish "andon: tamper by the verifier on $ID" 5
    if [ "$(tree_state "$WT")" != "$st0" ]; then
      restore_tree "$WT" "$HEADC" "$WS/runs/$ID-verify$N.stray.diff"
      VLEVEL=verifier-blocked; why="the verifier edited the tree; its verdict was thrown away"
    elif throttled "$WS/runs/$ID-verify$N.out" && [ ! -s "$VP" ]; then
      VLEVEL=verifier-blocked; why="the verifier was throttled"
    else
      VLEVEL=$(h_level "$VP"); why=$(md_body "$VP" Findings 1)
      [ -n "$VLEVEL" ] || { VLEVEL=verifier-blocked; why="the verifier wrote no verdict"; }
    fi
    rm -rf "$SCR"
    if [ "$VLEVEL" = verifier-blocked ]; then
      PASS=blocked
    elif [ "$VLEVEL" = verifier-failed ] || [ "$(rank "$VLEVEL")" -lt "$(need_rank "$NEED")" ]; then
      PASS=no
    fi
    trail verify "$VERIFIER judged $ID: $VLEVEL" "needs $NEED; ${why:-}" "runs/handoffs/$ID-verify$N.md" "$PASS"
  fi
  fm_set "$CARD" verified "$( [ "$PASS" = blocked ] && echo blocked || echo "$VLEVEL")"

  if [ "$PASS" = no ]; then
    red "independent verifier said $VLEVEL (needs $NEED)"
    rm -rf "$WS/claims/$ID"; CURRENT_ID=""; continue
  fi

  fm_set "$CARD" status review
  FAILS=0
  INTEG=""
  if [ -n "$NIGHT_BR" ] && [ "$PASS" = yes ]; then
    if integrate "$ID" "$BR" "$OUT"; then
      fm_set "$CARD" integrated "$NIGHT_BR"; INTEG=", integrated into $NIGHT_BR"
      trail integrate "merged $ID into the night branch" "green and verified ($VLEVEL)" "$NIGHT_BR @ $(git -C "$NIGHT_WT" rev-parse --short HEAD)" integrated
    else
      INTEG=", NOT integrated (conflict or red on the night branch — see runs/$(basename "$OUT"))"
      trail integrate "kept $ID off the night branch" "merge conflict or green red after the merge" "runs/$(basename "$OUT")" refused
    fi
  fi
  printf '\n### %s — %s (night shift)\n- %s done (attempt %s): green, verified %s%s. Output: runs/%s\n' \
    "$AGENT" "$DATE" "$ID" "$N" "$VLEVEL" "$INTEG" "$(basename "$OUT")" >> "$LOG"
  tick "green $ID ($VLEVEL)"
  rm -rf "$WS/claims/$ID"; CURRENT_ID=""
done
