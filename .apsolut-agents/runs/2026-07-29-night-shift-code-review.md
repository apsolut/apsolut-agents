# Night Shift v0 — code verification round (2026-07-29)

Claude implementation reviewed blind by AGY/Gemini + Grok. Adopted: 5xx=backoff + no attempt burn; full claim rewrite (status+claimed+pid); dead-pid recovery w/ 5m grace (was: pid-0 bug + 90m); CRLF strip in fm_get/cfg; fm_set adds missing keys; midnight-safe stop via awk int + morning re-arm; lane singleton + EXIT trap; reset to pre-attempt SHA on fail; branch assert; numeric sanitization (budget/cost/spend, atomic write); green_cmd sentinel refusal; done-only deps; exit codes (breaker=2, budget=3).

Rejected: owner-reset-to-any on recovery (PRD: reassign is morning-human-only); full manual process-tree kill rewrite (GNU timeout empirically kills children in Git Bash — v1 hardening item); fallback-cost only on success (conservative budget bias is intentional); runner delegating ready-computation to status.sh (duplication accepted for v0).

---

## Review: AGY (Gemini)
# Adversarial Code Review: Night Shift v0

---

## 1. PRD Violations

### [HIGH] HTTP 5xx Server Errors Trip Circuit Breaker
* **Snippet**: 
  ```sh
  if grep -qiE '(^|[^0-9])429([^0-9]|$)|rate.?limit|quota exceeded|overloaded' "$OUT"; then
  ```
* **Failure Scenario**: The PRD explicitly mandates: *"HTTP 429/5xx from the CLI must pause the lane with backoff, not trip the failure circuit breaker."* The current regex only checks for 429/rate-limit errors. When an LLM provider returns `500 Internal Server Error` or `503 Service Unavailable`, `runner.sh` treats it as a card execution failure, increments `FAILS`, and trips the circuit breaker after 3 occurrences.
* **Fix**: `if grep -qiE '(^|[^0-9])(429|500|502|503|504)([^0-9]|$)|rate.?limit|quota exceeded|overloaded|internal server error' "$OUT"; then`

---

### [HIGH] Recovered Stale Claims Remain Locked to Original Agent
* **Snippet**: 
  ```sh
  rm -rf "$c"
  [ -f "$WS/work/$id.md" ] && fm_set "$WS/work/$id.md" status waiting
  ```
* **Failure Scenario**: PRD Claim Protocol Step 3 states: *"stale-claim recovery... remove claim dir, card -> waiting, log it."* However, `fm_set` only resets `status` to `waiting` while leaving `owner: <agent>` intact in the card frontmatter. In `pick_ready()`, other runners check `case "$o" in "$AGENT"|any|"<agent>"|"")`. If `claude` crashes, `grok` will forever ignore the recovered card because `owner` remains set to `claude`.
* **Fix**: `[ -f "$WS/work/$id.md" ] && fm_set "$WS/work/$id.md" status waiting && fm_set "$WS/work/$id.md" owner any`

---

### [MED] Claim Protocol Omits `claimed` ISO Timestamp & Immediate `status: writing`
* **Snippet**: 
  ```sh
  mkdir "$WS/claims/$ID" 2>/dev/null || { sleep 5; continue; }
  echo $$ > "$WS/claims/$ID/pid"
  CARD="$WS/work/$ID.md"
  fm_set "$CARD" owner "$AGENT"; fm_set "$CARD" updated "$DATE"
  ```
* **Failure Scenario**: PRD Claim Protocol Step 2 specifies: *"Winner immediately rewrites card frontmatter: owner, status: writing, claimed: <iso-time> pid:<pid>"*. The implementation omits `claimed` entirely and delays setting `status: writing` until *after* checking whether a worktree exists. If `worktree.sh spawn` hangs or fails, the card stays in `status: waiting` while owned by the agent.
* **Fix**: `fm_set "$CARD" owner "$AGENT"; fm_set "$CARD" status writing; fm_set "$CARD" claimed "$(date -u +%Y-%m-%dT%H:%M:%SZ) pid:$$"`

---

### [MED] Provider Backoff Leaves Dirty Worktree State
* **Snippet**: 
  ```sh
  if grep -qiE ... "$OUT"; then
    tick "provider backoff on $ID (not a failure)"; rm -rf "$WS/claims/$ID"
    fm_set "$CARD" status waiting; sleep 900; continue
  fi
  ```
* **Failure Scenario**: PRD Cut #4 requires mandatory cleanup (`git reset --hard` in worktree) upon card exit/failure. If an agent modifies files and then hits an API rate limit mid-execution, `runner.sh` releases the claim and sets status back to `waiting` without resetting the worktree. The next attempt on that card will inherit uncommitted dirty edits from the failed rate-limited run.
* **Fix**: `git -C "$WT" reset --hard -q 2>/dev/null; git -C "$WT" clean -fdq 2>/dev/null; rm -rf "$WS/claims/$ID"; fm_set "$CARD" status waiting`

---

## 2. Shell, POSIX & Windows (Git Bash) Bugs

### [HIGH] `kill -0 0` Checks Runner's Own Process Group on Missing PID
* **Snippet**: 
  ```sh
  pid=$(cat "$c/pid" 2>/dev/null || echo 0)
  ...
  if ! kill -0 "$pid" 2>/dev/null && [ "$age" -ge "$STALE_MIN" ]; then
  ```
* **Failure Scenario**: If a runner crashes after `mkdir claims/$ID` but before writing `pid`, `cat "$c/pid"` fails and defaults `pid=0`. In POSIX shell / Git Bash, `kill -0 0` sends signal 0 to the **current process group**, which always succeeds (returns 0). Thus `! kill -0 0` evaluates to FALSE, and orphaned claims with missing/empty PID files will **never** be recovered.
* **Fix**: `pid=$(cat "$c/pid" 2>/dev/null || echo ""); [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && [ "$age" -ge "$STALE_MIN" ]`

---

### [HIGH] Windows CRLF (`\r`) Line Endings Corrupt Frontmatter Values
* **Snippet**: 
  ```sh
  fm_get() { awk -v k="$2" 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit}
    f&&index($0,k":")==1{sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");print;exit}' "$1"; }
  ```
* **Failure Scenario**: On Windows (Git-Bash/NTFS), card files saved with CRLF line endings cause `fm_get` to leave a trailing `\r` on extracted values (`o="claude\r"`). In `pick_ready()`, `case "$o" in "$AGENT"|...)` fails to match `"claude"` against `"claude\r"`. The runner silently ignores all ready cards.
* **Fix**: Insert `sub(/\r$/,"");` before printing in `fm_get`: `sub("^" k ":[ \t]*","");sub("[ \t]*#.*$","");sub(/\r$/,"");print;exit`

---

### [HIGH] `sed 's/^0*//'` Strips All Zeros at Midnight & Breaks `STOP` Check
* **Snippet**: 
  ```sh
  NOW=$(date +%H%M | sed 's/^0*//'); S=$(echo "$STOP" | sed 's/^0*//')
  [ "${NOW:-0}" -ge "${S:-700}" ] && [ "${NOW:-0}" -lt 1200 ] && finish "stop_time"
  ```
* **Failure Scenario**:
  1. At midnight (`00:00`), `date +%H%M` is `0000`. `sed 's/^0*//'` strips all characters, producing an empty string `""`. `${NOW:-0}` evaluates to `0`.
  2. At `00:15`, `sed` converts `0015` to `15`. `15 -ge 700` evaluates to FALSE. If a runner starts at 23:00 and runs past midnight, it will **not** stop at `07:00` because `00:00–06:59` evaluates as `< 700`.
* **Fix**: Use string comparison with 4-digit zero-padded numbers: `NOW=$(date +%H%M); [ "$NOW" -ge "$STOP" ] && [ "$NOW" -lt "1200" ] && finish "stop_time"`

---

### [HIGH] `fm_set` Silently Fails to Add Missing Frontmatter Keys
* **Snippet**: 
  ```sh
  fm_set() { awk -v k="$2" -v v="$3" 'NR==1&&$0=="---"{f=1;print;next}
    f&&$0=="---"{f=0;print;next} f&&index($0,k":")==1{print k": "v;next}{print}' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
  ```
* **Failure Scenario**: `fm_set` only replaces lines where `index($0, k":") == 1`. If a card is missing a field in its YAML frontmatter (e.g. `status:` or `owner:`), `fm_set` does not insert it. The temp file is written without the new key, and updates silently drop.
* **Fix**: Track replacement with a flag in AWK and print `k": "v` before closing `---` if key was not found.

---

### [HIGH] Git-Bash `timeout` Leaves Windows LLM Processes Running
* **Snippet**: 
  ```sh
  ( cd "$WT" && timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" runner "$PROMPT" ) > "$OUT" 2>&1
  ```
* **Failure Scenario**: On Git-Bash-on-Windows, `timeout` sends POSIX signals to the wrapper `sh`, but MSYS2 signal translation does not kill native Win32 child process trees (`claude.exe`, `node.exe`). When timed out, `sh` exits but the LLM process continues running in the background consuming API tokens.
* **Fix**: Kill child process trees on failure: `( cd "$WT" && timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" runner "$PROMPT" ) > "$OUT" 2>&1 || { taskkill //F //T //PID $$ 2>/dev/null || true; }`

---

### [MED] Large Prompt String Exceeds Windows Command Line Limits
* **Snippet**: 
  ```sh
  PROMPT="... $(cat "$CARD")"
  ( cd "$WT" && timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" runner "$PROMPT" )
  ```
* **Failure Scenario**: Passing the full text of `$CARD` as a command-line positional argument (`$1`) to `sh -c` easily exceeds the Windows `CreateProcess` 32,767 character limit on large task cards, causing `sh` to crash with `Argument list too long` (E2BIG).
* **Fix**: Pass prompt via standard input or a temporary file instead of a command argument: `echo "$PROMPT" | sh -c "$CMD -"`

---

## 3. Concrete Failure Scenarios

### 1. Card Missing `id:` Frontmatter Field
* **Line**: `ID=$(pick_ready || true)` -> `mkdir "$WS/claims/$ID"`
* **Failure Scenario**: A human creates a card without an `id:` key. `fm_get "$f" id` returns an empty string. `pick_ready` outputs `""`. `ID` becomes empty. `runner.sh` executes `mkdir "$WS/claims/"`, which fails or corrupts the claim directory root, causing an unhandled error loop under `set -e`.
* **One-line Fix**: `[ -n "$ID" ] || { tick "idle — no ready cards"; sleep "$POLL"; continue; }`

---

### 2. Two Runners Started with Same Agent Name by Mistake
* **Line**: `add_spend()` and `finish()`
* **Failure Scenario**: Two `runner.sh claude` instances run concurrently. Both claim separate cards successfully via `mkdir claims/$ID`. However, both write non-atomically to `$SPENDF` (`awk ... > "$SPENDF"`), corrupting the spend tally. On exit, both overwrite `$WS/runs/night-$DATE.md` simultaneously, truncating morning report data.
* **One-line Fix**: Include PID in temp report file and write spend atomically: `add_spend() { awk "BEGIN{printf \"%.2f\", $(spent) + ${1:-0}}" > "$SPENDF.tmp" && mv "$SPENDF.tmp" "$SPENDF"; }`

---

### 3. Non-Numeric `budget:` Frontmatter Breaks Arithmetic
* **Line**: `CB=$(fm_get "$CARD" budget); case "$CB" in ''|null) CB=$TIMEOUT_MIN;; esac` -> `$(( CB * 60 ))`
* **Failure Scenario**: A card contains `budget: 30m` or `budget: 30 minutes`. `CB` is extracted as `30m`. The shell evaluates `$(( 30m * 60 ))`, triggering a fatal arithmetic syntax error in `sh` and crashing the runner.
* **One-line Fix**: `CB=$(echo "$CB" | tr -dc '0-9'); CB=${CB:-$TIMEOUT_MIN}`

---

### 4. Runner Dies Mid-Card Execution
* **Line**: Boot recovery loop
* **Failure Scenario**: Power cut or `kill -9` terminates `runner.sh` while executing `CMD`. The claim folder `claims/$ID` remains on disk. On restart, boot recovery checks `age=$(( ... / 60 ))`. If restarted within 90 minutes (`STALE_MIN`), boot recovery ignores the dead process and leaves the card locked until 90 minutes pass.
* **One-line Fix**: Remove stale claims immediately if PID is dead regardless of age: `if ! kill -0 "$pid" 2>/dev/null; then rm -rf "$c"; ...; fi`

---

## Top 3 Priority Fixes to Make First

1. **Fix Stale Claim Recovery PID Zero Bug & Owner Lockout** (`runner.sh:40-47`):
   Prevent dead claims with missing PIDs from permanently locking cards, and ensure recovered cards clear `owner` so other agents can work on them.
2. **Fix CRLF (`\r`) Frontmatter Stripping** (`runner.sh:22-23`):
   Prevent Git-Bash on Windows from failing all string comparisons and silently skipping every card on disk.
3. **Fix Midnight `STOP` Window Calculation** (`runner.sh:76`):
   Replace fragile `sed 's/^0*//'` logic with standard 4-digit zero-padded string comparison so the runner stops reliably at `07:00` across midnight.

---

## Review: Grok
# Adversarial review: Night Shift v0 `runner.sh` vs PRD

## (1) PRD decision violations

### HIGH — Claim protocol incomplete (missing `status` / `claimed` rewrite)
**Snippet:** after `mkdir "$WS/claims/$ID"`:
```sh
echo $$ > "$WS/claims/$ID/pid"
fm_set "$CARD" owner "$AGENT"; fm_set "$CARD" updated "$DATE"
```
**PRD:** Winner immediately rewrites frontmatter: `owner`, `status: writing`, `claimed: <iso-time> pid:<pid>`.  
**Scenario:** Crash between `mkdir` and the later `fm_set … status writing` (or if spawn path never sets it) leaves a claim dir with `waiting` card and no `claimed` trail; another runner or human cannot tell who owns it.  
**Fix:** Immediately after claim: `fm_set status writing` + `fm_set claimed "$(date -Iseconds) pid:$$"` (and keep `owner`).

### HIGH — Stale-claim recovery uses wrong policy name + wrong predicate vs PRD
**Snippet:**
```sh
STALE_MIN=$(cfg stale_claim_minutes); STALE_MIN=${STALE_MIN:-90}
…
if ! kill -0 "$pid" 2>/dev/null && [ "$age" -ge "$STALE_MIN" ]; then
```
**PRD:** `stall_claim_minutes` AND pid dead → clear claim, card → `waiting`. HEARTBEAT template uses `stale_claim_minutes: 90` (also diverges from PRD name).  
**Scenario:** Operator fills PRD key `stall_claim_minutes` → runner ignores it and defaults to 90; dead PID claim younger than 90m is **not** recovered → permanent stuck card until timeout.  
**Fix:** Read `stall_claim_minutes` (alias both names) and recover on **dead PID** regardless of age, or age-only as secondary; never require both for long stalls of a live-looking but dead PID beyond a short grace.

### HIGH — Provider 5xx / HTTP errors not distinguished from card failures
**Snippet:** only 429/rate-limit grep:
```sh
if grep -qiE '(^|[^0-9])429…|rate.?limit|quota exceeded|overloaded' "$OUT"; then
```
**PRD:** “HTTP 429/5xx from the CLI must pause the lane with backoff, not trip the failure circuit breaker.”  
**Scenario:** Transient 502/503 from CLI → treated as red, `FAILS++`, after 3 trips breaker ends the night while cards are fine.  
**Fix:** Extend provider pattern to `5[0-9]{2}`, `server error`, etc., and `continue` without incrementing `FAILS` (same as 429 path).

### HIGH — Kill is not terminal process-tree cleanup as specified
**Snippet:**
```sh
( cd "$WT" && timeout -k 30 $(( CB * 60 )) sh -c "$CMD \"\$1\"" runner "$PROMPT" ) > "$OUT" 2>&1
…
# only removes index.lock; no kill tree
```
**PRD:** Timeout → kill process tree → mandatory cleanup (`git reset --hard`, clear orphan `.git/*.lock`) → card waiting/blocked.  
**Scenario:** On Git Bash/Windows, `timeout` may leave orphaned agent/node children holding the worktree; next attempt races on dirty index/locks.  
**Fix:** On timeout/`RC` 124/137, `pkill -P` / kill process group (`set -m` + `kill -- -$$`), then always `reset --hard` + clear `*.lock` before reclaim.

### MED — v0 report / “Green per PROJECT.md” / status.sh ready path misaligned
**Snippet:** `GREEN=$(cfg green_cmd)` and report always written by `finish()`; no reference to PROJECT.md.  
**PRD v0:** Green per PROJECT.md decides done; `status.sh` computes ready; report is mainly a **v1** gate item, but v0 still needs green definition honesty.  
**Scenario:** Project documents green in PROJECT.md; HEARTBEAT default is `echo … && false` → every card “fails” overnight while humans thought PROJECT.md was source of truth.  
**Fix:** Document/require green_cmd to match PROJECT.md (or read PROJECT.md key); refuse start if green_cmd still default/false stub.

### MED — `after: []` / ready computation lives in runner, not `status.sh`
**Snippet:** `deps_met` + `pick_ready` inline; only calls `status.sh` at end of `finish`.  
**PRD:** “`after: []` dependency edges on cards; `status.sh` computes `ready`.”  
**Scenario:** Human runs `status.sh` and sees different ready set than runner (duplicated logic drifts).  
**Fix:** Have runner invoke `status.sh --ready-for $AGENT` (or shared lib) instead of private `pick_ready`.

### MED — Config key drift from HEARTBEAT.md policy block in PRD
**Snippet:** `night_budget_usd`, `stale_claim_minutes`, `card_timeout_minutes`, `idle_poll_seconds` vs PRD’s `night_budget`, `stall_claim_minutes`, `tick_interval`, etc.  
**Scenario:** Someone edits HEARTBEAT from PRD snippet only → runner defaults silently (`BUDGET=25`, etc.) and “budget respected” gate is false confidence.  
**Fix:** Accept PRD aliases (`night_budget` / `night_budget_usd`, `stall_*` / `stale_*`) and fail loud if neither present when required.

### LOW — v0 ships full night report as if v1, overwriting mid-night
**Snippet:** `finish() { … } > "$REPORT"`  
**PRD:** Idempotent night report is a **v1** deliverable; v0 is supervised single-lane. Overwrite is OK-ish for supervised, but not idempotent on restart.  
**Scenario:** Restart after partial night → previous report content lost; attempts file remains so “idempotent” is partial.  
**Fix:** Append session sections or write `night-$DATE-$AGENT.md` / merge by card id (v1 readiness).

### LOW — No file-overlap / `files:` enforcement (OK for v0, easy to misread as ready)
Not a v0 requirement (v2), but runner never mentions tolerance flags for later. No defect for v0 gate if left alone.

---

## (2) Real shell / Git-Bash / POSIX bugs

### HIGH — Non-POSIX `timeout` and `date -r` (macOS / minimal busybox / Git Bash variance)
**Snippets:**
```sh
timeout -k 30 $(( CB * 60 )) …
age=$(( ( $(date +%s) - $(date -r "$c" +%s 2>/dev/null || date +%s) ) / 60 ))
```
**Scenario:** Git Bash often lacks GNU `timeout`; age falls back to `date +%s` → age ≈ 0 → **never** recovers stale claims (`age -ge STALE_MIN` false forever while PID dead).  
**Fix:** Use portable timer (`perl`/`python` sleep+kill, or busybox-compatible) and claim mtime via `stat`/`find -printf` with fallbacks; on age failure treat as stale if PID dead.

### HIGH — `fm_set` / claim rewrite not atomic; TOCTOU between pick and claim
**Snippets:**
```sh
ID=$(pick_ready || true)
…
mkdir "$WS/claims/$ID" 2>/dev/null || { sleep 5; continue; }
…
fm_set … > "$1.tmp" && mv "$1.tmp" "$1"
```
**Scenario:** Two runners (same agent, mistake): both see `waiting`, one wins `mkdir`, other sleeps 5 and retries forever while winner crashes before `status writing` — or both interleave `fm_set` on same card (`*.tmp` clobber). On NTFS, `mv` over file is usually OK; two concurrent `fm_set` still lose updates.  
**Fix:** Only winner rewrites; use claim dir as exclusive writer (write card under lock file inside `claims/$ID/`); loser must re-`pick_ready`.

### HIGH — Prompt / `CMD` injection via unquoted expansion
**Snippet:**
```sh
( cd "$WT" && timeout … sh -c "$CMD \"\$1\"" runner "$PROMPT" )
```
**Scenario:** Card body or path with `"` / `$` / backticks ends up in `PROMPT` (arg OK) but `CMD` from HEARTBEAT is expanded by outer shell before `sh -c` if mis-edited; more critically `sh -c "$CMD \"\$1\""` still subjects `$CMD` to word-splitting risks if it contains poorly quoted multi-arg forms. Worktree path with spaces is OK in `$WT` for `cd`; agent binary args depend on `cmd_*` being carefully written.  
**Fix:** Prefer `eval`-free: store argv as shell function or run `timeout … env PROMPT=… $CMD` with array emulation (`set --` + `"$@"`) documented for each lane.

### HIGH — `add_spend` / arithmetic with empty or non-numeric cost
**Snippets:**
```sh
spent() { cat "$SPENDF" 2>/dev/null || echo 0; }
add_spend() { awk "BEGIN{printf \"%.2f\", $(spent) + $1}" > "$SPENDF"; }
…
add_spend "${COST:-$FALLBACK_COST}"
```
**Scenario:** Corrupted `.spend-$DATE` or `COST` like `1.2.3` → awk/shell syntax error under `set -e` → **runner aborts mid-card** with claim dir left and status stuck `writing`.  
**Fix:** Validate numeric with `case`/`awk`; default bad values to fallback; write spend via temp+mv.

### MED — Spend / attempts files have no locking (race on dual runners)
**Snippet:** `echo "$N" > "$WS/runs/.attempts-$ID"`; `add_spend` rewrite.  
**Scenario:** Two runners same agent: double attempts, double spend → false breaker/budget stop.  
**Fix:** Serialize via claim (already exclusive per card) + atomic spend update with flock or single-writer process file.

### MED — `kill -0 "$pid"` on Windows/Git Bash is unreliable for “same machine” PIDs
**Snippet:** boot recovery `kill -0 "$pid"`.  
**Scenario:** Stale PID reused by unrelated process → claim never cleared; or Git Bash PID namespace ≠ agent PID → false “alive”.  
**Fix:** Store `pid` + start time + cmdline hash in claim dir; require match before treating alive.

### MED — Leading-zero strip on time is fragile at midnight / all-zero
**Snippet:**
```sh
NOW=$(date +%H%M | sed 's/^0*//'); S=$(echo "$STOP" | sed 's/^0*//')
[ "${NOW:-0}" -ge "${S:-700}" ] && [ "${NOW:-0}" -lt 1200 ] && finish "stop_time"
```
**Scenario:** At `00:00`, `NOW` becomes empty → `${NOW:-0}` = 0; stop check false (OK). At `00:05` after a run started previous evening past 07:00? If someone starts at 08:00, `NOW=800`, `S=700`, `800>=700` and `800<1200` → **immediate finish** (intended morning stop). At `07:00` works. **Bug:** `09:00` → stops (good for overnight). **Bug:** afternoon supervised run at 15:00 → `1500` not `< 1200` so **never** hits stop_time by clock (only budget/breaker) — may be OK for supervised. **Worse:** `NOW` after strip for `00:00`–`00:09` becomes `0`–`9` not `0000`–`0009` comparisons inconsistently; `STOP=07:00` → `S=700`; fine. Empty sed on `0000` → empty → 0.  
**Fix:** Compare as strings `HHMM` zero-padded without stripping, or minutes-since-midnight integers without leading-zero octal risk (`$((10#$NOW))` is bash-only).

### MED — Octal risk if someone uses bare arithmetic on zero-padded times elsewhere
Not used with `10#` here; `sed` strip avoids octal in `[` numeric tests — good. Keep it.

### MED — `fm_get` / `fm_set` only match keys at line start after `key:`; missing frontmatter or missing `id`/`status`
**Snippet:** `fm_get "$f" id`; `pick_ready` uses status/owner.  
**Scenario:** Card missing `---` or `id:` → empty `ID`, `mkdir claims/` odd path, or claim `claims/` with empty basename; missing `status` → never picked or wrong.  
**Fix:** Validate required keys after claim; skip and tick `malformed $f` if id/status missing.

### MED — Salvage commit can mask failed green and leave dirty history
```sh
if [ -n "$(git -C "$WT" status --porcelain | …)" ]; then
  git commit … || true
fi
if [ "$RC" -eq 0 ] && green; then review; else reset --hard
```
**Scenario:** RC≠0 path does reset (good); RC=0 green fails after salvage commit — commits remain (good for forensics) but red path `reset --hard` **drops** salvage if green fails after commit… actually order is: salvage commit **then** green; if green fails, **reset --hard** deletes salvage commits if they were new? `reset --hard` to HEAD keeps commits; only uncommitted cleaned. Wait: salvage **commits**, then green fails → `reset --hard` keeps those commits. So failed attempts leave commits on branch — next attempt continues dirty history (not clean worktree of PRD “reset hard”).  
**PRD:** cleanup `git reset --hard` on kill/fail — usually means discard uncommitted + return to pre-attempt tip.  
**Fix:** Record `PRE=$(git rev-parse HEAD)` before run; on fail `git reset --hard "$PRE"` and `clean`.

### LOW — `grep`/`awk` on Windows path `$WS` with spaces: mostly quoted OK  
Spaces in `$WT` in PROMPT text are fine; `cd "$WT"` OK.

### LOW — `rm -rf "$c"` claim recovery races with live writer  
If PID check false-negative, recovery deletes live claim.  
**Fix:** stronger liveness (see kill -0).

---

## (3) Failure scenarios (explicit matrix)

### Crash mid-card (runner killed / OOM / laptop sleep)
| Step left | State |
|-----------|--------|
| After `mkdir claims/$ID` | claim dir + pid file; card may still `waiting` or partial fm_set |
| After `status writing` | card writing, claim held |
| Mid-agent | dirty worktree, partial commits |
| Before `rm -rf claims` | permanent block until stale recovery |

**Defects:** no trap on EXIT/INT/TERM to release claim + set waiting/blocked; stale recovery needs **dead pid AND age≥90m** → up to 90 minutes stuck; no adoption of orphan worktree on boot (PRD v1, but crash during supervised v0 still hurts).  
**Severity:** HIGH  
**Fix:** `trap 'cleanup_claim' EXIT INT TERM` releasing claim, `status waiting`, optional hard reset to pre-SHA.

### Two runners started with same agent name
**Snippet:** `mkdir` mutex is only per-card; both share same `FAILS`, same `SPENDF`, same pick loop.  
**Scenario:** Both idle-loop; race on claim (one wins); both can run **different** cards concurrently on “single lane” v0 (violates “ONE lane”); file overlap possible (v2 problem early); double spend; circuit breaker counts per-process not per-lane.  
**Severity:** HIGH  
**Fix:** Lane lock `mkdir "$WS/claims/.lane-$AGENT"` (or pidfile with flock) at start; second instance exit 1.

### Clock past midnight
**Snippets:** `DATE=$(date +%Y-%m-%d)` once at start; `REPORT=…/night-$DATE.md`; `SPENDF=…/.spend-$DATE`; stop uses wall clock `HHMM`.  
**Scenario:** Run starts 23:30, continues past 00:00: still writes old night’s report/spend (good for “one night”) but `stop_time 07:00` only triggers when `NOW>=700 && NOW<1200` — overnight OK. **Bug:** if run starts **after** 07:00 same calendar day (restart at 08:00 to finish board), immediately `finish stop_time`. Supervised evening restart next morning is broken. Cross-midnight: `updated "$DATE"` stamps cards with start date not current.  
**Severity:** MED  
**Fix:** Define night window (e.g. stop only if started before stop_time or `NOW` in [stop, stop+grace) once); refresh DATE for logs carefully; don’t stop on first loop if start was after stop (daytime mode flag).

### Card file with missing fields
| Missing | Behavior |
|---------|----------|
| `id` | empty pick / bad claim path |
| `status` | not `waiting` → skipped forever |
| `owner` | treated as any (`""` allowed) — OK |
| `after` | empty → deps_met ok — OK |
| `branch`/`worktree` | spawn — OK if worktree.sh works |
| `budget` | null/'' → TIMEOUT_MIN — OK |
| no frontmatter | fm_get empty — silent skip or bad claim |

**Severity:** MED–HIGH for missing `id`/malformed YAML-like FM  
**Fix:** schema check before claim; `tick "skip malformed"` + leave card blocked with reason.

### Extra: green_cmd / CMD failure modes
Default `green_cmd: … && false` → all cards blocked after attempts; `cmd_$AGENT` missing → exit 1 at start (good).

### Extra: `finish` always `exit 0`
Even on breaker/budget — operators/CI think success.  
**Severity:** LOW  
**Fix:** map reason → exit codes.

---

## Additional notable defects

### HIGH — Success path never verifies “do not touch main” / no branch name assert
Runner never checks current branch ≠ main or that commits only landed on card branch. Gate “0 touches of main” is unenforced.  
**Fix:** After run, assert `git rev-parse --abbrev-ref HEAD` equals card branch; refuse if main advanced.

### MED — Provider backoff leaves attempt counter already incremented
```sh
N=$(( … + 1 )); echo "$N" > …
# later provider hit → waiting, but N already +1
```
**Scenario:** Two 429s burn both `max_attempts` → blocked without a real try.  
**Fix:** Increment attempts only on non-provider completion, or don’t count provider backoff.

### MED — HTTP 5xx missing (already above); also non-JSON CLIs always pay `FALLBACK_COST`
Every card charges $2 even on free local fails → budget stop after ~12 fails.  
**Fix:** Charge fallback only on provider success paths or parse exit.

### MED — `deps_met` accepts `review` as satisfied dependency
Card A in `review` (unmerged) unblocks B overnight — may be intended; PRD says branches unmerged until morning. Dependent work on unmerged review can break.  
**Severity:** MED (product)  
**Fix:** Only `done` satisfies `after:` in v0, or document review-as-done.

### LOW — `notify`/`curl` silent failure; no ntfy on start  
OK for v0.

---

## Top 3 fixes (do these first)

1. **Lane singleton + complete claim protocol** — `mkdir` lane lock for `$AGENT`; on card claim immediately set `status: writing`, `claimed: <iso> pid:$$`, `owner`; `trap` cleanup on EXIT/INT/TERM to drop claim and revert status if incomplete.  
2. **Terminal timeout/fail cleanup** — portable process-group kill; record pre-attempt `HEAD`; on fail/timeout `git reset --hard $PRE` + `clean` + remove `*.lock`; don’t count 429/5xx toward attempts or `FAILS`.  
3. **Stale recovery that works on Git Bash** — portable mtime; recover when PID dead (short grace), not dead∧age≥90 only; validate spend/cost as numbers so mid-card `set -e` death cannot orphan claims.

---

### Quick severity tally
| Sev | Count (approx) | Themes |
|-----|----------------|--------|
| HIGH | ~10 | claim protocol, dual runner, crash orphan, timeout tree, date -r/timeout portability, spend crash, 5xx, attempts on 429 |
| MED | ~10 | status.sh ready, config aliases, midnight/daytime stop, fm validation, reset-to-pre-SHA, kill -0 Windows |
| LOW | ~4 | report overwrite, finish exit 0, notify |

**Bottom line:** The script matches the PRD’s big cuts (no LLM control plane, no merge, no auto-reassign, rule-based ticks) at a product level, but the **claim/recovery/kill/cleanup** path — the part both reviewers treated as load-bearing safety — is incomplete and racy, and several POSIX/Windows assumptions will fail silently until a supervised night hits them.
