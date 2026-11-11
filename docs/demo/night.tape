# night.tape — records docs/demo/night.gif for the README with VHS
# (https://github.com/charmbracelet/vhs; it needs ttyd and ffmpeg on PATH).
#
# It does NOT run a night: it replays the morning after one, in a repo where a
# real-model goal-loop night has finished. So:
#
#   1. Run a real night in a small demo repo (runner.sh <agent> --drain, goal mode).
#   2. cd into that repo.
#   3. vhs /path/to/apsolut-agents/docs/demo/night.tape
#   4. Copy the night.gif it writes into apsolut-agents/docs/demo/.
#
# Never record it against tests/fake-agent.sh: the README says the demo is real.
#
# The committed night.gif was recorded on 2026-11-11 from a night with Claude Code as
# the worker and planner and Codex as the verifier and reviewer, on a throwaway
# todo-cli repo: two hand-written cards (T-01, T-02), one planner round, goal met.
#
# On Windows, VHS starts WSL's bash (ttyd finds System32\bash.exe before Git Bash).
# The hidden block below makes that work: WSL runs as root on files owned by the
# Windows user, so git needs safe.directory, and the prompt needs setting by hand.

Output night.gif

Set Shell "bash"
Set FontSize 17
Set Width 1280
Set Height 720
Set Padding 24
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Sleep 4s
Type "export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' PS1='$ '; cd .apsolut-agents; clear"
Enter
Sleep 1s
Show

# 1. the evening: what was asked
Type "# evening: a goal, a command that proves it, and two cards"
Enter
Sleep 600ms
Type "grep -E '^(goal|done_cmd):' GOAL.md; grep -H '^title:' work/T-*.md"
Enter
Sleep 4s

# 2. the night: one command (shown, not run)
Type "# night:  sh .apsolut-agents/scripts/runner.sh claude --drain"
Enter
Sleep 2500ms

# 3. the morning: the report
Type "clear"
Enter
Type "# morning: one report"
Enter
Sleep 600ms
Type "head -15 runs/night-????-??-??.md; grep '^| ' runs/night-????-??-??.md | cut -d'|' -f2-6"
Enter
Sleep 9s

# 4. why each card landed: the decision trail
Type "clear"
Enter
Type "# every decision the runner took, in order"
Enter
Sleep 600ms
Type "cut -f3,4,7 runs/trail-*.tsv | column -s$'\t' -t | cut -c1-112"
Enter
Sleep 10s

# 5. nothing moved main; one command lands the night
Type "clear"
Enter
Type "# a second model reviewed the night. main has not moved:"
Enter
Sleep 600ms
Type "tail -7 runs/night-????-??-??.md | head -4; git log --oneline main"
Enter
Sleep 4s
Type "git diff --shortstat main $(git branch | grep -o 'agent/night.*') -- ../bin ../src ../test"
Enter
Sleep 3s
Type "# you land it:  sh .apsolut-agents/scripts/worktree.sh done NIGHT-<date> --merge"
Enter
Sleep 5s
