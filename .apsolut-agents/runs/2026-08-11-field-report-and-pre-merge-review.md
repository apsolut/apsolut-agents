<!-- apsolut-agents: tier=1 kind=instance -->
# 2026-08-11 — Night-shift field report triage + 3-agent pre-merge review (v0.6.0)

Two evidence streams converged on the `feat/delegation-and-installer-fixes` branch
before its merge to main:

1. **Field report** — a Claude session ran the full cycle (install → fill-in → two
   supervised passes → one live night) on a real project and reported back.
2. **Pre-merge review fan-out** — 3 subagents (shell correctness / docs parity /
   upgrade opportunities), ~220k tokens, ~5 min wall. Docs parity: clean. Shell
   review verdict: NOT safe to merge as-is (4 confirmed bugs, each reproduced).

## Fixed this session (all in v0.6.0)

| # | Defect | Fix |
|---|---|---|
| R1 | `delegate.sh stop` killed the supervisor first; its cleanup trap deleted the stop flag + `agent.pid`, orphaning the bypass-permissions agent CLI | read both pids upfront, kill agent first; cleanup stands down when `stopped` flag exists |
| R2 | `upgrade.sh` cp'd over its own file mid-execution (POSIX sh reads incrementally) | re-exec from a temp copy; WS travels via env |
| R3 | throttle regex matched commit SHAs containing 429/50x and generic "server error" text → 3am `reset --hard` loops destroying real work | status codes only count next to http/status/api-error/code markers; added 529 |
| R4 | `curl \| sh` install from a repo with its own `template/` dir silently installed garbage as the workspace | local template/ only trusted if it contains PROTOCOL.md + scripts/status.sh; installer `main()`-wrapped against truncated downloads |
| F1 | card filename ≠ `id:` half-works then silently misses every downstream step (cost the reporter a night) | runner refuses the lane, delegate refuses the card, status.sh warns, template documents |
| F4 | no lane preflight — a refusing/broken CLI marched the whole board burning attempts | boot probe ("reply ok", empty temp cwd, 3 min cap); lane refused on failure |
| F7 | `after:` deadlocks by construction overnight; template offered it with no warning | warning at point of use in `_TEMPLATE.md` + status.sh flags unreachable cards |
| — | status.sh reported the log template's example line as the last session token | filter `<`-containing headings |
| — | `finish()` report loop crashed via `set -e` if work/ glob was empty | `[ -f ] \|\| continue` guard |
| F2 | two-dot diffstat in the night report | already three-dot on this branch — reporter's installed copy predated it; no change needed |

Also shipped: LICENSE (MIT — human choice), CHANGELOG.md, VERSION 0.6.0,
`template/.gitattributes` (`*.sh eol=lf` for Windows checkouts), GitHub Actions CI
(shellcheck -S error + installer smoke test incl. the INSTALL.md §1a parity diff),
HEARTBEAT comments (budget checked between cards; fallback cost is 3–5× low),
README: v0 supervised gate advertised as the feature it is.

## Deferred — needs a second data point or real design (next-session backlog)

- **F3 refusal classification:** `is_error:true` + `terminal_reason: api_error` +
  near-zero output tokens ≈ infrastructure, not work — should trip the breaker, not
  burn attempts. One incident so far; the preflight probe cuts most of the blast radius.
- **F5 cost fallback:** observed $6–10/card vs 2.00 default — comment added; rolling
  average from `runs/.spend-*` is the real fix.
- **F6 budget overshoot:** cap checked between cards ($29.12 on a $25 cap observed) —
  documented; refuse-to-start-below-rolling-average is the real fix.
- **F8 `files:` enforcement:** post-card diff-vs-declared comparison (nearly free,
  both inputs exist).
- **Per-card-start spend total** (mid-run ledger reads 0 → live monitoring impossible).
- **`doctor` command:** probe model + check timeout/jq/git + green_cmd on primary +
  validate card filenames and `after:` graph + rolling cost vs budget. The highest-
  leverage next feature per the field report.
- Review minors: lane-recovery TOCTOU, unlocked spend read-modify-write (undercount
  only), `date -r` mtime is GNU-only (macOS lane recovery), silent detach-guard
  failures, non-detach concurrency race.

Verdicts on the record: field report's certain bugs (F1, F2) verified — F1 real, F2
already fixed; both its extrapolated proposals deferred pending second data point,
exactly as the report itself recommended.

## Adversarial verify round (4th agent, ~130k tokens, ~13 min)

Tried to refute every fix; all held (stop fix live-tested against fake pids, installer
smoke incl. dry-run-writes-nothing, probe fail paths release the lane, parity exact,
shellcheck -S error clean). Verdict: SAFE TO MERGE. Its three confirmed quality gaps
were fixed before merging: status.sh dep-ready check aligned to runner's done-only rule
(review ≠ mergeable), throttle regex extended ("status code 429", "too many requests",
"service … unavailable", ISE/bad gateway — 10/10 corpus), upgrade.sh temp-copy cleanup
trap installed before arg parse. Remaining minors on the backlog: probe "ok" echo-match
laxity, filename validation bricks a lane on historical misnamed cards, stop-vs-natural-
completion timing race (work preserved), hand-killed parent still orphans the agent CLI
(pre-existing), `<` filter can drop a legit heading, no downgrade guard in upgrade.sh.
