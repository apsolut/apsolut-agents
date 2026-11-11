<!-- apsolut-agents: tier=2 kind=doc -->
# prompts/ — the role prompts Night Shift renders (Tier 2)

`runner.sh` fills `{{KEY}}` placeholders from files and passes the result to the
role's CLI. Lines that carry the `apsolut-agents: tier=` marker are stripped. These
files are `kind=doc`, so `upgrade.sh` overwrites them. To change a rule for one
project, change the card, `GOAL.md` or `PROJECT.md` (agents read all three), not the
prompt.

| file | role | runs | writes (only) |
|---|---|---|---|
| `worker.md` | implements one card | in the card's worktree | commits on its branch + `runs/handoffs/<id>-attempt<n>.md` |
| `verifier.md` | proves or refutes the change, read-only. Run by `verifier_agent`, or by `risk_verifier_agent` for a card carrying a `risk_tags` tag | in the card's worktree, after green | `runs/handoffs/<id>-verify<n>.md` |
| `advisor.md` | diagnoses a failed attempt, read-only | in the card's worktree, before a retry | `runs/handoffs/<id>-advice<n>.md` |
| `planner.md` | writes the next cards toward `GOAL.md`, each with a `check:` and honest `risk:` tags | in the night worktree, when the board is dry and the predicate is red | `runs/plan-<date>-r<n>/<id>.md` or `STUCK.md` |
| `review.md` | morning audit of the trail, read-only | at night end | `runs/night-<date>-attention.md` |

Roles write their output inside their cwd, under `.apsolut-out/` (git-excluded),
because a CLI sandboxed to its worktree cannot write anywhere else. The runner
collects it into the `runs/` paths above. The runner enforces "read-only" and "writes only": a role that changes the worktree
gets reset and its output discarded, and a role that touches `HEARTBEAT.md`,
`GOAL.md`, `prompts/` or `scripts/` raises the Andon.

## Where the rules come from

Distilled from the Cursor plugin set (github.com/cursor/plugins, MIT). Each rule was
kept only where a script here can enforce it or a prompt can carry it in one line:

- **pstack** (poteto): the overnight contract. A checkable finish predicate instead
  of a duration. A plateau means pivot. The predicate never relaxes. Prove it works on
  the real artifact. Fix root causes. Attack the premise after two failed fixes.
  Never block on the human. Sequence verifiable units. A decision trail with a
  cross-model audit and an Attention section (show-me-your-work). A verifier that did
  not write the code (autopilot, shipping).
- **orchestrate**: structured handoffs as the only channel up. Synthetic failure
  handoffs with a failure mode. The verification ladder (`live / test / typecheck /
  blocked / failed`), and "blocked is not a weaker pass". The Andon. A planner that
  writes tasks and never codes.
- **advisor**: a second model at the "stuck" and "before done" checkpoints. It is
  read-only, gets a full briefing, and its verdict is advice, not authority.
- **thermos** and **dyl-stack**: the review rubric. Report only code the diff
  changed. Never over-report severity. Watch for the 1000-line file and spaghetti
  conditionals. `Root cause: X because Y` and the symptom-patch list. One
  🟢/🟡/🔴 call.
- **agent-compatibility**: prove the start and validation paths in a cold, pristine
  checkout. `doctor.sh` does this for `green_cmd` and `done_cmd`.
- **pr-review-canvas**: put core logic first and boilerplate last when presenting a
  change to the reviewer (the Attention section's ordering).
