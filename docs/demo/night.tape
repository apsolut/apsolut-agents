# night.tape — records docs/demo/night.gif for the README with VHS
# (https://github.com/charmbracelet/vhs; it needs ttyd and ffmpeg on PATH).
#
# It does NOT run a night: a real night takes hours. It replays the morning after
# one, in a repo where a real-model night has finished. So:
#
#   1. Run a real night in a small demo repo (runner.sh <agent> --drain, goal mode).
#   2. cd into that repo.
#   3. vhs /path/to/apsolut-agents/docs/demo/night.tape
#   4. Copy the night.gif it writes into apsolut-agents/docs/demo/ and uncomment the
#      image line at the top of README.md.
#
# Never record it against tests/fake-agent.sh: the README says the demo is real.
# Not yet run: check the timings and the window size on the first recording.

Output night.gif

Require git
Require sh

Set Shell "bash"
Set FontSize 18
Set Width 1280
Set Height 760
Set Padding 24
Set TypingSpeed 45ms
Set Theme "Catppuccin Mocha"

# 1. the evening: what was asked
Type "# evening: the goal, and the cards on the board"
Enter
Sleep 800ms
Type "grep -E '^(goal|done_cmd):' .apsolut-agents/GOAL.md"
Enter
Sleep 2500ms
Type "grep -H '^title:' .apsolut-agents/work/*.md | grep -v _TEMPLATE"
Enter
Sleep 3500ms

# 2. the night: one command (shown, not run)
Type "# night: sh .apsolut-agents/scripts/runner.sh claude --drain"
Enter
Sleep 2500ms

# 3. the morning: the report
Type "clear"
Enter
Type "# morning: one report"
Enter
Sleep 800ms
Type "ls .apsolut-agents/runs/night-*.md | grep -v attention | tail -1 | xargs head -32"
Enter
Sleep 9s

# 4. why each card landed: the decision trail
Type "clear"
Enter
Type "# every decision, with its evidence"
Enter
Sleep 800ms
Type "cut -f3,4,7 $(ls .apsolut-agents/runs/trail-*.tsv | tail -1) | column -s$'\t' -t | cut -c1-110 | tail -14"
Enter
Sleep 9s

# 5. nothing moved main; one command lands the night
Type "clear"
Enter
Type "git log --oneline -3 main"
Enter
Sleep 2500ms
Type "# main has not moved. You land the night with one merge:"
Enter
Type "# sh .apsolut-agents/scripts/worktree.sh done NIGHT-<date> --merge"
Enter
Sleep 5s
