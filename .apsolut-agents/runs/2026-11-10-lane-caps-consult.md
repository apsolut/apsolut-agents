# Three-model consult on lane caps → v0.11.0 (2026-11-10)

**Ask (human):** "check our system again about latest changes in industry, like agent
swarm, workflows, loops - for claude, agy, grok, codex", then "talk with agents grok,
claude, agy", then "implement all if everyone agrees they are great things to have".

**Method:**
- Claude (orchestrator) read each installed CLI's `--help` and changelog (claude
  2.1.322, codex 0.167.0, grok 1.0.70, agy 1.5.3) and wrote six proposals.
- Claude, Grok and agy each judged them alone, headless, in read-only plan mode, from
  one brief. Codex was not asked.
- Grok and agy needed a second run. In plan mode each tried a shell command, was
  refused, and exited 0 with no answer (`"stopReason":"cancelled"`, `"denied_actions"`).
  That is the "exit 0 is not finished" bug v0.11 fixes.
- Every CLI claim was then checked with a real call before any code changed.

## Verdicts

| # | proposal | Claude | Grok | agy | outcome |
|---|---|---|---|---|---|
| 1 | Codex lane | change | change | change | shipped, with per-agent cost rates |
| 2 | stop lane fan-out | change | change | change | shipped, corrected (below) |
| 3 | `--max-budget-usd` for claude | agree | change | agree | shipped, behind `call_budget_usd`; a cap hit blocks |
| 4 | agy `--print-timeout` + `finished_reason` | change | change | change | shipped, with a per-call value |
| 5 | native sandboxes before Docker | agree | change | disagree | not shipped (FUTURE.md) |
| 6 | schema-enforced handoffs | disagree | disagree | disagree | rejected (FUTURE.md) |

Native goal loop instead of `runner.sh`: no, 3/3. The judge must not be the author.

## What the real calls showed

| claim | source | checked | result |
|---|---|---|---|
| `CLAUDE_CODE_FORK_SUBAGENT=0` does not remove the subagent tool | Claude, Grok | `claude -p` init event | true: the tool is `Task`; `--disallowedTools Agent` removes it |
| a headless claude loads the account's MCP servers and connectors | Claude | init event | true: 25+ servers; none with `--strict-mcp-config` |
| a claude budget stop is `is_error:true` | Claude | `--max-budget-usd 0.01` | true: exit 1, `subtype: error_max_budget_usd`. It spent $0.60 against a $0.01 cap: the cap is checked between turns |
| agy `--print-timeout` may exit 0 | Grok, agy | `--print-timeout 3s` | false: exit 3, `status: ERROR`, `finished_reason: print_timeout` |
| `codex exec` needs a trailing `-` for stdin | Grok, agy | `--help`, a probe | optional: it reads stdin with no prompt. Kept, it is explicit |
| codex `--json` has no cost and no `is_error` | all three | a probe | true: JSONL events with token counts only |
| `codex exec` runs from a non-git temp dir (the preflight cwd) | — | a probe | true with the bypass flag |
| grok JSON has no cost field | Grok (guess) | its own output | false: `total_cost_usd` and `costUSD` are there |
| agy JSON has no cost field | agy (guess) | its own output | true: token counts only |
| `grok --no-subagents` exists | Grok (unsure) | `--help`, a probe | true |
| `claude --max-turns` exists | Claude | `--help` | not listed in 2.1.322; not used |

## Shipped in v0.11.0
See CHANGELOG v0.11.0.

## Rejected or parked
FUTURE.md, "From the v0.11 three-model consult".

## Cost
Claude $2.02, Grok $0.54, agy no dollar figure (87k tokens). Probes: about $1.

## Raw answers

### The brief

> You are one of three independent reviewers (Claude, Grok, agy) of the repo in your current directory: apsolut-agents v0.10.0, a markdown + git + POSIX-sh workspace that runs several coding-agent CLIs against each other (template/scripts/runner.sh, delegate.sh, doctor.sh; config in template/HEARTBEAT.md; roles in template/prompts/; open ideas in FUTURE.md).
> 
> This is a READ-ONLY review. Do not edit, create, stage or commit any file. Read the code before you answer; cite file and line for every claim about what the code does.
> 
> Context: the CLIs installed here are claude 2.1.322, codex 0.167.0, grok 1.0.70, agy 1.5.3. All four now ship native subagents, native goal loops or background agents, worktree flags, sandbox flags and JSON-schema output. Six changes are proposed:
> 
> 1. Add a Codex lane: `cmd_codex: codex exec --dangerously-bypass-approvals-and-sandbox --json` with `prompt_codex: stdin`.
> 2. Stop lanes fanning out unbudgeted: `--no-subagents` and `--max-turns` on the grok line; `CLAUDE_CODE_FORK_SUBAGENT=0` for claude.
> 3. Per-call spend cap for claude with `--max-budget-usd`, because night_budget_usd is only checked between cards.
> 4. Pass `--print-timeout` to agy and read `finished_reason` from its JSON, to tell a timeout from an error.
> 5. Try the native sandboxes (`codex exec -s workspace-write`, `grok --sandbox`, `agy --sandbox`) before building Docker lanes.
> 6. Replace the tolerant handoff parser with schema-enforced final output (`--json-schema` on claude/grok/agy, `--output-schema` on codex).
> 
> Answer in this exact shape, under 600 words:
> 
> ## Verdict per proposal
> For each of 1-6: AGREE / DISAGREE / CHANGE, one or two sentences, with the file:line in this repo it touches or would break.
> 
> ## What the proposals miss
> Up to 3 things about YOUR OWN CLI (you know your own headless behaviour, JSON output fields, cost reporting, subagent and sandbox behaviour best) that this system gets wrong or does not use. Say which are facts you are sure of and which are guesses.
> 
> ## Should the runner use a native loop instead
> Should runner.sh hand the goal loop to a vendor-native feature (Claude /goal or workflows, Codex goals, Grok leader/worker, agy remote agents)? Yes or no, and the one strongest reason.
> 
> ## Order
> The proposals you would ship, in order, and the one you would drop.

### claude

Review complete; all file reads and CLI help checks were read-only.

## Verdict per proposal

1. **CHANGE.** The line is already documented at `template/DELEGATION.md:79` but missing from `template/HEARTBEAT.md:99-101`. Codex `--json` is JSONL with no cost field and no `is_error`, so `charge()` (`runner.sh:163-164`) always bills the fallback and the checks at `runner.sh:377` and `:1015` never fire. Ship it with a codex-specific fallback cost.
2. **CHANGE.** The grok half is right: both flags exist in `grok --help`. The claude half is wrong: in the 2.1.322 binary `CLAUDE_CODE_FORK_SUBAGENT=1` forces subagents into the background, and `=0` is not an off switch. Use `--disallowedTools Agent` and `--max-turns` on `HEARTBEAT.md:99`.
3. **AGREE.** The flag exists and closes the gap admitted at `HEARTBEAT.md:13-14`. A budget stop returns `is_error:true` with `total_cost_usd`, so the charge is right, but `runner.sh:1015` labels it generically and `red()` (`runner.sh:738`) retries it at full price.
4. **CHANGE.** The runner already tells a timeout from an error by exit code (`runner.sh:174`, `:1010`). The real gain is agy exiting cleanly with JSON before `timeout -k` kills it. The `cmd_` line is static (`runner.sh:213`) while the cap is per card (`runner.sh:907`), so it needs a substituted value.
5. **AGREE.** Role output already lands inside the worktree for this reason (`runner.sh:51-53`), and the runner commits for the agent (`runner.sh:994-997`). A sandbox would turn the tamper canary (`runner.sh:243-259`) from detection into prevention. Start with the read-only roles.
6. **DISAGREE.** The handoff is a file (`prompts/worker.md:29`, `runner.sh:961`) that survives a timeout kill; schema output exists only if the CLI finishes. Stdout is also merged with stderr (`runner.sh:228`), the scripts have no JSON parser, and the envelope differs per vendor.

## What the proposals miss

1. **Fact:** headless `claude -p` loads user settings, plugins, skills and MCP connectors. This review session came up with cloud connectors attached. With `--dangerously-skip-permissions` (`HEARTBEAT.md:99`), a worker can call them, and worktree isolation does not contain that. `--bare` is rightly banned (`HEARTBEAT.md:95-98`). `--strict-mcp-config` and `--setting-sources project` exist; that they keep OAuth and drop claude.ai connectors is a guess.
2. **Fact (binary schema):** the result JSON carries `subtype` (`error_max_turns`, `error_max_budget_usd`, `error_during_execution`, `error_max_structured_output_retries`) and `num_turns`. The runner reads only `is_error`. **Fact:** `--output-format json` prints one object at exit, so a timeout kill bills minutes × rate (`runner.sh:164`), not real spend. **Guess:** `total_cost_usd` includes subagent spend.
3. **Fact:** claude has no `--sandbox` flag, which is why proposal 5 omits it. **Guess:** a `sandbox` settings key passed through `--settings` would cover it, and whether that enforces on native Windows is unknown.

## Should the runner use a native loop instead

No. The runner's value is that the judge is not the author: it runs `done_cmd`, `green_cmd` and `check:` itself (`runner.sh:473`, `:1032`, `:1051`), with a cross-vendor verifier and one shared ledger. A native loop self-certifies inside one vendor.

## Order

Ship 3, then 2 (corrected), 1, 5, 4. Drop 6.

### grok (second run)

I'll review the runner, heartbeat, and prompts against the six proposals, using only file reads and search. No commands and no edits.## Verdict per proposal

1. **CHANGE.** Add the lane, but the argv is wrong: `prompt_codex: stdin` runs `sh -c "$c"` with the prompt only on stdin (`runner.sh:226-228`), and `HEARTBEAT.md:87-88` says that requires `codex exec -`, which this command lacks. `--json` is JSONL, while `charge()` and preflight look for `total_cost_usd` and `is_error` (`runner.sh:163`, `377`); the bypass flag also turns the sandbox off, cancelling proposal 5. `DELEGATION.md:79` already shows this command; `HEARTBEAT.md:99-101` does not, and `delegate.sh:297-300` would inherit it.

2. **CHANGE.** Children are a real hole, but these flags go on the one `cmd_` line shared by every role, preflight, and delegates (`HEARTBEAT.md:91`, `runner.sh:366-385`). A flag grok rejects fails the probe and the lane never starts (`runner.sh:379-385`). I am sure headless grok can `spawn_subagent` in the background, and this runner only waits on and charges the parent (`runner.sh:224-233`, `960`); I am not sure `--no-subagents` exists on grok 1.0.70, and `CLAUDE_CODE_FORK_SUBAGENT=0` does not remove Claude's Task tool. `--max-turns` on that shared line also caps the verifier, and two blocked verifiers raise the Andon (`runner.sh:1099-1101`).

3. **CHANGE.** The hole is real: the cap is checked only between cards (`HEARTBEAT.md:13-16`, `runner.sh:782`), then advisor, worker, and verifier are charged on return (`runner.sh:921`, `960`, `1075`). Put `--max-budget-usd` behind a HEARTBEAT key for Claude calls only. A cap hit is a non-zero exit, so `red()` retries it (`runner.sh:738`, `1027-1030`) and can pay the cap twice, and `delegate.sh` shares `cmd_claude`.

4. **CHANGE.** GNU `timeout` already records 124/137 as a timeout, not a throttle (`runner.sh:174`, `1010`). Green is allowed when the exit code is 0 (`runner.sh:1027`), so if `--print-timeout` makes agy exit 0 with `finished_reason` set, a partial tree can reach `green_cmd` unless that field is read first, in `runner.sh` and `delegate.sh:366`.

5. **CHANGE.** A cwd sandbox fits the existing report path, `.apsolut-out` (`runner.sh:51-53`, `prompts/README.md:18-19`). It does not replace Docker lanes, which are CPU, RAM, disk, egress, and a pinned toolchain (`FUTURE.md:26-48`); workspace-write still allows writes to `.apsolut-agents` inside the tree, which is the tamper the canary only detects (`runner.sh:243-247`). The worker must commit and run tests (`worker.md:8-12`).

6. **DISAGREE.** Each role's contract is a file, not the final message (`worker.md:28-30`, `verifier.md:28`, `advisor.md:18`, `planner.md:33-63`), and status, verdict level, and `CARD IS WRONG:` are read from those files (`runner.sh:294-295`, `928`, `1089`). One schema on `cmd_` also binds preflight, which requires the word `ok` (`runner.sh:378`); stdout recovery is only the fallback (`runner.sh:999-1006`, `tests/fake-agent.sh:111-115`). Keep `md_section` (`runner.sh:272-285`, `CHANGELOG.md:46-48`).

## What the proposals miss

1. **Fact:** grok `spawn_subagent` defaults to background. This runner never joins those processes and never sees their stdout, so their spend cannot hit `night_budget_usd`. **Guess:** the parent JSON does not roll child dollars into a field `charge()` matches (`runner.sh:163`).
2. **Fact:** `charge()` accepts only `total_cost_usd`, `costUSD`, and `total_cost`. **Guess:** grok 1.0.70 JSON reports token usage and none of those keys, so grok nights are priced by `cost_fallback_usd` and `cost_per_minute_usd` (`HEARTBEAT.md:17-30`).
3. **Fact:** grok is arg-mode; over 6000 bytes the model only gets a pointer to `.apsolut-out/prompt.md` (`HEARTBEAT.md:87-88`, `runner.sh:215-221`). A native grok worktree flag would leave the runner's branch and fail the assert (`runner.sh:990-992`). **Guess:** `grok -p` with no operand does not read stdin, so `prompt_grok: stdin` on today's command fails preflight.

## Should the runner use a native loop instead

**No.** The judge sits outside the model and is shared across vendors: `green_cmd` and `check:` decide (`runner.sh:1026-1059`), the verifier is another family (`HEARTBEAT.md:38-39`), and lanes share one claim mutex and one ledger (`runner.sh:154-166`, `782`). A vendor goal loop is that vendor grading itself.

## Order

Ship 4, then 3, then 2, then 5, then 1, each with the changes above. Drop 6.

### agy (second run)

## Verdict per proposal

1. **CHANGE** — Adding `cmd_codex` and `prompt_codex: stdin` in [template/HEARTBEAT.md](template/HEARTBEAT.md#L86-L102) matches [`run_cli()`](template/scripts/runner.sh#L207-L229) and [template/DELEGATION.md](template/DELEGATION.md#L79), but `codex exec` needs a trailing `-` to read stdin (as noted at [template/scripts/runner.sh](template/scripts/runner.sh#L207) and [template/HEARTBEAT.md](template/HEARTBEAT.md#L87)). Also, `codex exec --json` streams JSONL without matching `(total_cost_usd|costUSD|total_cost)` in [`charge()`](template/scripts/runner.sh#L162-L166) or [delegate.sh](template/scripts/delegate.sh#L355), so it will always book `cost_fallback_usd` / `cost_per_minute_usd`.

2. **CHANGE** — Blocking subagent fan-out and runaway turns in [template/HEARTBEAT.md](template/HEARTBEAT.md#L99-L101) works because [`run_cli()`](template/scripts/runner.sh#L228-L231) and [delegate.sh](template/scripts/delegate.sh#L298-L300) invoke `sh -c "$c"`, which accepts leading env assignments like `CLAUDE_CODE_FORK_SUBAGENT=0`. Export that variable alongside `APSOLUT_AGENT_DEPTH=1` in [runner.sh](template/scripts/runner.sh#L227-L230) and [delegate.sh](template/scripts/delegate.sh#L296), and cap `agy` and `codex` subagents too.

3. **AGREE** — `night_budget_usd` is only checked before claiming a card at [template/scripts/runner.sh](template/scripts/runner.sh#L782) (and before dispatch at [template/scripts/delegate.sh](template/scripts/delegate.sh#L193) and reviewer run at [template/scripts/runner.sh](template/scripts/runner.sh#L688)). Adding `--max-budget-usd` to `cmd_claude` in [template/HEARTBEAT.md](template/HEARTBEAT.md#L99) caps single-card spend overshoot without breaking preflight probes ([runner.sh](template/scripts/runner.sh#L366-L386)).

4. **CHANGE** — Reading `finished_reason` in [template/scripts/runner.sh](template/scripts/runner.sh#L1008-L1018) improves diagnostics, but hardcoding `--print-timeout` in [template/HEARTBEAT.md](template/HEARTBEAT.md#L101) conflicts with per-card `$CB` ([runner.sh](template/scripts/runner.sh#L907)) and `$HELPER_MIN` ([runner.sh](template/scripts/runner.sh#L578), [runner.sh](template/scripts/runner.sh#L920), [runner.sh](template/scripts/runner.sh#L1074)) enforced by GNU `timeout` in [`run_cli()`](template/scripts/runner.sh#L228-L231). Worse, if `--print-timeout` exits `0` before GNU `timeout` returns `124|137`, [`throttled()`](template/scripts/runner.sh#L174) and `[ "$RC" -ne 0 ]` ([runner.sh](template/scripts/runner.sh#L1027)) will misclassify a timed-out run as a normal exit unless `finished_reason` sets `RC=124`.

5. **DISAGREE** — Native workspace-write sandboxes restricted to `$WT` break git operations inside secondary worktrees (`*-wt-*`, enforced at [runner.sh](template/scripts/runner.sh#L857-L862) and [delegate.sh](template/scripts/delegate.sh#L253-L257)), because a worktree's `.git` file points to `$REPO/.git/worktrees/<name>` and `$REPO/.git/objects` outside `$WT`, blocking the worker commits required by [template/prompts/worker.md](template/prompts/worker.md#L8). It also blocks `review_agent` from reading `$REPORT`, `$TRAIL`, and `$REPO` ([runner.sh](template/scripts/runner.sh#L691-L697)) and blocks `delegate.sh` from reading `$PFILE` under `$WS/runs/` when prompts exceed `prompt_arg_max_bytes` ([delegate.sh](template/scripts/delegate.sh#L288-L293)).

6. **DISAGREE** — Every role shares `cmd_<agent>` via [`run_cli()`](template/scripts/runner.sh#L212-L236), so putting `--json-schema` on `cmd_<agent>` breaks the `"ok"` preflight probe ([runner.sh](template/scripts/runner.sh#L378), [doctor.sh](template/scripts/doctor.sh#L313)), the file-generating `planner` ([runner.sh](template/scripts/runner.sh#L581-L599)), `advisor` ([runner.sh](template/scripts/runner.sh#L923-L928)), `verifier` ([runner.sh](template/scripts/runner.sh#L1077-L1090)), and `reviewer` ([runner.sh](template/scripts/runner.sh#L700)). Moreover, `jq` is not in [`doctor.sh`](template/scripts/doctor.sh#L39), and a process killed by `timeout` (`124|137`) emits no final JSON, whereas `.apsolut-out/handoff.md` written before timeout is still collected at [runner.sh](template/scripts/runner.sh#L961).

## What the proposals miss

1. **`agy` has native subagents (`invoke_subagent` / `define_subagent`) and background tasks (`IsDaemon`) that ignore `APSOLUT_AGENT_DEPTH` (Fact).** Proposal 2 only restricts `grok` and `claude`; `agy` can spawn `self` or `research` subagents (including in `branch` or `share` workspace modes) and daemon tasks that outlive `timeout` ([FUTURE.md](FUTURE.md#L261-L264)) unless disabled by flag or settings.
2. **`agy` writes artifacts and scratch files to `~/.gemini/antigravity-cli/brain/<conversation-id>/` outside the worktree (Fact).** [`tree_state()`](template/scripts/runner.sh#L263-L264) and [`collect()`](template/scripts/runner.sh#L239-L241) only inspect `$WT` and `.apsolut-out/`, so if `agy` writes a plan or handoff to its brain artifact directory instead of `{{HANDOFF_PATH}}`, `runner.sh` misses it and synthesizes a failure at [runner.sh](template/scripts/runner.sh#L1008-L1018).
3. **`agy --output-format json` cost reporting vs [`charge()`](template/scripts/runner.sh#L162-L166) (Guess: field name mismatch).** [`charge()`](template/scripts/runner.sh#L163) and [delegate.sh](template/scripts/delegate.sh#L355) only grep `(total_cost_usd|costUSD|total_cost)`; if `agy` reports token usage metadata rather than those exact USD keys, every `agy` run falls back to `max(cost_fallback_usd, minutes * cost_per_minute_usd)` ([runner.sh](template/scripts/runner.sh#L164)) in `runner.sh` and flat `FALLBACK_COST` in [delegate.sh](template/scripts/delegate.sh#L356).

## Should the runner use a native loop instead

**No.** `runner.sh`'s value is cross-family adversarial separation—running [`check:`](template/scripts/runner.sh#L894-L904) red-then-green ([runner.sh](template/scripts/runner.sh#L1049-L1058)), enforcing [`protect:`](template/scripts/runner.sh#L1037-L1040) and [`forbid_added:`](template/scripts/runner.sh#L1042-L1046), checksum-guarding rule files ([`guard_end()`](template/scripts/runner.sh#L252-L259)), and requiring a *different* model family as [`verifier_agent`](template/scripts/runner.sh#L1065-L1102) ([doctor.sh](template/scripts/doctor.sh#L102-L104)) before merging into `NIGHT_BR` ([`integrate()`](template/scripts/runner.sh#L441-L468))—whereas any vendor-native goal loop lets one vendor's model grade its own homework inside a single trust boundary.

## Order

1. **Ship 1st: Proposal 2** (with `agy`/`codex` subagent caps and env export in [`run_cli()`](template/scripts/runner.sh#L227-L231)).
2. **Ship 2nd: Proposal 3** (`--max-budget-usd` on `cmd_claude` in [template/HEARTBEAT.md](template/HEARTBEAT.md#L99)).
3. **Ship 3rd: Proposal 1** (with trailing `-` on `cmd_codex` in [template/HEARTBEAT.md](template/HEARTBEAT.md#L99-L102)).
4. **Ship 4th: Proposal 4** (parse `finished_reason` in [runner.sh](template/scripts/runner.sh#L1008-L1018), keeping GNU `timeout` authoritative).
5. **Ship 5th: Proposal 5** (only after passing `--add-dir "$REPO/.git"` / `$WS/runs` so worktree git commits and reviewer reads work).
- **Drop: Proposal 6** (breaks multi-role `cmd_<agent>` sharing, preflight probes, and file-based handoff recovery on timeout).

<!-- GOAL_COMPLETE -->

