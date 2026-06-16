# The delegation loop (Brain ⇄ Claude Code)

Two roles:
- **Brain** (planning agent): does research, product/architecture decisions, reviews Claude Code's output, and turns each next action into a clear, copy-paste prompt.
- **Claude Code** (Opus 4.8, in VS Code): executes prompts inside this repo on the Mac (has Xcode/Swift toolchain the Brain lacks).

## Cycle
1. Brain analyzes context → picks the next step.
2. Brain emits a **PROMPT** block (copy-paste into Claude Code).
3. Every prompt ends with a **required structured response format** so the result is easy to paste back.
4. You paste Claude Code's structured response back to the Brain.
5. Brain interprets, adjusts strategy, emits the next prompt.
6. Repeat until done.

## Standard response format we ask Claude Code to use
At the end of each task, Claude Code must reply with:

```
### RESULT
status: success | partial | blocked
summary: <2–4 sentences>

### CHANGES
- <path> — <what changed>

### COMMANDS_RUN
- <cmd> → <result/exit>

### VALIDATION
- <what was tested> → <pass/fail + key output>

### BLOCKERS / DECISIONS_NEEDED
- <question for the Brain, or "none">

### NEXT
- <Claude Code's suggested next step, or "awaiting Brain">
```

This keeps each handoff compact and lets the Brain plan the next move precisely.

## Conventions
- One coherent unit of work per prompt; commit at the end with a conventional-commit message.
- If blocked, set `status: blocked` and ask in `BLOCKERS` rather than guessing.
- Paste real output (numbers, errors) in `VALIDATION` — the Brain relies on it.
