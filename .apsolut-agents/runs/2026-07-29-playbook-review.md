# PLAYBOOK — 3-model synthesis (2026-07-29)

Claude draft → blind reviews (AGY/Gemini + Grok), both build-changed. Convergent (adopted): strip unimplemented DORA section (both called it the end-block failure class — 'no metric claims until status.sh computes them'); replace B2B/B2C axis with technical risk tags on cards; test-first = HARD runner gate with visible spike: waiver; fixed-shape blameless blocked note (Attempted/Failed because/Would unblock). Grok extras adopted: rollback-path as most-bitten missing item; no research name-drops. AGY extras adopted: schema backward-compat item; machine-readable rejection (status blocked + note). Tier divergence (Grok: 0, AGY: 1) resolved: file ships Tier 1, the two universal rules live in the card template itself so Tier 0 gets the substance without the file.

---
## Review: AGY (Gemini)
## Verdict
**build-changed**

Required changes:
1. Strip Section 3 (DORA-lite metrics) from `PLAYBOOK.md` until the runner/`status.sh` parser is actually implemented and tested against real run data.
2. Replace Section 4's broad B2B/B2C narrative categories with concrete, machine-checkable flag declarations (e.g., `strict_api_contract: true`, `accessibility_check: true`).
3. Codify the night-run test-first rule as an explicit, machine-enforced requirement (the runner must validate and reject cards lacking a failing-test Done-when item before starting work).

## Top 3 risks
1. **Autonomous night runs deadlock on invalid test-first setup:** An agent assigned a night card requiring "a failing test exists" gets stuck trying to setup or mock a test harness before writing implementation code, failing out at step one and burning overnight execution budget without producing usable code.
2. **Misleading DORA telemetry from git history noise:** Deriving lead time from `claimed:` to `merge` breaks whenever cards are left claimed overnight, squashed, rebased, or cherry-picked. This creates false metric regressions that trigger unnecessary process churn.
3. **Advisory creep in Section 4:** Section 4 mandates guidelines (e.g., "analytics events are named in the card", "accessibility is a Done-when item") that lack runner-level enforcement. Without script assertions in `green_cmd`, these become unenforced human rituals—violating the core filter stated in the draft header.

## What to cut
- **Section 3 (DORA-lite metrics):** As noted in the implementation notes, `status.sh` does not yet calculate these metrics. Including un-implemented metrics in a Tier-1 contract is documentation debt. Cut it until the tooling exists.
- **B2B/B2C Taxonomy in Section 4:** Dividing practices by business model (B2B vs B2C) adds vague marketing personas. Cut the persona labels and replace them with specific technical flags in `PROJECT.md`.

## What's missing
- **Machine-readable card rejection spec:** Section 2 states that vague cards are returned to the human, but specifies no exit code, status field, or runner mechanism for how an agent signals rejection without aborting the night runner pipeline.
- **Worktree session limits:** Section 1 mandates small batches based on "one worktree session", but fails to define quantitative session boundaries (e.g., maximum token spend, file change limit, or execution timeout) needed for agents to auto-split large cards.
- **Fallback for uninitialized `green_cmd`:** The playbook relies heavily on `green_cmd` to enforce rules, but doesn't define standard behavior for early-stage or greenfield Tier-1 projects where `green_cmd` has not yet been authored.

## Steelman the opposite
The strongest argument against creating `PLAYBOOK.md` is that process rules belong exclusively in runnable scripts and task schemas, not in markdown text files. If a practice is truly enforceable by `green_cmd` or measurable from git, the code and runner configurations are the single source of truth. Maintaining an auxiliary markdown playbook introduces documentation drift and forces agents to consume context window reading guidelines that their execution harness should already be enforcing automatically.

## Answers to the draft's open questions
1. B2B vs. B2C is the wrong axis because business model categories encourage vague guidelines rather than binary rules. Profiles should use explicit functional boolean flags in `PROJECT.md` (e.g., `api_contract_strict: true`). The single missing checklist item that bites most often is verifying database schema backward-compatibility prior to running migrations.
2. It must be a hard requirement enforced by the runner. If test-first for night cards is left as a convention, autonomous agents will regularly bypass writing failing tests first under context pressure or complex task prompts, destroying the safety guarantee for unattended runs.
3. Defer it entirely. Publishing metrics in a contract file before the calculation logic in `status.sh` exists creates documentation drift. Ship the metric collection logic first, validate it on real run logs, and only then add the metrics section to `PLAYBOOK.md`.
4. Section 3 is currently pure cargo cult because it declares automated metrics that the implementation notes admit aren't written yet. Additionally, Section 4's narrative rules around analytics naming and accessibility guidelines mimic traditional human process handbooks that lack automated enforcement mechanisms.
5. Tier 1 only. Forcing Tier 0 projects (quick prototypes, one-off spikes, single-file utilities) to comply with test-first constraints, profile flags, and card contract rules adds unnecessary friction to low-risk exploration.

---
## Review: Grok
# Review template — every reviewer answers ALL sections

## Verdict
**build-changed** — Keep the file and ship it, but only after: (1) demote §3 “Measure the four keys” to a one-line *intent* plus “metrics land when night data exists,” not a fake contract that nothing enforces yet; (2) make night-card test-first a **runner hard gate** or drop the “first Done-when is a failing test” language; (3) resolve profile axis (see Q1) and cut any B2B/B2C rule that isn’t already checkable from card + git in this workspace; (4) Tier 0 vs 1 decision before INSTALL.md tables land (prefer Tier 0 or “optional Tier 0 with defaults”).

## Top 3 risks
1. **PLAYBOOK becomes unread sacred text.** Agents and humans treat it like CLAUDE-end-block theater: cited in reviews, never applied at claim/green time. Within weeks, “vague cards returned to human” is skipped because the runner still accepts soft Done-when lines, and the doc’s only enforcement is social — exactly what §6 claimed to reject.
2. **Lead time and recovery metrics lie.** `claimed:` → merge mapping via `git log --merges --grep "<id>"` breaks as soon as squash merges, rebased branches, multi-card PRs, or cards that never get the id into the merge message land. Status will report healthy DORA while delivery is actually stuck; people will “fix the rule that stopped paying rent” against garbage numbers.
3. **B2B/B2C defaults create false confidence and wrong gates.** A B2B internal admin UI card gets multi-tenancy/audit Done-when noise; a B2C backend mutation card skips auditability because Profile says b2c. Agents checkbox the profile section instead of the real risk surface (API breakage, data loss, PII, money). Profile becomes a costume, not a contract.

## What to cut
- **Full four-key DORA framing in the shipped file** until at least two metrics are scripted and validated. Shipping “never by hand” + four definitions with zero implementation is aspirational ritual with a metric costume. Keep one sentence: “We will measure delivery from git + runs/; definitions live with status.sh when data exists.”
- **“Strongest delivery correlate in the DORA research”** — name-dropping research doesn’t enforce anything and invites cargo-cult DORA cosplay. One line on small batches is enough.
- **Recovery via `updated:` deltas** — card mtime/touch noise is not recovery time; it will measure “someone edited the file,” not “outage fixed.” Cut until a real blocked→resolved event exists in runs/.
- **B2C “analytics events are named in the card”** and **B2B “every data mutation is auditable”** as unconditional defaults unless you already have a lint/check that fails without them. As prose-only Done-when suggestions they will be ignored or copy-pasted empty.
- **“A falling trend is a workspace bug”** — punitive, unfalsifiable without stable metrics, and will produce blame-seeking when the metric itself is broken.

## What's missing
- **Who enforces what, on which hook.** Card return for vague Done-when, night test-first, profile Done-when injects — runner vs human vs status.sh. Without hook points, week-one agents ignore the contract.
- **Definition of “one worktree session” and “card too big.”** No size signal (files touched, green_cmd duration, failed attempts). Agents will still claim mega-cards and half-finish them.
- **Merge discipline for this workspace.** Small batches die if the human merges weekly piles; no note on PR/merge policy, squash vs merge commits, or requiring card id in commit/PR title (needed for any later DORA).
- **Conflict with existing templates.** How PLAYBOOK relates to green_cmd, night runner, card schema, PROJECT.md, DECISIONS.md — one paragraph on precedence when they disagree.
- **Escape hatch for non-product work.** Infra, research spikes, docs-only, one-off migrations: test-first and profile checklists will either block legitimate work or get waived until waivers are the norm.
- **Blameless blocked note schema.** “One paragraph in runs/” without a fixed field/filename means free text that status.sh cannot aggregate for change-failure or recovery.

## Steelman the opposite
Don’t ship PLAYBOOK at all yet: the filter (“enforceable / measurable / one line on a card”) is the real product, and this draft is mostly unenforced prose that reintroduces methodology under a thinner brand. Small batches and checkable Done-when already belong on the card template and runner; profile rules belong as optional Done-when snippets keyed by risk tags (`api`, `schema`, `ui`, `money`), not a B2B/B2C essay; DORA without scripts is the joyci end-block class of failure. A shorter path is three card-template lines + one runner check + defer the doc until status.sh can shame noncompliance with numbers. A standalone Tier-1 PLAYBOOK risks becoming a status symbol for “serious” projects while changing zero behavior.

## Answers to the draft's open questions
1. **Axis:** Prefer **risk tags over market persona**. `b2b|b2c|both` is a weak predictor of what breaks; `api-contract`, `schema/tenant`, `pii/money`, `ui/a11y`, `flagged-rollout` map to Done-when lines agents can actually write. If you must keep one profile field for humans, keep `b2b|b2c|both` as soft defaults only. The single checklist item that bites most often and is missing: **rollback / forward-fix path named on the card** (how green gets undone or patched without a week-long branch) — more universal than tenancy or analytics naming.

2. **Test-first for night cards:** **Hard requirement if night-runnable is a first-class mode.** Convention-only will be skipped under schedule pressure the same way the end block was. Implement as: runner refuses claim/start when night flag is set and Done-when lacks an explicit failing-test (or `green_cmd`-related) first item. Soften only for explicitly tagged `spike`/`docs` cards with a human override field, not silent convention.

3. **DORA-lite deferral:** **Defer the four-key dashboard; ship one crude signal now if cheap.** Merges/week alone is nearly worthless without card linkage. Worth doing *now* only if you already have reliable card id → outcome in runs/: e.g. **blocked-after-green count / completed cards per week**. Otherwise defer all of §3 implementation and strip the four definitions from Tier-1 text so the contract doesn’t promise what the workspace can’t measure.

4. **Cargo cult in this draft:** (a) full DORA-lite section with no scripts; (b) “falling trend = workspace bug”; (c) recovery from `updated:`; (d) research authority appeal for small batches; (e) profile essays that aren’t injected or linted into cards; (f) “stranger can verdict Done-when” without a linter or second-agent check — that standard dies like the end block unless a machine fails the card. The durable core is: small cards, checkable Done-when, close ADR status, blameless blocked notes with a fixed shape.

5. **Tier:** **Tier 0 defaults (short), Tier 1 can lengthen profile/examples.** Everyone benefits from small batches + checkable Done-when + close-the-loop on decisions/blocks; B2B/B2C (or risk-tag) checklists and DORA language are optional depth. Making PLAYBOOK Tier-1-only guarantees the projects that most need batch discipline never see it, while long-run projects get a longer unread file. Prefer a tight Tier 0 PLAYBOOK and move profile matrices to a pointer or Tier 1 addendum.
