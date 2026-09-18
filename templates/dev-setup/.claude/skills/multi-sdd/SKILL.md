---
name: multi-sdd
description: Runs the autonomous SDD workflow on up to five tracked tasks from one session — a sequential pre-flight, then one background run per task in its own worktree, each outcome reported as it lands. Use when several independent tasks should each reach a review-ready merge request without a terminal per task.
effort: medium
user-invocable: true
disable-model-invocation: true
---

# Multi SDD

One session, several tasks. This command **composes** the `auto-sdd` workflow: it
holds no development logic, and every line of spec → challenge → dev → verify
lives in `workflows/auto-sdd.js`.

**Usage**: `/dev-setup:multi-sdd DE-1 DE-2 …`, or `--from-sprint <n>` to take
the first `n` `SPRINT` tasks off the board rather than naming them.

The chat is a control tower: the human parts happen **before** the fan-out or
**after**, never braided through the middle. Parallel *interactive* work stays
`n` invocations of `sdd`, one terminal each.

## The cap is a script, not a sentence

Run this first, always, and act on its exit status:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/multi-preflight.sh" --json \
  --task "DE-1" --task "DE-2"          # or: --from-sprint "2"
```

One quoted `--task` per id. Never splice `$ARGUMENTS` into that line: an id
carrying a `;` would run as shell *before* the check meant to reject it.

Exit 3 means refused — print `REASON` and **stop**: no run starts, no task is
touched, nothing is negotiated. It refuses six tasks, none at all, a duplicate
id, and an id that is not a plain identifier. `--from-sprint <n>` validates `n`
only; call it again with the ids the board returned, and an empty `SPRINT` is
refused there.

Five is the ceiling because review is the bottleneck, not compute, and **the
cost is `n` times a single run** — five tasks means fifteen verifiers.

## Before you start

- **`reference/preflight.md`** — phase A, the sequential part.
- **`reference/fan-out.md`** — phases B and C, and the ledger.
- **`${CLAUDE_PLUGIN_ROOT}/reference/run-outcomes.md`** — each outcome and what
  to do about it. Unchanged by there being several.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — the rule for every
  question phase A asks.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents, the
  transitions, the list id.

## The three phases

| # | Phase | Shape | Where |
|---|---|---|---|
| A | Intake, triage, the questions no agent can answer, the overlap warning | sequential, one task at a time | `reference/preflight.md` |
| B | One `auto-sdd` run per task, each in its own worktree | parallel, in the background | `reference/fan-out.md` |
| C | Each outcome reported here as it lands | as they arrive | `reference/fan-out.md` |

Phase A finishes for **every** task before B starts for any: once the runs are
going, a question in the middle of one blocks the other four.

## Expected output

- one refusal and nothing else, when the gate says no;
- otherwise a worktree, a branch and an outcome per task, all in this chat;
- a `needs-human` holds up none of the other runs;
- no edit in the developer checkout.
