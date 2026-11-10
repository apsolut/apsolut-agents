# Changelog

All notable changes to apsolut-agents. Pin a release with `install.sh --tag vX.Y.Z`;
upgrade an installed workspace with `sh .apsolut-agents/scripts/upgrade.sh`.

## v0.10.0 — 2026-11-10

Hardening from a blind four-model review. Claude, Codex, Grok and agy each read v0.9
and the Cursor plugins on their own. All four said to keep apsolut-agents as the
engine (the plugins only drive Cursor's own agents and cannot run Claude Code, Grok,
Codex and agy against each other), and to move every rule a script can check out of
the prompts and into `runner.sh`. Every item below was flagged by at least two
reviewers and checked against the code first.

### Fixed
- **False throttles.** Any output that mentioned "rate limit" or "Internal Server
  Error" (a card about rate limiting, a test log) was read as a provider throttle:
  the work was reset, no attempt was counted, no spend was charged, and the loop
  repeated until stop time. Now only a failed call (non-zero exit or `is_error`)
  can be a throttle, judged on its last 40 lines. Every call is charged, and after
  `max_backoffs_per_card` (3) throttles the card counts the attempt. `delegate.sh`
  gets the same detection fix (a failed call, judged on its last lines); its
  rounds are still not charged on a throttle.
- **Stranded cards.** A card that conflicted with the night branch, or went red
  there after the merge, used to stay in `review` and never landed, and its
  dependents never ran. "Merges are tasks": it is now a red attempt, and every
  attempt starts from the current night tip.
- **Prompts too long for the command line.** The rendered prompt went through argv
  despite the code comment. Retries and planner rounds outgrow Windows' 8–32 KB
  command-line limit, so the CLI failed before the model ran. New:
  `prompt_<agent>: stdin`; otherwise argv up to `prompt_arg_max_bytes` (6000), then
  a one-line pointer to the prompt file.
- **The planner prompt contradicted goal mode.** It said `after:` never gives code
  visibility, which is wrong on the night branch, so planners merged dependent work
  into oversized cards. The rule is rewritten.
- **`--once` was not one pass.** It ran the whole board. `--once` is now exactly one
  card, and the old behaviour is `--drain`.
- **Verifier evidence was deleted** as soon as its verdict was read. It now moves
  to `runs/evidence/<id>-verify<n>/`.
- **The planner could erase a merge.** It ran in the night worktree without the
  integration lock, and its "undo stray edits" reset could wipe another lane's
  integration. It now plans in a detached snapshot.
- **A verdict was thrown away when tests left untracked files** (coverage,
  `.tsbuildinfo`, sqlite). The read-only check now compares HEAD and tracked
  files only.
- **The handoff parser** read only the first line under the exact heading. It now
  accepts `## Status: blocked`, bold text, bullets and fences. A handoff printed as
  the final message is recovered, and a synthetic handoff carries the output tail.
- A restart after midnight opened a new night from `main` and reset the budget.
  `runs/.night-current` now keeps the night for 18 h. Attempt counters are per night.
- A timed-out run was charged the $2 fallback. It is now charged at least
  `cost_per_minute_usd` × minutes. Lanes now share the spend ledger under a lock.
- `stop_time` at 12:00 or later never fired. `CARD IS WRONG:` matched anywhere in
  the advisor's text, even when quoted. The test-first gate matched words like
  "latest". When the runner detects a red, the worker's notes are no longer shown
  as "Would unblock".

- Second review round (Codex and Grok on this diff) found seven more, fixed before
  release. The preflight probe now uses the lane's own prompt transport, so
  `prompt_<agent>: stdin` CLIs can start. The card snapshot is kept across retries
  (it used to be retaken on each claim, so attempt 1 could weaken attempt 2's
  contract) and dropped when the card blocks. `protect:` globs reach git literally
  instead of being expanded by the shell. The night file records its start time
  portably (`date -r` differs on macOS), and the last lane out closes it. A handoff
  printed inside a JSON envelope is recovered. The card's `check:` runs again on
  the merge candidate. The prompt pointer names a copy inside the cwd
  (`.apsolut-out/prompt.md`), because a native Windows CLI cannot open an MSYS
  `/c/...` path written in a sentence. Integration accepts untracked green output.
  "not blocked" no longer reads as `blocked` (the token must be the first word).
  A timeout is never a throttle. `doctor.sh` fails a `setup_cmd` that edits tracked
  files.

### Added
- **`protect:`** (HEARTBEAT and GOAL.md): git pathspecs no card may change, meaning
  the predicate's tests, the green script and CI config. A card diff touching one is
  red, and a night whose diff touches one cannot meet the goal. The card is
  snapshotted at claim, so a worker editing its own `verify:` or Done-when changes
  nothing.
- **`check:` on cards.** The runner runs it before the change (it must fail, or the
  card is refused) and after (it must pass). Planner cards must carry one. In goal
  mode with no verifier, only cards whose check passed integrate; the rest wait as
  `unverified`.
- **`forbid_added:`**: added diff lines matching it (`.skip(`, `.only(`,
  `@ts-ignore`, `eslint-disable`, …) turn the attempt red.
- **`setup_cmd:`** runs once per fresh worktree (cards and the night branch),
  outside the attempt clock. `doctor.sh` proves it in a pristine worktree.
- **`check_timeout_minutes:`** (30) caps setup, green, check and done_cmd.
- Roles write into `<worktree>/.apsolut-out/` (git-excluded), so CLIs sandboxed to
  their cwd can report. The runner collects the files into `runs/`.
- Worker prompts carry the handoffs of their `after:` cards. Retry and advisor
  context is ordered reason, verdict, handoff, output, then the diff.
- Two `verifier-blocked` verdicts in a row raise the Andon.
- Planner cards are normalised: `owner: any`, no pinned branch, `after:` must
  name known cards, no `spike: true`.
- `doctor.sh` now fails when `timeout` is not GNU and when `done_cmd` already
  passes, warns when `protect:` is empty, and runs `setup_cmd`. The runner refuses
  a non-GNU `timeout` at boot.
- `tests/goal-loop.sh` grows from 28 to 43 checks across 12 scenarios: false
  throttles, pointer and stdin prompts, protected paths, forbidden patches, check
  before and after, no-verifier goal mode, `--once`, and handoffs printed to stdout.

## v0.9.0 — 2026-11-09

The goal loop. A night can now run until a checkable "final product" predicate
passes, not just until the card list is empty. Patterns adapted from the Cursor
plugin set (pstack, orchestrate, advisor, thermos, dyl-stack, agent-compatibility,
pr-review-canvas; MIT). Credits and mapping: `template/prompts/README.md`.

### Added
- **`GOAL.md`** (instance): `goal:`, `done_cmd:` (the finish predicate),
  `verify_level:`, `max_plan_rounds:`, `max_cards_per_round:`, `planner_agent:`, and
  prose for what the final product means, what is out of scope, and what must not
  change. While `done_cmd:` is empty, the runner behaves as before.
- **Goal loop in `runner.sh`.** Verified cards merge onto one night branch
  (`agent/night/NIGHT-<date>`, a card-shaped worktree) with `--no-ff`, and green runs
  again after each merge. Later cards spawn from that branch, so `after:` clears on
  integration. When the board runs dry, `done_cmd` runs on the night branch. If it is
  red, a planner writes the next cards, the runner validates them, and the loop
  continues. Stops: goal met (0); STUCK, plateau (two rounds land nothing) or rounds
  used up (6); Andon or tamper (5). The default branch never moves. In the morning,
  `worktree.sh done NIGHT-<date> --merge` lands the night as one proven merge.
- **Role prompts** in `prompts/` (worker, verifier, planner, advisor, review), rendered
  through files, so a card or diff of any size or byte content survives.
- **Structured handoffs** (`runs/handoffs/<id>-attempt<n>.md`: Status, Root cause,
  What I did, Verification, Notes, Suggested follow-ups). A missing handoff gets a
  synthetic one naming the failure mode. `Status: blocked` blocks at once, with no
  retry burned.
- **Independent verifier** (`verifier_agent:`): read-only (HEAD and `git status` are
  checked, and edits are reset). It returns a verdict on the ladder `live-verified |
  test-verified | typecheck-only | verifier-blocked | verifier-failed`. Below the
  card's `verify:` level, the attempt is red, and the verdict goes into the retry
  context. `verifier-blocked` waits in review as unverified and never integrates.
- **Advisor** (`advisor_agent:`): before a retry, a second model diagnoses the failed
  attempt, and its diagnosis goes into the retry prompt. `CARD IS WRONG:` blocks
  instead of retrying.
- **Morning reviewer** (`review_agent:`): audits the trail at night end and appends
  `## Attention` (🟢/🟡/🔴) and `## Waiting on the human` to the night report.
- **Decision trail** `runs/trail-<date>.tsv` (one row per decision) and
  `scripts/trail.sh`.
- **`scripts/andon.sh raise|clear|status`**: any agent stops every lane, and only the
  human clears it. `status.sh` and `doctor.sh` flag it.
- **Tamper canary**: `HEARTBEAT.md`, `GOAL.md`, `prompts/` and `scripts/` are
  checksummed around every agent call. A change raises the Andon and ends the night.
- `worktree.sh spawn <agent> <id> --base <ref>`.
- `doctor.sh [goal loop]` checks the Andon, prompts, and role `cmd_` lines. It warns
  on no verifier or a same-lane verifier, validates `GOAL.md`, and proves `done_cmd`
  runs in a pristine worktree.
- `tests/goal-loop.sh` + `tests/fake-agent.sh` run seven end-to-end scenarios
  (goal met via a planner round, verifier reject + advisor retry, Andon, tamper,
  STUCK, agent dead end, plain mode unchanged) against a scripted fake CLI. Wired
  into CI as `goal-loop`.

### Changed
- The night report now has Goal, a card table with verdict and integration columns,
  Waiting on you, the trail pointer and Attention.
- The lane preflight probes every role CLI, not only the lane's own.
- Night agents run with `APSOLUT_AGENT_DEPTH=1`.
- The card template gains `verify:`, `verified:` and `integrated:`. HEARTBEAT gains
  `verifier_agent:`, `advisor_agent:`, `review_agent:`, `verify_level:` and
  `helper_timeout_minutes:`. Existing `HEARTBEAT.md` files are instance files, so
  `upgrade.sh` keeps them. Add the keys by hand to switch roles on.

## v0.8.2 — 2026-10-24

`done --merge` refuses a check that changes the merge it just proved.

### Changed
- After `green_cmd` exits 0, the agent worktree must still be on that merge
  commit, with no staged, unstaged, or new non-ignored files. Ignored output
  such as `node_modules` is allowed. A fixer (`lint --fix`, `prettier --write`)
  now refuses the merge instead of landing a different tree. The same check
  runs before `green_cmd`, so `done --merge --jar` cannot carry uncommitted
  files into the result. The primary branch is not moved. Stray edits are
  copied to `runs/<id>-merge-stray.diff`.
- `worktree.sh review <id>` prints a committed-tree conflict preview. The
  all-sibling list does not. A clean preview is not `green_cmd`. A configured
  custom merge driver skips the preview, because merge-tree can run it. The
  preview may write an unreferenced tree object; it changes no ref, index, or
  file.
- `WORKTREES.md` says a dev server needs an explicit port and must not fall
  back to another one.

## v0.8.1 — 2026-10-24

`done --merge` no longer lands the merge on the primary branch and hopes.

### Changed
- `worktree.sh done --merge` detaches the agent worktree at the primary commit,
  merges the agent branch there, and runs `green_cmd` in that directory. The
  primary branch fast-forwards to that commit only when the check passes. A red
  check leaves the primary branch unmoved, returns the worktree to its branch,
  and keeps the commit at `refs/apsolut/merges/<id>`. The agent worktree is used
  because it already has `node_modules` / `.venv`. A fresh worktree does not.
- `WORKTREES.md` notes what a worktree does not isolate: installs, ports, the
  local database, and the shared files that belong on the `PROJECT.md` hot-files
  list (route table, `.env.example`, migrations directory, dependency manifest).

## v0.8.0 — 2026-10-24

Morning cleanup stays human. The runner still does not delete worktrees.

### Added
- `worktree.sh review` — read-only packet per sibling worktree: ahead/behind,
  whether the branch is already in `HEAD`, dirty count, size, and the exact
  `done` command. `review <id>` adds card status, diffstat, and the output tail.
  `session-end.sh` runs it when a secondary worktree is still open.
- `worktree.sh done --jar` and `done --reject "<why>"` — a person can remove a
  dirty worktree after `runs/evidence/<id>/` is written. `--reject` also appends
  `runs/verdicts-YYYY-MM.md` and sets the card to `abandoned`. Plain `done`
  still refuses a dirty tree and now prints the paths. The branch is kept unless
  `--merge` was passed.
- Every `done` appends a verdict line (`merged`, `removed`, `jar`, `rejected`).
  The log says `MERGED` only when a merge happened.
- **Push seal at spawn.** `worktree.sh spawn` sets `extensions.worktreeConfig`
  and `git config --worktree remote.<name>.pushurl no_push://refused` for each
  remote. The primary checkout's push URL is not changed.

### Fixed
- `doctor.sh` fails a `HEARTBEAT.md` `cmd_` line that contains `--bare`.
  `claude --bare` ignores the signed-in claude.ai account, so a runner or
  delegate exits "Not logged in" while an interactive terminal is signed in.
  Noted in `HEARTBEAT.md` and `DELEGATION.md`.

## v0.7.1 — 2026-08-11

Field incident: green_cmd used a relative path to an untracked helper — it passed
on the primary but failed in every worktree (cwd = worktree; worktrees contain
only tracked files), blocking good cards and tripping the breaker.

### Added
- `runner.sh` **baseline green**: green runs once on the pristine worktree before
  the first dispatch; failure ends the night as a HARNESS failure (exit 4) with
  no cards charged — harness breakage no longer reads as cards failing.
- `doctor.sh` proves green inside a throwaway worktree (not just the primary),
  warns when a card's `files:` entries exist but are untracked/gitignored, and
  flags cards missing required frontmatter keys.

### Fixed
- `worktree.sh` `fm_set` now inserts missing frontmatter keys instead of silently
  dropping the value — spawn on a hand-written card without `branch:`/`worktree:`
  keys used to record nothing, making the runner refuse the card.
- HEARTBEAT.md and NIGHTSHIFT.md now state the contract where it bites: green and
  card inputs live in the worktree, which contains only tracked files.

## v0.7.0 — 2026-08-11

### Added
- **`scripts/doctor.sh [agent ...]`** — one-command workspace preflight: tools,
  HEARTBEAT sanity (incl. non-numeric key detection), card contract + `after:`
  graph (missing deps, cycles, overnight-unreachable), stale claims, `green_cmd`
  on the primary, rolling cost vs budget, and opt-in live CLI probes. Exit 1 on
  any failure. (Field report 2026-08-11 — "highest-leverage next feature".)
- **Failure-context retries** (`runner.sh`): a red attempt's diff + output tail
  is saved to `runs/<id>-attempt<N>.fail` and fed into the next attempt's prompt
  — retries are no longer blind.
- **Evidence refs** (`runner.sh`): every reset pins the salvaged attempt under
  `refs/apsolut/attempts/<id>-<n>` (gc-proof); the throttle-backoff path now
  salvage-commits before resetting, so a 429 never destroys uncommitted work.
- SPDX license headers in every script; LICENSE shipped inside the payload;
  `FUTURE.md` ideas parking lot.

### Changed
- Default `night_budget_usd` raised from 25 to 100 (HEARTBEAT template + runner
  fallback).

## v0.6.0 — 2026-08-11

### Added
- **Agent-drives-agent delegation (Tier 2):** `scripts/delegate.sh` (run / status /
  tail / stop, rounds, spend ledger shared with the night runner) + `DELEGATION.md`.
- **Lane preflight probe:** `runner.sh` sends the CLI one "reply ok" probe from an
  empty temp dir on boot and refuses the lane if it fails — bad auth or a refusing
  account costs one probe, not a board of burned attempts.
- **Card filename contract enforced:** a card's filename must be exactly `<id>.md`;
  the runner refuses the lane on mismatch, `delegate.sh run` refuses the card, and
  `status.sh` warns. (A mismatch used to half-work, then silently miss downstream.)
- `status.sh` warns when a waiting card's `after:` can never clear overnight
  (deps only clear on merge).
- Green output stamps the exact commit (`green_cmd @ <sha>`) in delegate/runner output.
- `template/.gitattributes` (`*.sh text eol=lf`) so installed scripts survive
  Windows checkouts with `core.autocrlf=true`.
- LICENSE (MIT), this changelog, and CI (shellcheck + installer smoke test).

### Fixed
- `install.sh` exited 1 after a fully successful `--wire` run.
- `install.sh` piped via curl no longer trusts a foreign `template/` directory in the
  target project as the payload; the installer body is also `main()`-wrapped so a
  truncated download executes nothing.
- `delegate.sh stop` killed the supervisor before the agent CLI, orphaning a
  bypass-permissions agent; the parent's cleanup also deleted the stop flag mid-stop.
- `upgrade.sh` overwrote its own file while executing; it now re-execs a temp copy.
- Provider-throttle detection false-positived on commit SHAs containing 429/50x and
  on ordinary "server error" app output — and then reset real work at 3am.
- `status.sh` reported the log template's own example line as the last session token.

## v0.5.0 — 2026-07-29

- Drop-in distribution: self-bootstrapping `install.sh` (`curl | sh`, `--wire`,
  `--tag`, `--dry-run`, `--refresh`), in-payload `scripts/upgrade.sh`, VERSION
  stamping, `kind=doc|instance|generated` refresh rules.
- Night Shift v0 (`runner.sh`, `HEARTBEAT.md`, `NIGHTSHIFT.md`), git-worktree
  multiplexing (`worktree.sh`, `WORKTREES.md`), status board and session-end
  automation — the pre-distribution history lives in git.
