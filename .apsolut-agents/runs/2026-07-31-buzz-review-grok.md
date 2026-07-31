<!-- apsolut-agents: tier=1 kind=instance -->
# 2026-07-31 — buzz assimilation, adversarially reviewed by Grok (2 rounds)

**Shape:** Claude imported five prose rules from [block/buzz](https://github.com/block/buzz)
(D-006 draft 1); Grok blind-reviewed the diff with an attack brief; Claude pre-registered
its own self-critique before reading Grok, rebutted, proposed a compromise package;
Grok verdicted the package. 2 rounds, grok-4.5-build, ~$0.22 total, ~8 min wall.

## Round 1 (Grok, adversarial) — verdicts on the original import

| # | Change | Verdict | Core argument |
|---|---|---|---|
| 1 | PROTOCOL §1 no-bare-acks | CUT | ack-loops are a chat failure; collides with mandatory end token |
| 2 | PROTOCOL §2 evict-on-ship | REWRITE | restates existing delete rule with more words |
| 3 | PROTOCOL §6 verification | REWRITE | "full suite" fights card scoping; HEAD belongs in scripts, not prose |
| 4 | DELEGATION facts/self-review | CUT | delegate.sh already surfaces facts; §7 already distrusts delegate verdicts |
| 5 | NIGHTSHIFT card bullet | CUT | fifth way to say "write a good card" |
| 6 | reference §12 | REWRITE | assimilation inventory duplicates D-006; persona brochure |

Grok's constructive core: **enforce-or-omit on every import** — bake `git rev-parse HEAD`
into recorded green output mechanically; import zero chat-era social rules.

## Round 2 — convergence

Claude conceded: mechanize HEAD (S1), cut "full suite", cut in-doc buzz citations,
shrink reference §12, compress everything. Claude rebutted: (R1) "zero prose until a
local scar" proves too much — it would delete "Committed ≠ done" and "HOLD stays human";
norms that define done/green/honest are not the skippable ceremony D-003 pruned.
(R2) hand-written log guesses/ack-noise are architecture-independent even if reply
loops aren't. (R3) never-self-review survives as a preference with solo-roster fallback.

Grok round 2: **ACCEPT C1, C2, C3, C4a, C4b, C6, S1** — including two explicit
concessions ("I overclaimed 'architecture cannot have this'"; "'must always
cross-review' was the bad form, not 'prefer fresh eyes'"). **STILL-WRONG C5**: don't
add a sibling bullet restating Goal/Done-when; fold only the invented-constraints
clause into the existing bullet. Claude accepted.

## Shipped (the converged package)

- **S1 (mechanism):** `delegate.sh` + `runner.sh` stamp `green_cmd @ <HEAD>` into
  `$OUT` immediately before running the check — every recorded green/red is bound to
  its exact commit. (`sh -n` clean on both.)
- **Norms (terse, citation-free):** PROTOCOL §1 asymmetric publish + no ack-only
  mid-session entries (end token explicitly carved out); §2 evict-on-ship as one
  clause; §6 green-is-a-claim-about-a-commit + scoped negatives; DELEGATION §2 facts
  off the board, timers are backstops; §5 prefer fresh eyes for judgement verdicts
  (solo fallback); NIGHTSHIFT invented-constraints clause folded into the existing
  Goal/Done-when bullet.
- **reference §12:** one-paragraph prior-art pointer; D-006 owns the record.

## Explicit rejects (with reasons — see D-006)

Relay/keypair platform; "full suite, never scoped"; hard cross-review duty; long
citations in doc bodies; persona packs; charter frontmatter parsed by scripts
(revisit-if-duplication-bites); "zero prose ever" (R1).

Raw transcripts: scratchpad `grok-round1.json` / `grok-round2.json` (session-local,
not preserved); briefs and pre-registration were session artifacts.
