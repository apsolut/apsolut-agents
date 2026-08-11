# Changelog

All notable changes to apsolut-agents. Pin a release with `install.sh --tag vX.Y.Z`;
upgrade an installed workspace with `sh .apsolut-agents/scripts/upgrade.sh`.

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
