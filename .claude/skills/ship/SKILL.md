---
name: ship
description: "Commit Muster's current changes, run the full check, and push to main if it passes. Stops on any failure."
argument-hint: "[commit summary]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(git status*), Bash(git diff*), Bash(git add *), Bash(git log*), Bash(git commit *), Bash(git -c * commit *), Bash(git push origin main), Bash(git rev-parse*), Bash(git ls-remote*), Bash(bash tools/dev/check.sh*)
model: sonnet
---

# Ship

1. Run `git status --short` and `git diff --stat`. Stage files by name. Never stage `*.png.import` line-ending noise, `data/local/`, or anything that looks like a secret.
2. Stop and ask if the changes include something destructive, or files you can't explain.
3. Commit with a Conventional Commits message that says why. Use `$ARGUMENTS` as the summary if given. Include a `Task:` line naming the design doc or task, and the attribution line this session specifies.
4. Run `bash tools/dev/check.sh` with a 10-minute timeout.
5. If the `RESULT:` line doesn't say `recorded for`, stop and report. Don't push, and never bypass the check or `--no-verify`. If it says `NOT FULLY ASSESSED`, you may push, but name what wasn't run in your report.
6. Run `git push origin main`, then confirm `git rev-parse HEAD` matches `git ls-remote origin refs/heads/main`.

Report the commit, the check result and whether GitHub matches. Never force push.
