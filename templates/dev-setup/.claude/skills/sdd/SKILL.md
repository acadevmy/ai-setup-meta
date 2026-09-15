---
name: sdd
description: Runs the interactive Spec-Driven Development flow for a task — discovery, spec, one approval, development, gates, merge request. Use when the work needs a spec — a new component, dependency or public interface, or a change over more than three files. Under that bar, use `quick`.
effort: medium
user-invocable: true
disable-model-invocation: true
---

# SDD

Take a task from the board to an open merge request, **interactively**: a spec,
a plan, and one checkpoint where the developer approves it. For the same ground
unsupervised, use `auto-sdd`; for a change too small to spec, `quick`.

**Usage**: `/dev-setup:sdd [TASK_ID] [--worktree]`. With a task id (e.g.
`DE-123`) it reads that task; without one it lists what is in `SPRINT` and asks.
`--worktree` runs the flow in an isolated checkout.

## This flow or `quick`

A fix or chore touching at most three files and adding no new component,
dependency or public interface belongs in `quick`; everything else belongs here.
Say so in one line when a task looks misrouted — the route is the developer's
call, and the command they typed is that call.

## Before you start

- **`reference/intake.md`** — steps 1–4: task, branch, status, brief, and what
  a spec already on disk changes.
- **`reference/closure.md`** — step 9: the gates, the commit, the merge request.
- **`${CLAUDE_PLUGIN_ROOT}/reference/worktree.md`** — only with `--worktree`.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — the rule for every
  question this flow asks.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents, the
  transitions, the list id.

## The flow

| # | Step | Where |
|---|---|---|
| 1–4 | Task, branch, status → IN PROGRESS, brief | `reference/intake.md` |
| 5 | Discovery — the structured interview | the `sdd-discovery` skill |
| 6 | Technical spec in `.specs/<customId>-<slug>.md` | the `sdd-spec` skill |
| 7 | Spec review and approval — **the checkpoint** | the `sdd-plan` skill |
| 8 | Development against the approved plan | the `sdd-dev` skill |
| 9 | Gates, commit, merge request | `reference/closure.md` |

Steps 5 to 8 are sub-skills: invoke each one by name, passing the task context,
and wait for it to finish before moving on. They are not user-invocable — this
flow is their entry point.

**Two questions stop this flow: the fork point in step 2 — the resolved base
branch is the default, the developer confirms it — and the spec approval in
step 7.** Nothing else does: `sdd-dev`'s closing summary is not a stop — go
straight to step 9, in the same turn. The final OK in chat is gone: the `ask`
rule on `gh pr create`/`glab mr create` is the real one.

## Expected output

- a branch named after the task's custom id, created by `sdd-start.sh` from
  the confirmed fork point;
- a spec in `.specs/`, status `implemented`;
- one commit carrying the code, the spec and whatever the gates changed;
- the task moved `SPRINT` → `IN PROGRESS` → `CODE REVIEW`;
- a merge request linking the task and the spec.
