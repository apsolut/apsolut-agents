<!-- apsolut-agents: tier=1 kind=doc -->
# PLAYBOOK — what makes projects land (Tier 1)

_Every rule here is enforced by a script, checkable on a card, or deliberately absent.
Prose-only process died in the field (a mandatory session block was used 0 of 52 times
in the reference run); this file refuses to grow anything of that kind. Reviewed blind
by three models; the DORA metrics section they killed returns only when `status.sh`
actually computes it from real night data._

## 1. Small batches, always

A card an agent can't finish in one worktree session is two cards. Branches live
hours-to-days. Merges are small and boring — that's what keeps morning review a
5-minute job and reverts one-card-sized.

## 2. The card is a contract

"Done when" items are **checkable statements** — written so a machine or a stranger
can verdict them without asking the author. Night-runnable cards are **test-first,
enforced**: the runner refuses a card whose Done-when mentions no test (set
`spike: true` in the frontmatter to waive it for research/docs cards — the waiver is
visible, not silent). A refused card goes `blocked` with the reason in the card, not
silently skipped.

## 3. Delivery is measured from git, or not at all

No hand-reported metrics, and no promised ones either: delivery numbers (lead time,
throughput, failure rate) appear in `status.sh`/night reports only once they are
computed from real run data. Until then this file makes no metric claims.

## 4. Risk tags, not business-model essays

Declare what a card can break — `risk: [api-contract, schema, pii, money, ui]` — and
add the matching Done-when lines. The two that bite most in practice:

| tag | non-negotiable Done-when additions |
|---|---|
| `api-contract` | backward-compat verified (or break = human gate); **rollback / forward-fix path named on the card** |
| `schema` | migration is backward-compatible with running code; tenant/user isolation stated |
| `pii` / `money` | mutation is auditable (who/when/what); human gate per PROJECT.md |
| `ui` | accessibility item; behind a feature flag if risky (flag removal is its own card) |

Tags are card-level and technical — whether the product is B2B or B2C is your
business, not the card's.

## 5. Close the loops

Decisions carry `Status:` and get updated in the implementing session. Blocked night
cards get a fixed-shape note in their runs/ output — three lines, blameless:
`Attempted:` / `Failed because:` / `Would unblock:`. Fixed shape so scripts can
aggregate it later; blameless so it gets written at all.

## 6. Deliberately absent

Sprints, points, standups, estimation, RACI, research citations. The log is the
standup, the board is the status meeting, git is the burndown. If a practice needs a
calendar and social pressure to survive, it does not belong in this workspace.
