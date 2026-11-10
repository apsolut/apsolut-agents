# FUTURE — ideas parking lot

Crazy-but-plausible ideas for making the agents faster, safer, kinder, and smarter.
This file is **not protocol**: nothing here is promised, enforced, or even
necessarily good. The promotion path is idea → work card (or `DECISIONS.md` entry)
→ code; ideas graduate when a real run produces the scar or the second data point
that justifies them. Backlog with evidence attached lives in
`.apsolut-agents/runs/2026-08-11-field-report-and-pre-merge-review.md`.

Provenance: seeded 2026-08-11 from the night-shift field report, then extended by
a 4-agent fan-out (throughput / containment / human-experience / memory lenses),
each agent reasoning over the scripts before proposing.

## Standing constraint (not an idea — do not "fix" this)

**Agents never delete worktree folders.** The runner and delegate leave every
worktree and branch alive for morning review; the only deletion path is a human
invoking `worktree.sh done` (and even that refuses paths not matching
`*-wt-*`). Plain `done` still refuses a dirty tree. `done --jar` and
`done --reject "<why>"` (v0.8.0) may remove a dirty tree only after writing
`runs/evidence/<id>/`, and `--reject` also appends `runs/verdicts-YYYY-MM.md`.
Nothing in the runner or delegate calls them. Auto-cleanup is still refused:
a worktree is the evidence of what a bypass-permissions agent did. `worktree.sh
review` is the read-only list that makes the human step obvious.

## The big one: Docker-isolated lanes

Run a whole lane (or every lane) inside a container. Everything that is forbidden
on the host because the blast radius is your machine becomes cheap inside:

- **Aggressive cleanup becomes safe** — prune worktrees, delete branches, rearrange
  the checkout, `git gc`, wipe scratch dirs: the container is the sacrifice zone,
  and the host keeps the only durable copy (a bare repo mounted read-only, or a
  push-gateway remote the container can push branches to but never force-push).
- **Real resource caps** — CPU/RAM/disk quotas per lane instead of trusting a
  timeout; a runaway build can't take the laptop down at 3am.
- **Network policy as config** — default-deny egress with an allowlist (provider
  APIs, package registries); an agent that decides to `curl` something weird gets
  a connection refused instead of a security incident.
- **Reproducible lane env** — the image pins toolchain + CLI versions, so "works
  in the lane" means the same thing every night and on every machine.
- **Disposable acceptance tests** — chaos-test runner.sh/delegate.sh against a
  containerized fake repo on every CI run, including kill/-9 and disk-full cases
  we currently only reason about.

Sketch: `Dockerfile.lane` + `lane.sh <agent>` wrapper (docker run with the mounts
and caps from HEARTBEAT keys like `lane_image:`, `lane_memory:`, `lane_net:`).
Keeps the no-daemon soul — the container lives exactly as long as the lane does.

## Faster

- **Overnight branch stacking** — shipped in v0.9.0 for goal mode, as the night
  integration branch instead of per-card stacks. `worktree.sh spawn --base`
  spawns every card from `agent/night/NIGHT-<date>`, verified cards merge onto it,
  and `after:` clears on integration. Plain board mode is unchanged (`after:` still
  clears only on merge). Still open: per-card `stack: true` outside goal mode.
- **Warm worktree seeding** — every spawn pays the full `npm ci` / first-build tax
  inside the card's own time cap. A `seed_dirs:` HEARTBEAT key: when a sibling
  `*-wt-*` worktree already has the artifact dirs (`node_modules/`, `target/`,
  `.venv/`), `worktree.sh spawn` hardlink-copies them (`cp -al`) — N installs
  become 1, and every card gets its whole 45 minutes back. First step: the
  `cp -al` fast path in spawn.
- **Wide lane** — one runner holds `lane_width: K` cards in flight (claim → spawn
  → dispatch backgrounded, harvest loop collects finishes). The `mkdir claims/`
  mutex and worktree isolation already make this collision-safe; what serializes
  the night is only the shape of the `while` loop. Breaker + budget checks move
  to the harvest loop. First step: extract the card body into a function and run
  two instances in a supervised `--once` pass. (Independently validated 2026:
  Claude Code Agent Teams converged on the same shape — lead + shared task list +
  self-claiming teammates.)
- **Tiered green** — optional `green_fast_cmd:` (lint + targeted tests, seconds)
  runs before the full suite; fast-fail skips straight to retry with the fast
  output as context. Full `green_cmd` remains the only path to `status: review` —
  the tier only short-circuits red, never softens green. First step: one `if` in
  the verdict block, key absent = current behavior.
- **Warm lanes / session reuse** — today every card pays cold-start (CLI boot,
  repo discovery, context ingestion). Keep one session per lane alive across
  cards, or exploit provider prompt-caching by keeping the boilerplate prefix
  (rules + PROJECT.md) byte-identical across dispatches.
- **Speculative duel** — dispatch the same card to two models in two worktrees,
  first green branch wins, loser is killed and its round refunded. Costs ~2× per
  card, buys the best-of-both quality and a live capability benchmark for free.
- **Single-branch merge gate** — shipped in v0.8.1. `done --merge` builds the
  merge inside the agent worktree, runs `green_cmd` there, and fast-forwards the
  primary branch only if it passes. A fresh worktree is not used (no installs).
  The primary branch is never reset.
- **Candidate freeze** — shipped in v0.8.2. `green_cmd` must leave the merge
  commit unchanged, or the primary branch stays put. `review <id>` prints
  committed-tree conflict paths. A clean preview is not `green_cmd`.
- **Morning merge-train** — take the accepted branches in dependency order,
  rebase each onto the accumulating result, re-run green per step, stop on the
  first conflict for the human. Turns N manual merges into one supervised pass.
- **Multi-lane scheduler** — claude + grok lanes concurrently with per-lane
  budget slices (the claim mutex already makes this collision-safe; missing is a
  combined report and a shared breaker).
- **Pre-card budget gate** — refuse to start a card when remaining budget is
  below the rolling per-card average (kills the overshoot-by-one-card gap).

## Safer (containment & audit)

- **Structural no-push** — shipped in v0.8.0. `worktree.sh spawn` sets
  `extensions.worktreeConfig` and then `git config --worktree remote.<name>.pushurl
  no_push://refused` for every remote. The primary checkout is not sealed.
  The prompt still says do not push.
- **Round-boundary tamper canary** — runner half shipped in v0.9.0: `runner.sh`
  checksums HEARTBEAT.md, GOAL.md, prompts/ and scripts/ around every agent call.
  A mismatch raises the Andon (exit 5). Not covered: the spend file, claims/ and
  the log (lanes legitimately write them), and `delegate.sh` rounds. Original note:
  the caps and ledgers are plain files a
  bypass delegate can rewrite via `.primary` (HEARTBEAT.md, spend file, claims/,
  its own card, the log). Prevention needs Docker; detection needs a checksum:
  snapshot sha256s at dispatch, re-verify after the round, diff the log for
  anything beyond the script's own appends — mismatch → verdict `TAMPERED`, card
  blocked, branch quarantined unmerged. First step: hash HEARTBEAT.md + the spend
  file around the `wait` in delegate.sh and refuse a green verdict on mismatch.
- **Un-spoofable throttle + cost accounting** — the THROTTLED carve-out and the
  cost parser both grep the delegate's own stdout: printing "too many requests"
  buys a free un-charged retry, and the last `total_cost_usd` match wins, so a
  printed fake undercuts the ledger. Accept THROTTLED only from the CLI's JSON
  envelope or near-empty output, take the max cost match, and cap free rollbacks
  per card per day. First step: a `.throttled-<id>` rollback counter (cap 3/day)
  around the existing grep.
- **Depth check from geometry, not env** — `APSOLUT_AGENT_DEPTH` dies with an
  env-scrubbing CLI, and a delegate can invoke the primary's delegate.sh by path.
  Backstop: refuse `run` when the caller's cwd sits inside a `*-wt-*` worktree —
  the naming convention already encodes "you are a delegate" on disk, where no
  CLI can scrub it. First step: one `case "$(pwd)"` refusal at the top of run.

## Kinder to the human

- **Card scaffolder (`card.sh new <id>`)** — the filename=`id:` invariant already
  cost a full night; every current rail is a refusal after the typo. A script
  that copies `_TEMPLATE.md` to `work/<id>.md` with `id:` stamped, suggests the
  next id, and prints the `after:` overnight warning inline makes the mistake
  unmakeable instead of merely detectable. First step: copy + `sed` the id line +
  refuse existing ids.
- **Night ticker** — `notify()` fires only on blocked cards and night end, so the
  $29.12-on-$25 overshoot and $6–10 real card costs were morning surprises. Ping
  at each card completion: `<id> green|red, $X/$CAP, N cards left` — one glance
  at 3am says whether the night is worth its budget. First step: one `notify`
  line after the green/red decision.
- **Morning triage walker (`worktree.sh review <id>`)** — first step shipped in
  v0.8.0: a read-only block per sibling (ahead/behind, contained in HEAD, dirty
  count, size, exact `done` command). `review <id>` adds card status, diffstat,
  and the output tail. Still not built: green-stamp and spend on the same page.
- **Upgrade aftercare report** — two documented silent drifts (stale wired
  CLAUDE.md block; new HEARTBEAT keys never appearing in `kind=instance` files)
  are both mechanically detectable via the markers and the `key:` format.
  upgrade.sh should end every run printing "snippet drift: yes/no" and "HEARTBEAT
  keys you're missing: …". First step: diff the between-markers block against
  fresh CLAUDE-SNIPPET.md and WARN on mismatch.
- **`--rewire`** — the wired block is machine-bounded by begin/end markers, so an
  explicit opt-in flag can replace only the content between them — never anything
  outside — removing the last manual step in INSTALL.md §6 while default behavior
  stays untouched. First step: replace-between-markers mode behind a flag +
  `--dry-run` print of the swap.

## Smarter

- **Refusal/infra classifier** — `is_error:true` + near-zero output tokens ≈
  infrastructure, not work: trip the breaker instead of burning attempts across
  the board. (One field incident; needs a second data point.)
- **Learned card sizing** — mine `runs/.spend-*` and attempt outputs into a
  rolling cost/duration model per risk tag; use it for the budget gate above and
  to flag "this card is 3× your usual scope" at write time.
- **Card auto-generation** — turn a failing CI run or an issue into a draft card
  (goal + failing test pre-filled, `spike:` guessed) for the human to approve at
  evening card-writing time.
- **Cross-night distillation** — a session that reads the last N night reports +
  run outputs and proposes updates to PROJECT.md hot-files/gotchas, so lessons
  stop living only in `runs/` archaeology. (Caveat from 2026 field data:
  LLM-generated agent-memory files measurably reduce success rates vs
  human-curated ones — the human-approves gate is load-bearing, keep it.)
- **Model routing by risk tags** — cards tagged `schema`/`money` go to the
  strongest model, `spike:` research cards to the cheapest; the roster table
  grows a routing column instead of a human deciding per card.
- **`files:` enforcement** — post-card diff of declared vs touched paths (both
  inputs already exist); deviation downgrades green → review-with-warning.
  (Field report F8.)
- **Per-card-start spend accrual** — write the fallback cost at claim time and
  true it up at completion, so mid-run `delegate.sh status` shows real spend and
  the overshoot window shrinks.
- **`refs:` card field (rich references)** — agents imitate a concrete artifact
  better than they parse a spec. A frontmatter list (an exemplar file, a commit
  that did something similar, a doc) that the runner inlines into the prompt as
  "imitate the shape of these" — vague cards produce less confident 3am garbage
  when they point at something real. Pure frontmatter + prompt assembly. First
  step: `refs:` in `_TEMPLATE.md` + a cat/log of each listed path into the
  dispatch prompt. (From the rules→judgement / rich-references agent-design
  slide, 2026-08-11.)

## Compounding memory

- **Verdict ledger** — first step shipped in v0.8.0. Every `worktree.sh done`
  appends `runs/verdicts-YYYY-MM.md` (`merged`, `removed`, `jar`, `rejected`).
  `--reject "<why>"` archives `runs/evidence/<id>/` first, then removes the
  worktree and sets the card `abandoned`. The branch is kept. Risk tags and a
  per-agent green-and-merged rate are not derived yet.
- **Scar injection at dispatch** — cards declare `files:` and `risk:`; decisions
  declare "applies to"; a `GOTCHAS.md` of `glob: one-line lesson` entries closes
  the triangle. At dispatch the runner greps GOTCHAS + DECISIONS for lines whose
  globs/tags intersect the card's and prepends the ≤10 matches to the prompt —
  the 3am agent gets exactly the lessons about the files it is touching,
  mechanically. Capture is human/foreman; replay is grep. First step:
  `delegate.sh run --note` also appends the note to GOTCHAS.md keyed by the
  card's globs.
- **Prior-attempt feedback on re-dispatch** — retries within a night shipped
  (v0.7 failure context; v0.9 adds the verifier's verdict and an advisor's
  diagnosis). Still open: re-claiming a card blocked on an earlier night. Blocked notes already have a fixed
  shape "so scripts can aggregate it later" (PLAYBOOK §5), but a re-claimed card
  gets the same prompt it failed with and can repeat the identical dead end at
  full token cost. On retry or re-claim of a previously-blocked card, prepend the
  card's own `Attempted:/Failed because:` block as "previous attempt — do not
  repeat this approach". First step: include the blocked note in the retry
  prompt.
- **Evidence jar (second-data-point collector)** — half the deferred backlog is
  gated on "needs a second data point," yet kill-cleanup destroys the raw CLI
  output that *is* the data point (the throttle-regex corpus had to be built by
  hand). On every non-green terminal outcome, save the output tail to
  `runs/fixtures/<class>/<date>-<id>.txt` and let CI run the throttle/refusal
  regexes against the whole jar — every incident becomes a permanent regression
  test. Rules stay rule-based; the jar is how they earn their next rule. First
  step: copy the last 100 lines of attempt output into `runs/fixtures/` on
  non-green.
- **`recall` command** — knowledge survives (archive/, runs/, DECISIONS.md) but
  only for an agent that knows to grep four places; sessions re-ask questions the
  archive already answers. `recall.sh <topic>`: one grep sweep ranked decisions →
  verdicts → runs → log → archive, printed as file:line hits with a one-screen
  cap — the read-side twin of `status.sh`. First step: a 20-line script that
  greps the locations in fixed priority order.
- **Capture-time auto-memory** — the standing principle, stated once: every
  script that *learns* something records it as a side effect of running, never as
  someone's discipline. status.sh already does it for facts; the verdict ledger,
  GOTCHAS auto-append from `--note`, and the evidence jar are all instances. The
  next cheap one: the runner writes a one-line per-card history
  (`<date> attempt N verdict $cost`) into the card's own Notes at each terminal
  state, so a card carries its full biography. First step: one `printf >> card`
  in the runner's verdict block. (From the auto-memory agent-design slide,
  2026-08-11.)

## From the v0.9 goal loop (2026-11-09)

- **Goal mode for `delegate.sh`.** The attended path still has no handoff parsing,
  verifier, or trail. Reuse the runner's `p_render` and handoff helpers instead of a
  second copy.
- **Live verifier lane.** `live-verified` needs the project's control surface
  (dev server, browser, CLI) inside the verifier's worktree. Without Docker lanes
  that means ports, so serialize live verification with a mutex, as dyl-stack does
  for UI driving.
- **Cross-night goal memory.** A goal that takes three nights restarts its plan
  rounds each night. Carry `STUCK`, plateau premises and the last round's
  failures into the next night's first planner prompt.
- **Swarm verify for risky cards.** When cards are tagged `schema`/`api-contract`,
  run two verifiers on different models and integrate only on two passes (pstack
  autopilot-full). Cost is about 2×, so make it tag-gated, not default.

## From the v0.10 four-model review (2026-11-10) — raised, not shipped

Raised by the blind review (Claude, Codex, Grok, agy), left out of v0.10 on purpose.

- **Process-group containment.** `timeout` kills the CLI, not the dev server or test
  watcher it started. Under Git Bash, native children can outlive it and hold
  ports, so the next verifier comes back `verifier-blocked`. Needs `setsid`/process
  groups on POSIX and Job Objects on Windows. Docker lanes solve it outright.
- **Real isolation.** Worktrees plus a sealed pushurl do not stop a
  bypass-permission process from writing the primary checkout or shared git
  metadata. The tamper canary detects; it does not prevent. Same answer: Docker lanes.
- **A score ratchet.** An optional `score_cmd` that prints a number (acceptance
  tests passing, TODOs left). `integrate()` would refuse a merge that lowers it, and a
  flat score across rounds would define the plateau. Raised by three reviewers in
  three shapes (Claude's score, agy's metrics_cmd, Codex's measurements); needs one
  design.
- **Failure-mode routing.** A timeout should go back to the planner as "split
  <id>", not retry at the same size. A CLI or tool error should retry on a
  `fallback_agent` from another family (orchestrate's loop-hygiene). Today every
  red is the same retry.
- **A project control recipe for `live-verified`.** pstack's
  create-verification-skill: launch, readiness, drive, evidence, teardown. Without
  it, a generic verifier falls back to reading tests.
- **Advisor before the first "done" on risky cards**, not only after a failure
  (advisor's stop-hook checkpoint). Tag-gated, like swarm verify.
- **A stall detector.** Kill an attempt whose output has not grown and whose
  worktree has not changed for `stall_minutes`, instead of letting it burn the full
  card cap.
- **Disagreements, not adopted.** Claude would cut the advisor (fold it into a
  cross-model retry) and the plateau rule. Grok would cut the morning reviewer and
  `spike: true`. agy would remove plain board mode and always integrate. Each came
  from one reviewer only, so none changed.

## From the v0.11 three-model consult (2026-11-10) — raised, not shipped

Claude, Grok and agy judged six proposals against the code
(`.apsolut-agents/runs/2026-11-10-lane-caps-consult.md`). Four shipped in v0.11.
These did not.

- **Native sandboxes before Docker lanes (2 for, 1 against).** `codex exec -s
  workspace-write`, `grok --sandbox`, `agy --sandbox`. agy's objection is a fact
  about git: a worktree's `.git` is a file pointing at `<repo>/.git/worktrees/<name>`,
  and objects live in `<repo>/.git/objects`, so a sandbox limited to the worktree
  blocks the worker's own commit. The reviewer also reads the report, the trail and
  the repo outside its cwd. First step, if any: the read-only roles (verifier,
  advisor), with the git directory added as a second allowed path. Needs one trial
  per CLI on Windows. claude has no `--sandbox` flag.
- **Schema-enforced final output (0 for, 3 against). Do not re-raise without new
  facts.** The handoff is a file, and a file survives a timeout kill; `--json-schema`
  output exists only when the CLI finishes. One `cmd_` line serves every role and
  the preflight probe, which expects the word `ok`. The envelope differs per vendor
  and the scripts have no JSON parser.
- **A vendor-native goal loop (0 for, 3 against).** Claude `/goal` and workflows,
  Codex goals, Grok leader/worker and agy remote agents all keep author and judge
  inside one vendor. The runner's point is that the judge is a script and the
  verifier is another model family.
- **claude loads the signed-in account's MCP servers and claude.ai connectors in
  headless runs** (checked: 25+ servers in a `claude -p` init event, none with
  `--strict-mcp-config`). With permissions bypassed a worker can call them, and
  worktree isolation does not contain that. Raised by one reviewer, so it is a
  `doctor.sh` warning and a documented flag, not a default: the flag also drops a
  project `.mcp.json`.
- **agy has no flag to switch off its subagents or daemon tasks**, and it writes
  plans and scratch files under `~/.gemini/antigravity-cli/brain/<conversation>/`,
  outside the worktree. A handoff written there is never collected.
- **Does grok's `total_cost_usd` include its subagents' spend?** Unknown. v0.11
  switches them off, which avoids the question.
- **claude's result `subtype`** has more values than the runner reads
  (`error_during_execution`, `error_max_structured_output_retries`). They arrive
  with `is_error:true`, so they are red already; only the label is generic.
- **codex and agy print no cost.** v0.11 lets each have its own fallback and
  per-minute rate. Pricing from the token counts they do print would be exact.
