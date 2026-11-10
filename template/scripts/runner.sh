#!/bin/sh
# apsolut-agents: tier=2 kind=doc
# SPDX-License-Identifier: MIT — (c) 2026 apsolut — https://github.com/apsolut/apsolut-agents
# runner.sh <agent> [--once|--drain] — Night Shift: overnight task runner, one lane per agent.
#   --once   one card through the whole pipeline, then stop (the supervised v0 gate)
#   --drain  work until the board is empty (or the goal is met), then stop; no idle wait
# Rule-based control only. The default branch never moves overnight, kill is
# terminal, and a claim is a mkdir mutex plus a card rewrite. Provider errors back
# off instead of tripping the breaker. See NIGHTSHIFT.md.
# v0.9 goal loop: with GOAL.md done_cmd set, cards whose verification passes
# integrate onto one night branch. When the board is empty, the runner checks the
# predicate there and a planner writes the next cards, until the predicate passes.
# Role prompts live in prompts/*.md. Every decision goes to runs/trail-<date>.tsv.
set -eu

AGENT=${1:?usage: runner.sh <agent> [--once|--drain]}
ONCE=no; DRAIN=no
case "${2:-}" in
  --once) ONCE=yes; DRAIN=yes ;;
  --drain) DRAIN=yes ;;
  "") ;;
  *) echo "usage: runner.sh <agent> [--once|--drain]" >&2; exit 1 ;;
esac
DID_ONE=no

WS=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$WS/.primary" ]; then
  echo "error: run from the primary worktree" >&2; exit 1
fi
REPO=$(git -C "$WS" rev-parse --show-toplevel)
HB="$WS/HEARTBEAT.md"; LOG="$WS/agent-log.md"; GOALF="$WS/GOAL.md"
mkdir -p "$WS/claims" "$WS/runs"
# The night's identity outlives a crash: a runner restarted after midnight keeps the
# night that is still open (same branch, same spend ledger, same round count) instead
# of opening a fresh night from the default branch. finish() closes it.
NIGHTF="$WS/runs/.night-current"
DATE=$(date +%Y-%m-%d)
if [ -f "$NIGHTF" ]; then
  nd=$(head -1 "$NIGHTF" | tr -d '\r')
  nft=$(date -r "$NIGHTF" +%s 2>/dev/null || echo 0)
  case "$nd" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    [ $(( $(date +%s) - nft )) -lt 64800 ] && DATE=$nd ;;
  esac
fi
echo "$DATE" > "$NIGHTF"
REPORT="$WS/runs/night-$DATE.md"; SPENDF="$WS/runs/.spend-$DATE"
HO="$WS/runs/handoffs"; EVD="$WS/runs/evidence"
mkdir -p "$HO" "$EVD"
# Role output is written INSIDE the worktree (a sandboxed CLI may not be able to
# write anywhere else) under this git-excluded folder, then copied into runs/.
OUTD=.apsolut-out

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
CHECK_MIN=$(num_or "$(cfg check_timeout_minutes)" 30)
SETUP=$(cfg setup_cmd)
PER_MIN=$(num_or "$(cfg cost_per_minute_usd)" 0.15)
MAX_BACKOFF=$(num_or "$(cfg max_backoffs_per_card)" 3)
ARG_MAX_B=$(num_or "$(cfg prompt_arg_max_bytes)" 6000)
# added lines matching this ERE turn an attempt red (symptom patches). Empty = off.
if grep -q '^forbid_added:' "$HB"; then FORBID=$(cfg forbid_added)
else FORBID='\.skip\(|\.only\(|(^|[^[:alnum:]_])x(it|describe)\(|@ts-ignore|@ts-nocheck|eslint-disable'; fi
[ -n "$CMD" ] || { echo "error: no cmd_$AGENT in HEARTBEAT.md" >&2; exit 1; }
# GNU timeout is load-bearing (-k, exit 124). Windows' TIMEOUT.EXE earlier on PATH
# would make every call fail in milliseconds and read as red cards.
timeout -k 1 5 true >/dev/null 2>&1 || {
  echo "error: 'timeout' is not GNU coreutils timeout ($(command -v timeout)) — fix PATH" >&2; exit 1; }
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
# protect: git pathspecs no card may change (the judge: the predicate's script, the
# acceptance tests, the green script, CI config). HEARTBEAT applies to every night,
# GOAL.md adds goal-specific ones. A card diff touching one is red.
PROTECT="$(cfg protect) $(gcfg protect)"; PROTECT=$(printf '%s' "$PROTECT" | tr ',' ' ' | xargs 2>/dev/null || true)
NIGHT_ID="NIGHT-$DATE"; NIGHT_CARD="$WS/work/$NIGHT_ID.md"; NIGHT_BR=""; NIGHT_WT=""; NIGHT_BASE=""
# keep role output folders out of git in every worktree (info/exclude is shared)
EXCL="$(git -C "$REPO" rev-parse --git-common-dir)/info/exclude"
case "$EXCL" in /*|?:*) ;; *) EXCL="$REPO/$EXCL";; esac
mkdir -p "$(dirname "$EXCL")"; grep -qx "/$OUTD/" "$EXCL" 2>/dev/null || echo "/$OUTD/" >> "$EXCL"

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
# morning stop (s < 12:00): the window is [s, 12:00). evening stop: [s, midnight).
in_stop_window() { awk -v n="$(now_hhmm)" -v s="$STOP" 'BEGIN{n=int(n);s=int(s); exit !(s<1200 ? (n>=s && n<1200) : n>=s)}'; }
# started during the morning window (e.g. a supervised 08:00 run) → don't stop instantly;
# the stop gate re-arms once the clock leaves the window (past noon or past midnight).
ARMED=yes; in_stop_window && ARMED=no

notify() { [ -n "$NTFY" ] && curl -s -d "night-shift[$AGENT]: $1" "$NTFY" >/dev/null 2>&1 || true; }
tick() { printf 'TICK: %s %s %s\n' "$AGENT" "$(date '+%m-%d %H:%M')" "$1" >> "$LOG"; }
trail() { TRAIL_LANE=$AGENT TRAIL_DATE=$DATE sh "$WS/scripts/trail.sh" "$@" 2>/dev/null || true; }
spent() { num_or "$(cat "$SPENDF" 2>/dev/null || echo 0)" 0; }
add_spend() { # lanes share the ledger: read-modify-write under a mutex
  n=0; until mkdir "$SPENDF.lock" 2>/dev/null; do n=$((n+1)); [ "$n" -ge 50 ] && rm -rf "$SPENDF.lock"; sleep 0.2; done
  awk "BEGIN{printf \"%.2f\", $(spent) + $(num_or "$1" 0)}" > "$SPENDF.tmp.$$" && mv "$SPENDF.tmp.$$" "$SPENDF"
  rm -rf "$SPENDF.lock"
}
# $1 = CLI output file, $2 = minutes the call ran → its reported cost; with none (a
# timeout, a CLI that prints no cost) the larger of cost_fallback_usd and
# minutes × cost_per_minute_usd, so a 45-minute timeout is not booked as $2.
charge() {
  c=$(grep -oE '"(total_cost_usd|costUSD|total_cost)"[: ]*[0-9.]+' "$1" 2>/dev/null | tail -1 | grep -o '[0-9.]*$' || true)
  [ -n "$c" ] || c=$(awk -v f="$FALLBACK_COST" -v m="$(num_or "${2:-0}" 0)" -v r="$PER_MIN" 'BEGIN{x=m*r; printf "%.2f", (x>f?x:f)}')
  add_spend "$c"
}
T0=0; t_start() { T0=$(date +%s); }
t_min() { echo $(( ( $(date +%s) - T0 + 59 ) / 60 )); }
# provider trouble (429/5xx/quota) = backoff, not a failure, not an attempt. Only a
# call that FAILED (rc != 0 or is_error) can be throttled, and only its last lines
# count: a card about rate limiting, or a test log that prints "Internal Server
# Error", must never read as provider trouble (that reset good work in a loop).
throttled() { # $1 output file, $2 rc
  [ "${2:-0}" -ne 0 ] || grep -q '"is_error"[[:space:]]*:[[:space:]]*true' "$1" 2>/dev/null || return 1
  command tail -40 "$1" 2>/dev/null | grep -qiE 'rate.?limit|quota exceeded|overloaded|too many requests|service.{0,15}unavailable|internal server error|bad gateway|gateway time.?out|(http|status( code)?|api.?error|error.?code)[^0-9A-Za-z]{0,4}(429|50[0-4]|529)([^0-9]|$)'
}
# run a check command in a worktree with a hard cap; $1 dir, $2 cmd, $3 out (append)
run_check() { ( cd "$1" && timeout -k 30 $(( CHECK_MIN * 60 )) sh -c "$2" ) >> "$3" 2>&1; }

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
# How the prompt reaches the CLI (HEARTBEAT prompt_<agent>: arg | stdin):
#   stdin  the whole prompt on stdin, nothing on argv (claude -p, codex exec -, …)
#   arg    the prompt as the last argument, while it fits prompt_arg_max_bytes.
#          A bigger one (retries, planner rounds) becomes a one-line pointer to the
#          prompt file: Windows caps a command line near 8–32 KB, and a prompt that
#          does not fit would fail every retry before the model ever ran.
run_cli() { # $1 agent, $2 cwd, $3 minutes, $4 prompt file, $5 output file → CLI exit code
  c=$(cfg "cmd_$1"); mode=$(cfg "prompt_$1")
  arg=""
  if [ "$mode" != stdin ]; then
    if [ "$(wc -c < "$4")" -le "$ARG_MAX_B" ]; then arg=$(cat "$4")
    else arg="Your complete instructions are in the file $4 — read the whole file now and follow it exactly. It is long on purpose; do not skip any part."; fi
  fi
  t_start
  set +e
  if [ "$mode" = stdin ]; then
    ( cd "$2" && APSOLUT_AGENT_DEPTH=1 && export APSOLUT_AGENT_DEPTH && \
      timeout -k 30 $(( $3 * 60 )) sh -c "$c" ) < "$4" > "$5" 2>&1
  else
    ( cd "$2" && APSOLUT_AGENT_DEPTH=1 && export APSOLUT_AGENT_DEPTH && \
      timeout -k 30 $(( $3 * 60 )) sh -c "$c \"\$1\"" runner "$arg" ) < /dev/null > "$5" 2>&1
  fi
  rc=$?
  set -e
  return $rc
}
# where a role writes its output inside a worktree, and how the runner collects it
out_path() { mkdir -p "$1/$OUTD"; rm -rf "${1:?}/$OUTD/$2"; echo "$1/$OUTD/$2"; }
collect() { # $1 in-worktree file, $2 runs/ destination — copy if the role wrote it
  if [ -s "$1" ]; then cp "$1" "$2"; rm -f "$1"; fi
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
# HEAD + tracked changes. Untracked files are left out on purpose: a test run that
# drops coverage/, a .tsbuildinfo or a sqlite file is not a read-only role editing
# the code. restore_tree() still cleans them away.
tree_state() { printf '%s %s' "$(git -C "$1" rev-parse HEAD 2>/dev/null)" \
  "$(git -C "$1" status --porcelain -uno 2>/dev/null | grep -v '\.apsolut-agents' | cksum)"; }
restore_tree() { # $1 worktree, $2 commit, $3 stray-diff file — undo a read-only role's writes
  { git -C "$1" status --porcelain; git -C "$1" diff HEAD; } > "$3" 2>/dev/null || true
  git -C "$1" reset --hard -q "$2" 2>/dev/null || true
  git -C "$1" clean -fdq -e .apsolut-agents 2>/dev/null || true
}

# --- handoff parsing ----------------------------------------------------------------
# Models drift from the template: "## Status: blocked", "**success**", a bullet, a
# code fence. A heading matches case-insensitively by prefix, the text after it on
# the heading line counts as the first body line, and fences are skipped.
md_section() { # $1 file, $2 heading, $3 max lines → section body
  [ -f "$1" ] || return 0
  awk -v h="$2" -v m="$3" 'BEGIN{h=tolower(h)}
    {sub(/\r$/,"")}
    /^#{2,3}[ \t]/ { t=tolower($0); sub(/^#+[ \t]*/,"",t)
      if (f) exit
      if (index(t,h)==1) { f=1; rest=substr($0, index(tolower($0),h)+length(h)); sub(/^[ \t:*-]*/,"",rest)
        if (rest!="" && n<m) { print rest; n++ }; next } }
    f && /^```/ {next}
    f && NF && n<m { print; n++ }' "$1"
}
md_first() { md_section "$1" "$2" 1; }
md_body() { md_section "$1" "$2" "$3"; }
h_status() { md_section "$1" Status 3 | grep -oiE 'success|partial|blocked' | head -1 | tr 'A-Z' 'a-z' || true; }
h_level() { md_section "$1" Verification 3 | grep -oiE 'live-verified|test-verified|typecheck-only|verifier-blocked|verifier-failed|not-verified' | head -1 | tr 'A-Z' 'a-z' || true; }
# protected paths a diff touched (empty = none); $1 dir, $2 from, $3 to
protected_hits() {
  [ -n "$PROTECT" ] || return 0
  # shellcheck disable=SC2086
  git -C "$1" diff --name-only "$2" "$3" -- $PROTECT 2>/dev/null | head -5 | tr '\n' ' '
}
forbidden_hits() { # symptom patches on added lines; $1 dir, $2 from, $3 to
  [ -n "$FORBID" ] || return 0
  git -C "$1" diff -U0 "$2" "$3" 2>/dev/null | grep '^+' | grep -v '^+++' | grep -E "$FORBID" | head -3 || true
}
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
    setup_wt "$(fm_get "$NIGHT_CARD" worktree)" || { unlock .integrate; finish "harness: setup_cmd failed in the night worktree (runs/.setup-$NIGHT_ID.out)" 4; }
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
  NIGHT_BASE=$(fm_get "$NIGHT_CARD" base)
}
# setup_cmd (HEARTBEAT): bootstrap a fresh worktree (install deps, link a seeded
# node_modules or .venv) once, outside every attempt's clock and outside green_cmd.
setup_wt() { # $1 worktree → 0 ok
  [ -n "$SETUP" ] || return 0
  sf="$WS/runs/.setup-$(basename "$1").out"
  echo "setup_cmd @ $(git -C "$1" rev-parse --short HEAD): $SETUP" > "$sf"
  run_check "$1" "$SETUP" "$sf" || return 1
  # setup may write ignored files only; tracked edits mean it is not a setup step
  [ -z "$(git -C "$1" status --porcelain -uno | grep -v '\.apsolut-agents' || true)" ] || {
    echo "setup_cmd changed tracked files — refusing" >> "$sf"; return 1; }
}
integrate() { # $1 id, $2 branch, $3 log → 0 merged and green on the night branch
  lock .integrate || return 1
  pre=$(git -C "$NIGHT_WT" rev-parse HEAD); ok=yes
  echo "=== integrate $1 into $NIGHT_BR @ $pre ===" >> "$3"
  git -C "$NIGHT_WT" merge --no-ff --no-edit -q -m "night: integrate $1 ($2)" "$2" >> "$3" 2>&1 || ok=no
  [ "$ok" = no ] && echo "MERGE CONFLICT with the night branch: $(git -C "$NIGHT_WT" diff --name-only --diff-filter=U | tr '\n' ' ')" >> "$3"
  if [ "$ok" = yes ]; then
    echo "green_cmd @ $(git -C "$NIGHT_WT" rev-parse HEAD) (night)" >> "$3"
    run_check "$NIGHT_WT" "$GREEN" "$3" || { ok=no; echo "GREEN RED on the night branch after the merge" >> "$3"; }
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
  echo "done_cmd @ $at: $DONE_CMD" > "$WS/runs/.done-$DATE.out"
  run_check "$NIGHT_WT" "$DONE_CMD" "$WS/runs/.done-$DATE.out" || rc=$?
  # the predicate never relaxes: a night whose diff moved the judge cannot meet it
  ph=$(protected_hits "$NIGHT_WT" "${NIGHT_BASE:-$at}" "$at")
  if [ -n "$ph" ]; then
    echo "protected paths changed on the night branch ($ph) — a pass would not count" >> "$WS/runs/.done-$DATE.out"
    [ "$rc" -eq 0 ] && rc=98
  fi
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
  [ "$(fm_get "$1" spike)" != true ] || { echo "planner cards cannot be spikes (spike: true skips the test gate)"; return 1; }
  [ -n "$(fm_get "$1" check)" ] || { echo "no check: command (the runner runs it: red before the change, green after)"; return 1; }
  for d in $(fm_get "$1" after | tr -d '[]' | tr ',' ' '); do
    [ "$d" != "$id" ] || { echo "after: names itself"; return 1; }
    [ -f "$WS/work/$d.md" ] || [ -f "$(dirname "$1")/$d.md" ] || { echo "after: names unknown card $d"; return 1; }
  done
  return 0
}
board_table() {
  for f in "$WS"/work/*.md; do is_card "$f" || continue;
    [ "$(fm_get "$f" id)" = "$NIGHT_ID" ] && continue
    printf '%s | %s | verified: %s | integrated: %s | %s\n' "$(fm_get "$f" id)" "$(fm_get "$f" status)" \
      "$(fm_get "$f" verified)" "$( [ -n "$NIGHT_BR" ] && [ "$(fm_get "$f" integrated)" = "$NIGHT_BR" ] && echo yes || echo no)" "$(fm_get "$f" title)"
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
  # The planner reads a detached snapshot of the night tip, never the night worktree:
  # another lane may integrate while it plans, and nothing the planner does can
  # touch that branch. Its cards come back through the snapshot's output folder.
  at=$(git -C "$NIGHT_WT" rev-parse HEAD); PSNAP=$(mktemp -d)/plan
  git -C "$NIGHT_WT" worktree add -q --detach "$PSNAP" "$at" >/dev/null 2>&1 || PSNAP=""
  [ -n "$PSNAP" ] || { trail plan "could not snapshot the night branch" "git worktree add failed" "$NIGHT_WT" error; return 2; }
  PSTAGE=$(out_path "$PSNAP" plan); mkdir -p "$PSTAGE"
  pv MAX_CARDS "$MAX_CARDS"; pv STAGE "$PSTAGE"; pv NEXT_ID "G$(date +%m%d)r$R-1"
  PF="$STAGE/.prompt.md"; p_render planner "$PF"
  guard_begin; tick "plan round $R ($PLANNER)"
  prc=0; run_cli "$PLANNER" "$PSNAP" "$HELPER_MIN" "$PF" "$STAGE/.out" || prc=$?
  charge "$STAGE/.out" "$(t_min)"
  guard_end "planner $PLANNER" || finish "andon: tamper by the planner" 5
  for f in "$PSTAGE"/*.md; do [ -f "$f" ] && cp "$f" "$STAGE/"; done
  [ -n "$(git -C "$PSNAP" status --porcelain -uno 2>/dev/null)" ] && \
    trail plan "discarded planner edits to its snapshot" "the planner may only write cards" "$STAGE" discarded
  git -C "$NIGHT_WT" worktree remove --force "$PSNAP" >/dev/null 2>&1 || rm -rf "$PSNAP"
  git -C "$NIGHT_WT" worktree prune >/dev/null 2>&1 || true
  if throttled "$STAGE/.out" "$prc" && ! ls "$STAGE"/*.md >/dev/null 2>&1; then
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
      # a planner does not pick lanes or pin branches: any lane may claim its cards
      fm_set "$WS/work/$id.md" owner any
      fm_set "$WS/work/$id.md" branch null; fm_set "$WS/work/$id.md" worktree null
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
      at=$(cat "$WS/runs/.attempts-$DATE-$id" 2>/dev/null || echo 0)
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
      [ "$st" = review ] && [ "$vf" = unverified ] && { echo "- $id green but UNVERIFIED (no verifier and no check:) — not integrated"; w=1; }
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
    RD=${NIGHT_WT:-$(mktemp -d)}; APW=$(out_path "$RD" attention.md)
    pv NIGHT_BRANCH "${NIGHT_BR:-(none — plain board night)}"; pv BASE "$BASEBR"; pv REPO "$REPO"; pv OUT_PATH "$APW"
    p_render review "$WS/runs/.review-$DATE.prompt"
    st0=$(tree_state "$RD"); at=$(git -C "$RD" rev-parse HEAD 2>/dev/null || true)
    guard_begin
    run_cli "$REVIEWER" "$RD" "$HELPER_MIN" "$WS/runs/.review-$DATE.prompt" "$WS/runs/.review-$DATE.out" || true
    charge "$WS/runs/.review-$DATE.out" "$(t_min)"
    guard_end "reviewer $REVIEWER" || true
    collect "$APW" "$AP"
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
  # most useful first: the retry and the advisor read the HEAD of this file, so a
  # long diff must never push the reason and the evidence out of their view
  {
    echo "attempt $N failed: $1 (rc=$RC)"
    [ -n "${VP:-}" ] && [ -f "$VP" ] && { echo; echo "The independent verifier's verdict:"; head -60 "$VP"; }
    [ -f "$HF" ] && { echo; echo "Its handoff:"; head -40 "$HF"; }
    echo; echo "Last output (incl. checks):"
    command tail -50 "$OUT"
    echo; echo "Diff it tried (vs $PRE), files first:"
    git -C "$WT" diff --stat "$PRE" HEAD 2>/dev/null | tail -30
    git -C "$WT" diff "$PRE" HEAD 2>/dev/null | head -300
  } > "$WS/runs/$ID-attempt$N.fail" 2>/dev/null || true
  git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
  git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  if [ "${2:-}" = block ] || [ "$N" -ge "$MAX_ATTEMPTS" ]; then
    fm_set "$CARD" status blocked
    fm_set "$CARD" updated "$DATE"
    # the agent's Notes say what would unblock only when the agent itself stopped
    unb=""; [ "${2:-}" = block ] && unb=$(md_body "$HF" Notes 1)
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

deps_digest() { # $1 card → what its after: cards did (latest handoff), for the worker
  for d in $(fm_get "$1" after | tr -d '[]' | tr ',' ' '); do
    h=$(ls -t "$HO/$d"-attempt*.md 2>/dev/null | head -1 || true)
    [ -n "$h" ] || continue
    echo "### $d ($(fm_get "$WS/work/$d.md" status 2>/dev/null))"
    md_body "$h" "What I did" 10
    md_body "$h" Notes 10
  done | head -80
}
release() { rm -rf "$WS/claims/$ID"; CURRENT_ID=""; }
VBLOCKS=0

while :; do
  [ -f "$WS/ANDON" ] && finish "andon: $(sed -n 's/^reason: //p' "$WS/ANDON")" 5
  [ "$ONCE" = yes ] && [ "$DID_ONE" = yes ] && finish "once: one card through the pipeline" 0
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
    [ "$DRAIN" = yes ] && finish "board empty" 0
    tick "idle — no ready cards"; sleep "$POLL"; continue
  fi

  mkdir "$WS/claims/$ID" 2>/dev/null || { sleep 5; continue; }
  CURRENT_ID=$ID
  echo $$ > "$WS/claims/$ID/pid"
  CARD="$WS/work/$ID.md"
  CHK=$(fm_get "$CARD" check)

  # test-first gate (PLAYBOOK §2): a check: command the runner runs, or a test named
  # on the card, or spike: true. (A word match, so "latest" no longer counts.)
  if [ -z "$CHK" ] && [ "$(fm_get "$CARD" spike)" != "true" ] && ! grep -qiwE 'tests?|specs?' "$CARD"; then
    fm_set "$CARD" status blocked
    printf '\nAttempted: claim by runner\nFailed because: no check: command, no test named on the card, and spike is not true (PLAYBOOK §2)\nWould unblock: add check: <command that fails now and passes when done>, or a failing-test criterion in Done-when\n' >> "$CARD"
    tick "refused $ID: test-first gate (PLAYBOOK §2)"
    trail claim "refused $ID" "test-first gate: no check, no test named, not a spike" "work/$ID.md" blocked
    release; continue
  fi
  fm_set "$CARD" owner "$AGENT"
  fm_set "$CARD" status writing
  fm_set "$CARD" claimed "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid:$$"
  fm_set "$CARD" updated "$DATE"
  DID_ONE=yes
  # The card as claimed is what gets judged. A worker that edits its own card (a
  # lower verify:, a softer Done-when) changes nothing: verify:, check: and the text
  # the verifier reads all come from this snapshot.
  CARDSNAP="$WS/runs/.card-$DATE-$ID.md"; cp "$CARD" "$CARDSNAP"

  BR=$(fm_get "$CARD" branch); WT=$(fm_get "$CARD" worktree)
  if [ -z "$BR" ] || [ "$BR" = "null" ] || [ ! -d "${WT:-/nonexistent}" ]; then
    if [ -n "$NIGHT_BR" ]; then
      sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" --base "$NIGHT_BR" >/dev/null
    else
      sh "$WS/scripts/worktree.sh" spawn "$AGENT" "$ID" >/dev/null
    fi
    WT=$(fm_get "$CARD" worktree); BR=$(fm_get "$CARD" branch)
    if ! setup_wt "$WT"; then
      fm_set "$CARD" status waiting; release
      notify "HARNESS: setup_cmd failed in a fresh worktree"
      finish "harness: setup_cmd failed in a fresh worktree (runs/.setup-$(basename "$WT").out)" 4
    fi
  fi
  # never run destructive git ops anywhere but a spawned worktree
  case "$(basename "$WT")" in
    *-wt-*) ;;
    *) tick "SKIP $ID: worktree path '$WT' is not a spawned worktree — refusing"
       fm_set "$CARD" status blocked
       release; FAILS=$((FAILS+1)); continue;;
  esac
  # goal mode: every attempt starts from the current night tip. A retry after a
  # merge conflict, or a card whose dependency landed meanwhile, builds on what is
  # integrated now. (After a red reset the card branch has no commits of its own,
  # so this is a fast-forward.)
  if [ -n "$NIGHT_BR" ] && git -C "$WT" merge-base --is-ancestor HEAD "$NIGHT_BR" 2>/dev/null; then
    git -C "$WT" merge --ff-only -q "$NIGHT_BR" >/dev/null 2>&1 || true
  fi
  PRE=$(git -C "$WT" rev-parse HEAD)

  # harness-vs-card attribution: green must pass on the PRISTINE worktree before any
  # agent runs. A worktree contains only TRACKED files and green_cmd runs with cwd
  # set to it — a relative path or untracked helper makes every card read as "card
  # failed" while the harness is broken, blocking good work and tripping the breaker
  # (field incident 2026-08-11: cost 3 cards). Checked once per night, first worktree.
  if [ "$BASELINE_OK" != yes ]; then
    : > "$WS/runs/.baseline-$DATE.out"
    if run_check "$WT" "$GREEN" "$WS/runs/.baseline-$DATE.out"; then
      BASELINE_OK=yes
      tick "baseline green ok on pristine worktree"
      trail harness "baseline green passed on a pristine worktree" "a red harness must not read as red cards" "runs/.baseline-$DATE.out" green
    else
      fm_set "$CARD" status waiting
      release
      notify "HARNESS: green_cmd fails on a pristine worktree — night refused, no cards charged"
      tick "HARNESS FAILURE: green_cmd red on pristine worktree $WT (not a card failure) — runs/.baseline-$DATE.out"
      finish "harness: green_cmd red on pristine worktree" 4
    fi
  fi

  # check: is proved red BEFORE the change. A check that already passes means the
  # card is done or the check proves nothing; either way no model should run.
  if [ -n "$CHK" ]; then
    echo "check @ $PRE (must FAIL before the change): $CHK" > "$WS/runs/$ID-check-pre.out"
    if run_check "$WT" "$CHK" "$WS/runs/$ID-check-pre.out"; then
      git -C "$WT" reset --hard -q "$PRE"; git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
      fm_set "$CARD" status blocked; fm_set "$CARD" updated "$DATE"
      printf '\nAttempted: claim by runner, night %s\nFailed because: check: already passes before any change (runs/%s-check-pre.out)\nWould unblock: a check that fails until the card is done, or close the card\n' "$DATE" "$ID" >> "$CARD"
      trail claim "refused $ID" "its check: passes before any change, so it proves nothing" "runs/$ID-check-pre.out" blocked
      release; continue
    fi
    git -C "$WT" reset --hard -q "$PRE"; git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
  fi

  N=$(( $(cat "$WS/runs/.attempts-$DATE-$ID" 2>/dev/null || echo 0) + 1 ))
  CB=$(num_or "$(fm_get "$CARD" budget | tr -dc '0-9')" "$TIMEOUT_MIN")
  OUT="$WS/runs/$ID-attempt$N.out"
  HF="$HO/$ID-attempt$N.md"; rm -f "$HF"; VP=""
  PREVFAIL="$WS/runs/$ID-attempt$(( N - 1 )).fail"

  # advisor checkpoint ("stuck"): a different model reads the failure before the retry
  ADVICE=""
  if [ -f "$PREVFAIL" ] && [ -n "$ADVISOR" ]; then
    AP="$HO/$ID-advice$N.md"; rm -f "$AP"; APW=$(out_path "$WT" advice.md)
    p_begin; pv AGENT "$ADVISOR"; pv ID "$ID"; pv WT "$WT"; pvf CARD "$CARDSNAP"
    pv PREVFAIL "$(head -150 "$PREVFAIL")"; pv ADVICE_PATH "$APW"
    p_render advisor "$WS/runs/$ID-advice$N.prompt"
    st0=$(tree_state "$WT"); guard_begin
    run_cli "$ADVISOR" "$WT" "$HELPER_MIN" "$WS/runs/$ID-advice$N.prompt" "$WS/runs/$ID-advice$N.out" || true
    charge "$WS/runs/$ID-advice$N.out" "$(t_min)"
    guard_end "advisor $ADVISOR" || finish "andon: tamper by the advisor" 5
    collect "$APW" "$AP"
    [ "$(tree_state "$WT")" != "$st0" ] && restore_tree "$WT" "$PRE" "$WS/runs/$ID-advice$N.stray.diff"
    if [ -s "$AP" ]; then
      ADVICE=$(head -60 "$AP")
      trail advise "advisor $ADVISOR read the failure of $ID" "retry gets a second model's diagnosis" "runs/handoffs/$ID-advice$N.md" advised
      if grep -qE '^[[:space:]*_>-]*CARD IS WRONG:' "$AP"; then
        fm_set "$CARD" status blocked; fm_set "$CARD" updated "$DATE"
        printf '\nAttempted: %s attempt(s), then advisor %s\nFailed because: advisor says the card is wrong — %s\nWould unblock: a human rewrites the card (runs/handoffs/%s)\n' \
          "$(( N - 1 ))" "$ADVISOR" "$(grep -m1 'CARD IS WRONG:' "$AP" | sed 's/.*CARD IS WRONG:[[:space:]]*//')" "$ID-advice$N.md" >> "$CARD"
        trail card "blocked $ID without a retry" "the advisor says the card itself is wrong" "runs/handoffs/$ID-advice$N.md" blocked
        release; continue
      fi
    fi
  fi

  HFW=$(out_path "$WT" handoff.md)
  p_begin
  pv AGENT "$AGENT"; pv WT "$WT"; pv BRANCH "$BR"; pv GOAL "$(goal_text)"; pv GREEN "$GREEN"
  pv HANDOFF_PATH "$HFW"; pvf CARD "$CARDSNAP"
  pv CHECK "${CHK:-(none on this card: name and write the failing test yourself)}"
  dd=$(deps_digest "$CARDSNAP")
  if [ -n "$dd" ]; then
    pv DEPS "$(printf '\n=== WHAT THE CARDS THIS ONE BUILDS ON DID (their handoffs; their code is in your tree) ===\n%s\n' "$dd")"
  else pv DEPS ""; fi
  if [ -f "$PREVFAIL" ]; then
    pv PREVFAIL "$(printf '\n=== PREVIOUS ATTEMPT FAILED — read this, do NOT repeat the same approach ===\n%s\n' "$(head -150 "$PREVFAIL")")"
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
  charge "$OUT" "$(t_min)"
  collect "$HFW" "$HF"

  GD=$(git -C "$WT" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$GD" ] && rm -f "$GD/index.lock" 2>/dev/null || true

  if throttled "$OUT" "$RC"; then
    BOF="$WS/runs/.backoff-$DATE-$ID"; bo=$(( $(cat "$BOF" 2>/dev/null || echo 0) + 1 )); echo "$bo" > "$BOF"
    if [ "$bo" -lt "$MAX_BACKOFF" ]; then
      tick "provider backoff on $ID ($bo/$MAX_BACKOFF, not an attempt)"
      trail card "backed off $ID ($bo/$MAX_BACKOFF)" "provider throttle, not the agent's failure" "runs/$(basename "$OUT")" backoff
      # salvage + pin BEFORE the reset: a throttle is not the agent's failure, and
      # destroying its uncommitted work on a 429 was pure evidence loss. The pinned
      # ref is gc-proof and invisible to branch listings; humans list/delete
      # refs/apsolut/* manually, same posture as worktree folders.
      if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
        git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
        git -C "$WT" commit -q -m "$ID: salvaged before throttle backoff (attempt $N)" || true
      fi
      [ "$(git -C "$WT" rev-parse HEAD)" != "$PRE" ] && git -C "$WT" update-ref "refs/apsolut/attempts/$ID-$N-backoff-$bo" HEAD 2>/dev/null || true
      git -C "$WT" reset --hard -q "$PRE" 2>/dev/null || true
      git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
      fm_set "$CARD" status waiting
      release
      sleep 900; continue
    fi
    echo "runner: provider throttled $bo times on this card tonight — counting it as a failed attempt" >> "$OUT"
  fi
  echo "$N" > "$WS/runs/.attempts-$DATE-$ID"

  # agent must still be on its card branch — anything else is a hard fail
  NOWBR=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  [ "$NOWBR" = "$BR" ] || { RC=97; echo "runner: branch assert failed ($NOWBR != $BR)" >> "$OUT"; }

  if [ -n "$(git -C "$WT" status --porcelain | grep -v '\.apsolut-agents' || true)" ]; then
    git -C "$WT" add -A -- ':!.apsolut-agents' 2>/dev/null || git -C "$WT" add -A
    git -C "$WT" commit -q -m "$ID: uncommitted work salvaged by runner (attempt $N)" || true
  fi

  # the handoff: the file the agent wrote, else the handoff it printed as its final
  # message (JSON-escaped newlines undone), else a synthetic one naming the failure
  if [ ! -s "$HF" ] && grep -qE '#+ *Status' "$OUT" 2>/dev/null; then
    sed 's/\\n/\
/g' "$OUT" | awk '/^#+ *Status/{buf=""; f=1} f{buf=buf $0 "\n"} END{printf "%s", buf}' | head -80 > "$HF"
    [ -n "$(h_status "$HF")" ] || rm -f "$HF"
  fi
  if [ ! -s "$HF" ]; then
    case "$RC" in
      124|137) fm="timeout after ${CB}m — the card is probably too big; split it" ;;
      97) fm="left its branch" ;;
      0) fm="finished without writing a handoff" ;;
      *) fm="CLI exited $RC" ;;
    esac
    grep -q '"is_error"[[:space:]]*:[[:space:]]*true' "$OUT" 2>/dev/null && fm="CLI reported is_error:true"
    { printf '## Status\n(none — synthetic handoff written by runner.sh)\n\n## Failure mode\n%s\n\n## Notes\n- output: runs/%s\n\n## Output tail\n' "$fm" "$(basename "$OUT")"
      command tail -40 "$OUT"; } > "$HF"
  fi
  HSTAT=$(h_status "$HF"); VSELF=$(h_level "$HF")

  if [ "$HSTAT" = blocked ]; then
    red "the agent reported a dead end: $(md_body "$HF" Notes 1)" block
    release; continue
  fi

  echo "green_cmd @ $(git -C "$WT" rev-parse HEAD)" >> "$OUT"
  if [ "$RC" -ne 0 ]; then
    fmode=$(md_first "$HF" "Failure mode")
    red "${fmode:-the agent CLI exited $RC}"
    release; continue
  fi
  if ! run_check "$WT" "$GREEN" "$OUT"; then
    red "green_cmd red at $(git -C "$WT" rev-parse --short HEAD)"
    release; continue
  fi
  # the judge is not the worker's to edit, and symptom patches are not fixes
  ph=$(protected_hits "$WT" "$PRE" HEAD)
  if [ -n "$ph" ]; then
    red "changed protected path(s): $ph — the checks are not the worker's to edit"
    release; continue
  fi
  fh=$(forbidden_hits "$WT" "$PRE" HEAD)
  if [ -n "$fh" ]; then
    red "added a forbidden symptom patch (forbid_added): $(printf '%s' "$fh" | head -1 | cut -c1-140)"
    release; continue
  fi
  # check: must pass AFTER the change — the runner runs it, the worker's word is a claim
  CHECKED=no
  if [ -n "$CHK" ]; then
    echo "check @ $(git -C "$WT" rev-parse HEAD) (must PASS after the change): $CHK" >> "$OUT"
    if ! run_check "$WT" "$CHK" "$OUT"; then
      red "check: still red after the change ($CHK)"
      release; continue
    fi
    [ -z "$(git -C "$WT" status --porcelain -uno | grep -v '\.apsolut-agents' || true)" ] || {
      red "check: changed tracked files — a check must not edit"; release; continue; }
    CHECKED=yes
  fi
  trail card "green $ID attempt $N" "$( [ "$CHECKED" = yes ] && echo "green_cmd and check: decide" || echo "green_cmd decides"), not the agent's claim" "runs/$(basename "$OUT") @ $(git -C "$WT" rev-parse --short HEAD)" "green (self: ${VSELF:-none}, handoff: ${HSTAT:-none})"

  # independent verification: a different agent runs the change; the author's word is a claim
  VLEVEL="self:${VSELF:-none}"; PASS=yes
  [ "$CHECKED" = yes ] && VLEVEL="check-passed"
  NEED=$(fm_get "$CARDSNAP" verify); NEED=${NEED:-$VERIFY_LEVEL}
  if [ -n "$VERIFIER" ]; then
    VP="$HO/$ID-verify$N.md"; rm -f "$VP"; VPW=$(out_path "$WT" verdict.md)
    SCRW=$(out_path "$WT" "scratch-$N"); mkdir -p "$SCRW"
    HEADC=$(git -C "$WT" rev-parse HEAD)
    p_begin
    pv AGENT "$VERIFIER"; pv ID "$ID"; pv WT "$WT"; pv BRANCH "$BR"; pv BASE "$PRE"; pv SCRATCH "$SCRW"
    pv GREEN "$GREEN"; pv CHECK "${CHK:-(none on this card)}"; pvf CARD "$CARDSNAP"; pvf HANDOFF "$HF"; pv VERDICT_PATH "$VPW"
    p_render verifier "$WS/runs/$ID-verify$N.prompt"
    st0=$(tree_state "$WT"); guard_begin
    rcv=0; run_cli "$VERIFIER" "$WT" "$HELPER_MIN" "$WS/runs/$ID-verify$N.prompt" "$WS/runs/$ID-verify$N.out" || rcv=$?
    charge "$WS/runs/$ID-verify$N.out" "$(t_min)"
    guard_end "verifier $VERIFIER on $ID" || finish "andon: tamper by the verifier on $ID" 5
    collect "$VPW" "$VP"
    # evidence outlives the worktree cleanup: screenshots, logs, repro scripts
    if [ -n "$(ls -A "$SCRW" 2>/dev/null)" ]; then
      rm -rf "${EVD:?}/$ID-verify$N"; mv "$SCRW" "$EVD/$ID-verify$N" 2>/dev/null || cp -r "$SCRW" "$EVD/$ID-verify$N"
    fi
    rm -rf "$SCRW"
    if [ "$(tree_state "$WT")" != "$st0" ]; then
      restore_tree "$WT" "$HEADC" "$WS/runs/$ID-verify$N.stray.diff"
      VLEVEL=verifier-blocked; why="the verifier edited tracked files; its verdict was thrown away"
    elif [ "$rcv" -ne 0 ]; then
      VLEVEL=verifier-blocked; why="the verifier CLI exited $rcv$(throttled "$WS/runs/$ID-verify$N.out" "$rcv" && echo " (provider throttle)")"
    else
      VLEVEL=$(h_level "$VP"); why=$(md_body "$VP" Findings 1)
      [ -n "$VLEVEL" ] || { VLEVEL=verifier-blocked; why="the verifier wrote no verdict"; }
    fi
    git -C "$WT" clean -fdq -e .apsolut-agents 2>/dev/null || true
    if [ "$VLEVEL" = verifier-blocked ]; then
      PASS=blocked; VBLOCKS=$((VBLOCKS+1))
    elif [ "$VLEVEL" = verifier-failed ] || [ "$(rank "$VLEVEL")" -lt "$(need_rank "$NEED")" ]; then
      PASS=no; VBLOCKS=0
    else VBLOCKS=0; fi
    trail verify "$VERIFIER judged $ID: $VLEVEL" "needs $NEED; ${why:-}" "runs/handoffs/$ID-verify$N.md" "$PASS"
    if [ "$VBLOCKS" -ge 2 ]; then
      TRAIL_LANE=$AGENT sh "$WS/scripts/andon.sh" raise "verifier $VERIFIER blocked on two cards in a row (last: $why) — its harness is broken, every card would land unverified" >/dev/null 2>&1 || true
      trail andon "stopped the night" "two verifier-blocked verdicts in a row" "runs/handoffs/$ID-verify$N.md" ANDON
    fi
  elif [ "$GOAL_MODE" = yes ] && [ "$CHECKED" != yes ]; then
    # goal mode never integrates on the author's word alone: something other than
    # the author (the runner's check: or a verifier) has to prove each card
    PASS=unverified
  fi
  case "$PASS" in
    blocked) fm_set "$CARD" verified blocked ;;
    unverified) fm_set "$CARD" verified unverified ;;
    *) fm_set "$CARD" verified "$VLEVEL" ;;
  esac

  if [ "$PASS" = no ]; then
    red "independent verifier said $VLEVEL (needs $NEED)"
    release; continue
  fi

  fm_set "$CARD" status review
  INTEG=""
  if [ -n "$NIGHT_BR" ] && [ "$PASS" = yes ]; then
    if integrate "$ID" "$BR" "$OUT"; then
      fm_set "$CARD" integrated "$NIGHT_BR"; INTEG=", integrated into $NIGHT_BR"
      trail integrate "merged $ID into the night branch" "green and verified ($VLEVEL)" "$NIGHT_BR @ $(git -C "$NIGHT_WT" rev-parse --short HEAD)" integrated
    else
      # merges are tasks: a card that cannot land is red, and its retry starts
      # from the current night tip with the conflict or the red output in its prompt
      trail integrate "kept $ID off the night branch" "merge conflict or green red after the merge" "runs/$(basename "$OUT")" refused
      red "could not land on the night branch ($(grep -E '^(MERGE CONFLICT|GREEN RED)' "$OUT" | tail -1 | cut -c1-160)) — retry from the current night tip"
      release; continue
    fi
  fi
  FAILS=0
  printf '\n### %s — %s (night shift)\n- %s done (attempt %s): green, verified %s%s. Output: runs/%s\n' \
    "$AGENT" "$DATE" "$ID" "$N" "$VLEVEL" "$INTEG" "$(basename "$OUT")" >> "$LOG"
  tick "green $ID ($VLEVEL)"
  release
done
