#!/bin/sh
# SPDX-License-Identifier: MIT — (c) 2026 Aleksandar Perisic (apsolut) — https://github.com/apsolut/apsolut-agents
# tests/goal-loop.sh — end-to-end Night Shift goal loop against a fake agent CLI.
# Each scenario: a throwaway repo, a fresh install, a board, `runner.sh fake --drain`,
# then asserts on exit code, branches, cards, trail and report. No model is called.
# Run: sh tests/goal-loop.sh   (CI runs it; needs git, awk, sed, timeout)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAKE="$ROOT/tests/fake-agent.sh"
PASSN=0; FAILN=0
TMPS=""
# KEEP=1 keeps the fixture repos for inspection (paths printed at the end)
[ -n "${KEEP:-}" ] || trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

ok()   { PASSN=$((PASSN+1)); echo "  ok    $1"; }
bad()  { FAILN=$((FAILN+1)); echo "  FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# fixture repo: tracked run-tests.sh is the green check; the test repo signs nothing
# (it is a throwaway fixture with no key; real commits stay signed)
setup() { # $1 goal text, $2 done_cmd, $3 extra HEARTBEAT lines (optional)
  T=$(mktemp -d); TMPS="$TMPS $T"
  R="$T/proj"; mkdir -p "$R"
  git init -q -b main "$R"
  git -C "$R" config user.email test@example.invalid
  git -C "$R" config user.name test
  git -C "$R" config commit.gpgsign false
  printf 'for t in t_*.sh; do [ -f "$t" ] || continue; sh "$t" || exit 1; done\n' > "$R/run-tests.sh"
  sh "$ROOT/install.sh" "$R" >/dev/null
  W="$R/.apsolut-agents"
  cat > "$W/HEARTBEAT.md" <<EOF
card_timeout_minutes: 2
helper_timeout_minutes: 2
max_attempts_per_card: 2
max_consecutive_failures_lane: 3
night_budget_usd: 50
cost_fallback_usd: 0.10
stop_time: 23:59
idle_poll_seconds: 1
stale_claim_minutes: 5
green_cmd: sh run-tests.sh
cmd_fake: sh $FAKE
cmd_fakev: sh $FAKE
verifier_agent: fakev
advisor_agent: fakev
review_agent: fakev
verify_level: test
${3:-}
EOF
  sed -i "s|^goal:.*|goal: $1|; s|^done_cmd:.*|done_cmd: $2|" "$W/GOAL.md"
  git -C "$R" add -A && git -C "$R" commit -q -m init
  MAIN0=$(git -C "$R" rev-parse main)
}
card() { # $1 id, $2 notes line(s), $3 extra frontmatter line (optional)
  cat > "$W/work/$1.md" <<EOF
---
id: $1
status: waiting
owner: any
title: card $1
after: []
risk: []
spike: false
verify: test
files:
  - x
${3:-}
branch: null
worktree: null
---

# $1

## Goal
make the file

## Done when
- [ ] A failing test exists that proves the goal
- [ ] sh run-tests.sh passes

## Notes
$2
EOF
}
run() { RC=0; ( cd "$R" && sh .apsolut-agents/scripts/runner.sh fake "${1:---drain}" ) > "$T/runner.out" 2>&1 || RC=$?; }
D() { date +%Y-%m-%d; }
NB() { echo "agent/night/NIGHT-$(date +%Y-%m-%d)"; }

echo "[1] goal loop: card, verifier, integration, planner, goal met"
setup "a.txt and b.txt exist" 'test -f a.txt \&\& test -f b.txt'
card T-01 "make: a.txt"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ]'
check "report says goal met" 'grep -q "reason: goal met" "$W/runs/night-$(date +%Y-%m-%d).md"'
check "default branch never moved" '[ "$(git -C "$R" rev-parse main)" = "$MAIN0" ]'
check "night branch holds a.txt and b.txt" 'git -C "$R" cat-file -e "$(NB):a.txt" && git -C "$R" cat-file -e "$(NB):b.txt"'
check "T-01 integrated and test-verified" '[ "$(sed -n "s/^verified: //p" "$W/work/T-01.md")" = test-verified ] && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "planner card accepted and integrated" 'ls "$W"/work/G*r1-1.md >/dev/null 2>&1 && grep -q "^integrated: $(NB)" "$W"/work/G*r1-1.md'
check "planner card normalised to owner: any" 'grep -q "^owner: \(any\|fake\)" "$W"/work/G*r1-1.md && grep -q "^planned_by: " "$W"/work/G*r1-1.md'
check "planner card check: proved red before the change" 'grep -q "must FAIL" "$W"/runs/G*r1-1-check-pre.out'
check "verifier evidence kept under runs/evidence" '[ -s "$W/runs/evidence/T-01-verify1/proof.log" ]'
check "handoff collected from the worktree into runs/handoffs" '[ -s "$W/runs/handoffs/T-01-attempt1.md" ]'
check "role output folder is git-ignored, never committed" '! git -C "$R" log --all --name-only --format= | grep -q "^.apsolut-out"'
check "one merge commit per card on the night branch" '[ "$(git -C "$R" rev-list --merges --count "main..$(NB)")" -eq 2 ]'
check "NIGHT card left in review" 'grep -q "^status: review" "$W/work/NIGHT-$(date +%Y-%m-%d).md"'
check "trail has verify, integrate, plan and goal rows" 'for p in verify integrate plan goal; do cut -f3 "$W/runs/trail-$(date +%Y-%m-%d).tsv" | grep -qx "$p" || exit 1; done'
check "reviewer attention appended to the report" 'grep -q "^## Attention" "$W/runs/night-$(date +%Y-%m-%d).md"'
check "the reviewer read a snapshot and it is gone" '[ "$(git -C "$R" worktree list | grep -c "/review")" -eq 0 ]'
check "morning merge lands the night" '( cd "$R" && sh .apsolut-agents/scripts/worktree.sh done "NIGHT-$(date +%Y-%m-%d)" --merge ) >/dev/null 2>&1 && git -C "$R" cat-file -e main:b.txt'

echo "[2] verifier rejects attempt 1, advisor feeds attempt 2"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt
flaky: yes"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ]'
check "two attempts" '[ "$(cat "$W/runs/.attempts-$(date +%Y-%m-%d)-T-01")" = 2 ]'
check "attempt 1 pinned under refs/apsolut/attempts" 'git -C "$R" rev-parse -q --verify refs/apsolut/attempts/T-01-1 >/dev/null'
check "verifier verdict was in the failure context" 'grep -q verifier-failed "$W/runs/T-01-attempt1.fail"'
check "advisor wrote advice and the retry prompt carried it" '[ -s "$W/runs/handoffs/T-01-advice2.md" ] && grep -q "ADVISOR" "$W/runs/T-01-attempt2.prompt"'
check "night branch has the right content" '[ "$(git -C "$R" show "$(NB):a.txt")" = right ]'

echo "[3] Andon stops the line before any claim"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt"
( cd "$R" && sh .apsolut-agents/scripts/andon.sh raise "harness broken: test" ) >/dev/null
run
check "exit 5" '[ "$RC" -eq 5 ]'
check "card never claimed" 'grep -q "^status: waiting" "$W/work/T-01.md"'

echo "[4] tamper canary: a worker editing HEARTBEAT.md ends the night"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt
tamper: yes"
run
check "exit 5" '[ "$RC" -eq 5 ]'
check "Andon raised naming HEARTBEAT.md" 'grep -q "HEARTBEAT.md" "$W/ANDON"'
check "nothing integrated" '! git -C "$R" cat-file -e "$(NB):a.txt" 2>/dev/null'

echo "[5] planner STUCK ends the night for a human"
setup "stuck-please" 'test -f never.txt'
run
check "exit 6" '[ "$RC" -eq 6 ]'
check "STUCK writeup filed and in the report" '[ -s "$W/runs/STUCK-$(date +%Y-%m-%d).md" ] && grep -q "Planner is stuck" "$W/runs/night-$(date +%Y-%m-%d).md"'

echo "[6] agent-declared dead end blocks without a retry"
setup "" ''
card T-01 "make: a.txt
blocked: yes"
run
check "card blocked after one attempt" 'grep -q "^status: blocked" "$W/work/T-01.md" && [ "$(cat "$W/runs/.attempts-$(date +%Y-%m-%d)-T-01")" = 1 ]'
check "blocked note carries the agent's reason" 'grep -q "Would unblock: - needs a credential" "$W/work/T-01.md"'
check "a dead end is blocked by the task" 'grep -qx "Blocked by: task" "$W/work/T-01.md"'

echo "[7] plain board mode (no done_cmd) is unchanged: no night branch"
setup "" ''
card T-01 "make: a.txt"
run
check "exit 0 (board empty)" '[ "$RC" -eq 0 ] && grep -q "reason: board empty" "$W/runs/night-$(date +%Y-%m-%d).md"'
check "card in review on its own branch, no night branch" 'grep -q "^status: review" "$W/work/T-01.md" && ! git -C "$R" rev-parse -q --verify "$(NB)" >/dev/null'

echo "[8] provider-error words in a SUCCESSFUL run are not a throttle; big prompts go by pointer"
setup "a.txt exists" 'test -f a.txt' "prompt_arg_max_bytes: 300"
card T-01 "make: a.txt
chatty: yes"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ]'
check "integrated on attempt 1, no backoff" '[ "$(cat "$W/runs/.attempts-$(D)-T-01")" = 1 ] && ! cut -f6 "$W/runs/trail-$(D).tsv" | grep -qx backoff'

echo "[9] the judge is protected: a worker that edits the green script goes red"
setup "a.txt exists" 'test -f a.txt' "protect: run-tests.sh"
card T-01 "make: a.txt
cheat: yes"
run
check "card blocked, never integrated" 'grep -q "^status: blocked" "$W/work/T-01.md" && ! git -C "$R" cat-file -e "$(NB):a.txt" 2>/dev/null'
check "reason names the protected path" 'grep -q "protected path(s): run-tests.sh" "$W/work/T-01.md"'
check "blocked by a rule, and the report says so" 'grep -qx "Blocked by: rule" "$W/work/T-01.md" && grep -q "T-01 blocked (by: rule)" "$W/runs/night-$(D).md"'

echo "[10] symptom patches are red: an added .skip fails the attempt"
setup "" ''
card T-01 "make: a.txt
skip: yes"
run
check "card blocked for a forbidden patch" 'grep -q "^status: blocked" "$W/work/T-01.md" && grep -q "forbidden symptom patch" "$W/work/T-01.md"'

echo "[11] check: is run by the runner — red before, green after; no verifier needed"
setup "a.txt and c.txt exist" 'test -f a.txt \&\& test -f c.txt' "verifier_agent:"
sed -i 's/^verifier_agent: fakev$//' "$W/HEARTBEAT.md"
card T-01 "make: a.txt" "check: test -f a.txt"
card T-02 "make: c.txt" "check: true"
card T-03 "make: c.txt"
run
check "T-01 integrated on its check alone (verified: check-passed)" 'grep -q "^verified: check-passed" "$W/work/T-01.md" && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "T-02 refused: its check passes before any change" 'grep -q "^status: blocked" "$W/work/T-02.md" && grep -q "already passes" "$W/work/T-02.md"'
check "T-03 (no check, no verifier) green but unverified, not integrated" 'grep -q "^verified: unverified" "$W/work/T-03.md" && ! grep -q "^integrated: $(NB)" "$W/work/T-03.md"'

echo "[12] --once is one card, prompt on stdin, handoff printed to stdout is honoured"
setup "" '' "prompt_fake: stdin"
card T-01 "make: a.txt
stdout-handoff: yes"
card T-02 "make: b.txt"
run --once
check "exit 0 after one card" '[ "$RC" -eq 0 ] && grep -q "reason: once" "$W/runs/night-$(D).md"'
check "T-01 blocked from the printed handoff, T-02 untouched" 'grep -q "^status: blocked" "$W/work/T-01.md" && grep -q "dead end" "$W/work/T-01.md" && grep -q "^status: waiting" "$W/work/T-02.md"'

echo "[13] a call that hits its budget cap is blocked, not retried; the cap reaches the CLI"
setup "" '' "call_budget_usd: 3"
card T-01 "make: a.txt
budget-stop: yes"
run
check "blocked after one attempt, naming the cap" 'grep -q "^status: blocked" "$W/work/T-01.md" && grep -q "per-call budget cap" "$W/work/T-01.md" && [ "$(cat "$W/runs/.attempts-$(D)-T-01")" = 1 ]'
check "the cmd_ line saw the call budget and both time caps" 'grep -q "^env: budget=3.00 soft=1 cap=2$" "$W/runs/T-01-attempt1.out"'

echo "[14] exit 0 without a finished turn is red, not a green candidate; per-agent cost rate"
setup "" '' "cost_fallback_usd_fake: 0.77"
sed -i 's/^verifier_agent: fakev$//' "$W/HEARTBEAT.md"
card T-01 "cancelled: yes"
run
check "blocked after two attempts, never sent to review" 'grep -q "^status: blocked" "$W/work/T-01.md" && grep -q "ended the turn early" "$W/work/T-01.md" && [ "$(cat "$W/runs/.attempts-$(D)-T-01")" = 2 ]'
check "both attempts charged at the agent rate" 'awk "BEGIN{exit !($(cat "$W/runs/.spend-$(D)") >= 1.54)}"'
check "a CLI that never finished is blocked by the cli, not the task" 'grep -qx "Blocked by: cli" "$W/work/T-01.md"'

echo "[15] a CLI that stops at its own timeout reads as a timeout"
setup "" ''
card T-01 "print-timeout: yes"
run
check "failure names the timeout" 'grep -q "^status: blocked" "$W/work/T-01.md" && grep -q "timeout after" "$W/work/T-01.md"'

echo "[16] risk routing: a risk-tagged card goes to the risk verifier, the rest to the usual one"
setup "a.txt and c.txt exist" 'test -f a.txt \&\& test -f c.txt' "cmd_fakes: sh $FAKE
risk_tags: schema money
risk_verifier_agent: fakes"
card T-01 "make: a.txt"; sed -i 's/^risk: \[\]$/risk: [ui, schema]/' "$W/work/T-01.md"
card T-02 "make: c.txt"; sed -i 's/^risk: \[\]$/risk: [ui]/' "$W/work/T-02.md"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ]'
check "T-01 judged by the risk verifier, with the tag in the trail" 'grep -q "fakes judged T-01.*risk tag schema" "$W/runs/trail-$(D).tsv"'
check "T-02 (no listed tag) judged by the usual verifier" 'grep -q "fakev judged T-02" "$W/runs/trail-$(D).tsv" && ! grep -q "fakes judged T-02" "$W/runs/trail-$(D).tsv"'

echo "[17] a risk-tagged card never integrates on its check: alone"
setup "a.txt exists" 'test -f a.txt' "risk_tags: schema"
sed -i 's/^verifier_agent: fakev$//' "$W/HEARTBEAT.md"
card T-01 "make: a.txt" "check: test -f a.txt"; sed -i 's/^risk: \[\]$/risk: [schema]/' "$W/work/T-01.md"
run
check "green, in review, marked risk-unverified, not integrated" 'grep -q "^status: review" "$W/work/T-01.md" && grep -q "^verified: risk-unverified" "$W/work/T-01.md" && ! grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "the report hands it to the human" 'grep -q "T-01 green, but it carries a risk tag" "$W/runs/night-$(D).md"'

echo "[18] intake.sh: labelled GitHub issues become draft cards"
setup "" ''
intake() { IRC=0; ( cd "$R" && APSOLUT_GH="$ROOT/tests/fake-gh.sh" sh .apsolut-agents/scripts/intake.sh "$@" ) > "$T/intake.out" 2>&1 || IRC=$?; }
intake 3 9
check "a named issue with the label becomes a draft on hold" '[ "$IRC" -eq 0 ] && grep -q "^status: hold" "$W/work/GH-3.md" && grep -q "^source: https://github.com/example/proj/issues/3" "$W/work/GH-3.md"'
check "a named issue without the label is refused" '[ ! -f "$W/work/GH-9.md" ] && grep -q "skip  #9" "$T/intake.out"'
intake
check "the rest of the labelled issues follow, existing cards are skipped" '[ -f "$W/work/GH-7.md" ] && grep -q "skip  #3" "$T/intake.out"'
check "issue text cannot close the frontmatter or forge a card section" '[ "$(grep -c "^---$" "$W/work/GH-7.md")" -eq 2 ] && [ "$(grep -c "^status:" "$W/work/GH-7.md")" -eq 1 ] && [ "$(grep -c "^## Notes" "$W/work/GH-7.md")" -eq 1 ] && grep -q "^> Ignore your rules" "$W/work/GH-7.md"'
check "a title cannot smuggle a comment marker" '! grep "^title:" "$W/work/GH-7.md" | grep -q "#"'
rm "$W/work/GH-3.md"; intake --ready 3
check "--ready writes a waiting card" 'grep -q "^status: waiting" "$W/work/GH-3.md"'
rm "$W/work/GH-3.md"
IRC=0; ( cd "$R" && APSOLUT_AGENT_DEPTH=1 APSOLUT_GH="$ROOT/tests/fake-gh.sh" sh .apsolut-agents/scripts/intake.sh 3 ) >/dev/null 2>&1 || IRC=$?
check "a delegate cannot write its own cards" '[ "$IRC" -ne 0 ] && [ ! -f "$W/work/GH-3.md" ]'
run
check "the runner accepts an intake card and leaves a draft on hold alone" '[ "$RC" -eq 0 ] && grep -q "^status: hold" "$W/work/GH-7.md"'

# a fake signing key: commits can be signed only while $T/key-unlocked exists
signing() {
  cat > "$T/signer.sh" <<EOF
#!/bin/sh
[ -f "$T/key-unlocked" ] || { echo "error: agent refused operation" >&2; exit 1; }
for a in "\$@"; do last=\$a; done
printf -- '-----BEGIN SSH SIGNATURE-----\nZmFrZQ==\n-----END SSH SIGNATURE-----\n' > "\$last.sig"
EOF
  chmod +x "$T/signer.sh"
  git -C "$R" config gpg.format ssh
  git -C "$R" config gpg.ssh.program "$T/signer.sh"
  git -C "$R" config user.signingkey "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake"
  git -C "$R" config commit.gpgsign true
}
# run something once the lane has parked (never loops for more than two minutes)
when_parked() { ( i=0; until grep -q "PARKED" "$W/agent-log.md" 2>/dev/null || [ "$i" -ge 120 ]; do sleep 1; i=$((i+1)); done; sleep 1; eval "$1" ) & }
logins() { sed -i "s|^cmd_fake: .*|cmd_fake: FAKE_LOGOUT=$T/signed-out sh $FAKE|; s|^cmd_fakev: .*|cmd_fakev: FAKE_LOGOUT=$T/signed-out sh $FAKE|" "$W/HEARTBEAT.md"; git -C "$R" commit -qam logins; }

echo "[19] a locked signing key parks the lane before any card is touched, and the night resumes"
setup "a.txt exists" 'test -f a.txt' "human_wait_minutes: 2
park_poll_seconds: 1"
card T-01 "make: a.txt"
signing
when_parked ': > "$T/key-unlocked"'
run
wait
check "exit 0 (goal met after the key came back)" '[ "$RC" -eq 0 ]'
check "the lane parked, then resumed, in the trail" 'grep -q "parked the lane" "$W/runs/trail-$(D).tsv" && grep -q "resumed the lane" "$W/runs/trail-$(D).tsv"'
check "the card landed on its first attempt" 'grep -q "^integrated: $(NB)" "$W/work/T-01.md" && [ "$(cat "$W/runs/.attempts-$(D)-T-01")" = 1 ]'

echo "[20] a signing key that stays locked ends the night without spending a card"
setup "a.txt exists" 'test -f a.txt' "human_wait_minutes: 0"
card T-01 "make: a.txt"
signing
run
check "exit 7 (waiting on a human)" '[ "$RC" -eq 7 ]'
check "no worker was called and the card is still waiting" '[ ! -f "$W/runs/T-01-attempt1.out" ] && grep -q "^status: waiting" "$W/work/T-01.md"'
check "the report says what to unlock" 'grep -q "Lane parked, waiting on a human: commits cannot be signed" "$W/runs/night-$(D).md"'

echo "[21] a worker CLI that loses its login parks the lane; the card keeps its attempt"
setup "a.txt exists" 'test -f a.txt' "human_wait_minutes: 0"
logins
card T-01 "make: a.txt
logout: yes"
run
check "exit 7 (waiting on a human)" '[ "$RC" -eq 7 ]'
check "the card is waiting, not blocked, with no attempt used" 'grep -q "^status: waiting" "$W/work/T-01.md" && ! grep -q "^Blocked by:" "$W/work/T-01.md" && [ "$(cat "$W/runs/.attempts-$(D)-T-01")" = 0 ]'
check "the report names the CLI" 'grep -q "the fake CLI stopped answering" "$W/runs/night-$(D).md"'

echo "[22] a verifier CLI that loses its login parks the lane instead of raising the Andon"
setup "a.txt exists" 'test -f a.txt' "human_wait_minutes: 2
park_poll_seconds: 1"
logins
card T-01 "make: a.txt
verifier-logout: yes"
when_parked 'rm -f "$T/signed-out"'
run
wait
check "exit 0 (goal met after the login came back)" '[ "$RC" -eq 0 ]'
check "parked on the verifier, resumed, no Andon" 'grep -q "the verifier CLI (fakev) stopped answering" "$W/runs/trail-$(D).tsv" && grep -q "resumed the lane" "$W/runs/trail-$(D).tsv" && [ ! -f "$W/ANDON" ]'
check "the card was verified and integrated" 'grep -q "^verified: test-verified" "$W/work/T-01.md" && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'

echo "[23] a verifier CLI that crashes (login intact) blocks the verdict; the runner survives"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt
verifier-crash: yes"
run
check "the runner ended with a report, not a crash" '[ -f "$W/runs/night-$(D).md" ] && [ "$RC" -ne 1 ]'
check "the card is green but unverified, and not integrated" 'grep -q "^verified: blocked" "$W/work/T-01.md" && ! grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "the trail records the blocked verdict, with no park" 'grep -q "fakev judged T-01: verifier-blocked" "$W/runs/trail-$(D).tsv" && ! grep -q "parked the lane" "$W/runs/trail-$(D).tsv"'

echo "[24] nightshift.sh: the runner's exit code, the lane's ticks, colour only when asked"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt"
NRC=0; ( cd "$R" && sh .apsolut-agents/scripts/nightshift.sh fake --drain ) > "$T/ns.out" 2>&1 || NRC=$?
ESC=$(printf '\033')
check "exit 0 and the goal is met" '[ "$NRC" -eq 0 ] && grep -q "reason: goal met" "$T/ns.out"'
check "it shows the lane working and says nothing waits" 'grep -q "start T-01 attempt 1" "$T/ns.out" && grep -q "Nothing is waiting on you" "$T/ns.out"'
check "no colour codes when the output is not a terminal" '! grep -q "$ESC" "$T/ns.out"'
setup "" ''
card T-01 "blocked: yes"
NRC=0; ( cd "$R" && CLICOLOR_FORCE=1 sh .apsolut-agents/scripts/nightshift.sh fake --drain ) > "$T/ns.out" 2>&1 || NRC=$?
check "forced colour paints the blocked card red and lists it" 'grep -q "$ESC\[31mblocked T-01" "$T/ns.out" && grep -q "Waiting on you" "$T/ns.out" && grep -q "T-01 blocked" "$T/ns.out"'
check "NO_COLOR wins over a forced colour" '( cd "$R" && NO_COLOR=1 CLICOLOR_FORCE=1 sh .apsolut-agents/scripts/doctor.sh 2>&1 || true ) | grep -q "ok" && ! ( cd "$R" && NO_COLOR=1 CLICOLOR_FORCE=1 sh .apsolut-agents/scripts/doctor.sh 2>&1 || true ) | grep -q "$ESC"'

echo "[25] two lanes, one report: the second lane to finish keeps the first lane's ending"
setup "" ''
card T-01 "make: a.txt"
# another lane already ended this night parked, and the night is still open
echo "$(D) $(date +%s)" > "$W/runs/.night-current"
printf '%s\n%s\n' "2026-01-01 01:00 — reason: waiting on a human: the other CLI stopped answering — spend: \$0 / \$50" "- **Lane parked, waiting on a human: the other CLI stopped answering.** Fix it." > "$W/runs/.lane-end-$(D)-other"
RC=0; ( cd "$R" && sh .apsolut-agents/scripts/nightshift.sh fake --drain ) > "$T/ns.out" 2>&1 || RC=$?
RP="$W/runs/night-$(D).md"
check "exit 0 and the report names both lanes" '[ "$RC" -eq 0 ] && grep -q "^# Night report .* (lanes: fake, other)" "$RP"'
check "each lane has its own Ended line" 'grep -q "^Ended: .* — lane: fake$" "$RP" && grep -q "^Ended: .*the other CLI stopped answering.* — lane: other$" "$RP"'
check "the other lane is still waiting on the human" 'grep -q "Lane parked, waiting on a human: the other CLI stopped answering.*(lane: other)" "$RP"'
check "nightshift.sh shows its own lane ending" 'grep -q "reason: .* — lane: fake" "$T/ns.out" && ! grep -q "reason: waiting on a human.* — lane: other" "$T/ns.out"'
check "the last lane standing ran the audit" 'grep -q "^## Attention" "$RP"'
setup "" ''
card T-01 "make: a.txt"
# a live second lane: the audit waits for it, and the night stays open
mkdir -p "$W/claims/.lane-other"; echo $$ > "$W/claims/.lane-other/pid"
RC=0; ( cd "$R" && sh .apsolut-agents/scripts/runner.sh fake --drain ) > /dev/null 2>&1 || RC=$?
check "with another lane alive: no audit yet, the night stays open, single-lane format" '[ "$RC" -eq 0 ] && ! grep -q "^## Attention" "$W/runs/night-$(D).md" && [ -f "$W/runs/.night-current" ] && grep -q "(lane: fake)" "$W/runs/night-$(D).md"'
rmdir "$W/claims/.lane-other" 2>/dev/null || true

echo "[26] a key that locks before the merge into the night branch parks; the card keeps its attempt"
setup "a.txt exists" 'test -f a.txt' "human_wait_minutes: 2
park_poll_seconds: 1"
card T-01 "make: a.txt
verifier-locks-key: $T/key-unlocked"
signing
: > "$T/key-unlocked"
when_parked ': > "$T/key-unlocked"'
run
wait
check "exit 0 (the card landed after the key came back)" '[ "$RC" -eq 0 ] && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "it parked on signing, not on a merge conflict" 'grep -q "the merge could not be signed" "$W/runs/trail-$(D).tsv" && grep -q "resumed the lane" "$W/runs/trail-$(D).tsv" && ! grep -q "^status: blocked" "$W/work/T-01.md"'
check "the attempt was returned" '[ "$(cat "$W/runs/.attempts-$(D)-T-01")" = 1 ]'

echo "[27] a role that leaves a folder nobody can delete does not end the lane"
setup "a.txt and b.txt exist" 'test -f a.txt \&\& test -f b.txt'
sed -i "s|^cmd_fake: .*|cmd_fake: FAKE_STUCK=1 sh $FAKE|; s|^cmd_fakev: .*|cmd_fakev: FAKE_STUCK=1 sh $FAKE|" "$W/HEARTBEAT.md"; git -C "$R" commit -qam stuck
card T-01 "make: a.txt"
run
check "exit 0 (goal met) and the lane did not die" '[ "$RC" -eq 0 ] && grep -q "reason: goal met" "$W/runs/night-$(D).md" && ! grep -q "DIED" "$W/agent-log.md"'
check "the verifier evidence was still kept" '[ -s "$W/runs/evidence/T-01-verify1/proof.log" ]'
check "the planner card landed and the reviewer notes are in the report" 'grep -q "^integrated: $(NB)" "$W"/work/G*r1-1.md && grep -q "^## Attention" "$W/runs/night-$(D).md"'

echo "[28] a stopped runner stops, says so, and the next start heals the night"
setup "a.txt exists" 'test -f a.txt'
cat > "$R/run-tests.sh" <<EOF
for t in t_*.sh; do [ -f "\$t" ] || continue; sh "\$t" || exit 1; done
# a slow check on the night branch, once: the test stops the runner in the middle of it
case "\$PWD" in *NIGHT-*) if [ -f "$T/slow" ]; then rm -f "$T/slow"; : > "$T/in-green"; sleep 8; fi;; esac
EOF
git -C "$R" commit -qam "slow green on the night branch"
: > "$T/slow"
card T-01 "make: a.txt"
( cd "$R" && sh .apsolut-agents/scripts/runner.sh fake --drain ) > "$T/runner.out" 2>&1 &
RPID=$!
i=0; until [ -f "$T/in-green" ] || [ "$i" -ge 240 ]; do sleep 1; i=$((i+1)); done
LP=$(cat "$W/claims/.lane-fake/pid" 2>/dev/null || echo "")
[ -n "$LP" ] && kill -TERM "$LP" 2>/dev/null || true
RC=0; wait "$RPID" || RC=$?
check "TERM ends the runner (exit 143)" '[ -n "$LP" ] && [ "$RC" -eq 143 ]'
check "the log says the lane died, with no report" 'grep -q "DIED: the runner stopped without a report (exit 143)" "$W/agent-log.md" && [ ! -f "$W/runs/night-$(D).md" ]'
check "the card is back on the board, its claim and the lane are released" 'grep -q "^status: waiting" "$W/work/T-01.md" && [ ! -d "$W/claims/T-01" ] && [ ! -d "$W/claims/.lane-fake" ]'
check "the half-done merge is on record" '[ -s "$W/runs/.integrating-$(D)" ]'
run
check "the next start rolls the night branch back and lands the card" '[ "$RC" -eq 0 ] && grep -q "rolled the night branch back" "$W/agent-log.md" && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "the card restarted clean, and landed with one merge" 'grep -q "reset T-01 to where its interrupted attempt started" "$W/agent-log.md" && [ "$(git -C "$R" rev-list --merges --count "main..$(NB)")" -eq 1 ]'
check "the report is written and nothing is left behind" 'grep -q "reason: goal met" "$W/runs/night-$(D).md" && [ ! -f "$W/runs/.integrating-$(D)" ] && [ ! -f "$W/runs/.pre-$(D)-T-01" ]'
# a journal that outlived an accepted merge (its file could not be deleted) must not
# undo that merge: the card carries the mark
echo "$(NB) $MAIN0 T-01" > "$W/runs/.integrating-$(D)"
run
check "a journal left after an accepted merge rolls nothing back" '[ "$RC" -eq 0 ] && git -C "$R" cat-file -e "$(NB):a.txt" && [ ! -f "$W/runs/.integrating-$(D)" ] && [ "$(grep -c "rolled the night branch back" "$W/agent-log.md")" -eq 1 ]'

echo "[29] a card saved with Windows line endings runs like any other"
setup "a.txt exists" 'test -f a.txt'
card T-01 "make: a.txt"
sed -i 's/$/\r/' "$W/work/T-01.md"
run
check "exit 0 (goal met)" '[ "$RC" -eq 0 ] && grep -q "reason: goal met" "$W/runs/night-$(D).md"'
check "the card got its worktree, was verified and integrated" 'grep -q "^worktree: .*-wt-" "$W/work/T-01.md" && grep -q "^verified: test-verified" "$W/work/T-01.md" && grep -q "^integrated: $(NB)" "$W/work/T-01.md"'
check "the board lists it" '( cd "$R" && sh .apsolut-agents/scripts/status.sh >/dev/null 2>&1 ); grep -q "T-01" "$W/STATUS.md"'

echo "[30] spend caps: off unless set, 0 is off too, a number above zero is a hard stop"
# the fixture sets night_budget_usd: 50. One card costs 0.06 here (worker 0.05, verifier 0.01).
setup "" ''
sed -i 's/^night_budget_usd: 50$/night_budget_usd: 0.05/' "$W/HEARTBEAT.md"
card T-01 "make: a.txt"
card T-02 "make: b.txt"
run
check "a cap that is set ends the night once the ledger reaches it (exit 3)" '[ "$RC" -eq 3 ] && grep -q "reason: budget — spend: \$0.06 / \$0.05" "$W/runs/night-$(D).md"'
check "the card that fitted is done, the next one never started" 'grep -q "^status: review" "$W/work/T-01.md" && grep -q "^status: waiting" "$W/work/T-02.md" && [ ! -f "$W/runs/T-02-attempt1.out" ]'
# no cap: the ledger starts above the $100 an empty key used to mean
setup "" ''
sed -i 's/^night_budget_usd: 50$/night_budget_usd:/' "$W/HEARTBEAT.md"
mkdir -p "$W/runs"; echo 150.00 > "$W/runs/.spend-$(D)"
card T-01 "make: a.txt"
run
check "an empty night_budget_usd is no cap: the night runs whatever the ledger holds" '[ "$RC" -eq 0 ] && grep -q "^status: review" "$W/work/T-01.md" && grep -q "spend: \$150\.[0-9]* (no cap)" "$W/runs/night-$(D).md"'
check "the lane says so when it starts" 'grep -q "night start (budget off," "$W/agent-log.md"'
check "a cmd_ line with a spend flag still gets a number" 'grep -q "^env: budget=1000000.00 " "$W/runs/T-01-attempt1.out"'
setup "" '' "call_budget_usd: 3"
sed -i 's/^night_budget_usd: 50$/night_budget_usd: 0/' "$W/HEARTBEAT.md"
card T-01 "make: a.txt"
run
check "night_budget_usd: 0 is no cap, not a night that ends before its first card" '[ "$RC" -eq 0 ] && grep -q "^status: review" "$W/work/T-01.md" && grep -q "(no cap)" "$W/runs/night-$(D).md"'
check "call_budget_usd caps a call by itself" 'grep -q "^env: budget=3.00 " "$W/runs/T-01-attempt1.out"'
# delegate.sh reads the same ledger and has its own key
dstatus() { ( cd "$R" && sh .apsolut-agents/scripts/delegate.sh status ) 2>&1; }
drun() { DRC=0; ( cd "$R" && sh .apsolut-agents/scripts/delegate.sh run fake T-01 ) > "$T/delegate.out" 2>&1 || DRC=$?; }
setup "" '' "delegate_budget_usd: 5"
mkdir -p "$W/runs"; echo 6.00 > "$W/runs/.spend-$(D)"
card T-01 "make: a.txt"
drun
check "delegate.sh: a cap that is set refuses the dispatch" '[ "$DRC" -eq 1 ] && grep -q "has reached \$5 (delegate_budget_usd)" "$T/delegate.out" && [ ! -d "$W/claims/T-01" ]'
sed -i 's/^delegate_budget_usd: 5$/delegate_budget_usd: 0/' "$W/HEARTBEAT.md"
check "delegate.sh: 0 is no cap, even while the night has one" 'dstatus | grep -q "spend today: \$6.00 (no cap)"'
drun
check "delegate.sh: with no cap the dispatch goes out" 'grep -q "^dispatching fake on T-01" "$T/delegate.out" && ! grep -q "has reached" "$T/delegate.out"'
sed -i 's/^delegate_budget_usd: 0$/delegate_budget_usd:/' "$W/HEARTBEAT.md"
check "delegate.sh: an empty delegate cap follows the night cap" 'dstatus | grep -q "spend today: \$[0-9.]* / \$50"'
sed -i 's/^night_budget_usd: 50$/night_budget_usd:/' "$W/HEARTBEAT.md"
check "delegate.sh: no cap when neither key is set" 'dstatus | grep -q "spend today: \$[0-9.]* (no cap)"'

echo "[31] the eighth decision (D-008) does not stop the board or the session end"
# to the shell 008 is a bad octal number and 010 is eight
stat() { SRC=0; ( cd "$R" && sh .apsolut-agents/scripts/status.sh ) > "$T/status.out" 2>&1 || SRC=$?; }
setup "" ''
# a decisions file that holds only the placeholder entry
{ head -1 "$W/decisions/DECISIONS.md"; echo '### D-0NN — <title>  (<date>)'; } > "$T/dec"
mv "$T/dec" "$W/decisions/DECISIONS.md"
stat
check "with no decision yet the next id is D-001" '[ "$SRC" -eq 0 ] && grep -q "^- next decision id: D-001$" "$W/STATUS.md"'
printf '\n### D-008 — the eighth  (a date)\n' >> "$W/decisions/DECISIONS.md"
stat
check "with D-008 in the file status.sh still exits 0 and names D-009" '[ "$SRC" -eq 0 ] && grep -q "^- next decision id: D-009$" "$W/STATUS.md"'
SRC=0; ( cd "$R" && sh .apsolut-agents/scripts/session-end.sh fake HOLD "a test" ) > "$T/send.out" 2>&1 || SRC=$?
check "session-end.sh finishes and regenerates the facts" '[ "$SRC" -eq 0 ] && grep -q "facts regenerated" "$T/send.out"'
printf '\n### D-010 — the tenth  (a date)\n' >> "$W/decisions/DECISIONS.md"
stat
check "D-010 is ten: the next id is D-011" '[ "$SRC" -eq 0 ] && grep -q "^- next decision id: D-011$" "$W/STATUS.md"'

echo
echo "goal-loop: $PASSN ok, $FAILN failed"
[ -z "${KEEP:-}" ] || echo "kept fixtures:$TMPS"
[ "$FAILN" -eq 0 ] || { echo "last runner output:"; tail -30 "$T/runner.out"; exit 1; }
