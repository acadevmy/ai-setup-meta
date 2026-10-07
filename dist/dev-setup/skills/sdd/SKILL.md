---
name: sdd
description: Runs the interactive Spec-Driven Development flow for a task — discovery, spec, one approval, development, gates, merge request. Use when the work needs a spec — a new component, dependency or public interface, or a change over more than three files. Under that bar, use `quick`.
effort: medium
argument-hint: "[TASK_ID] [--worktree] [--stop <point>]"
user-invocable: true
disable-model-invocation: true
---

# SDD

Take a task from the board to an open merge request, **interactively**.
Unsupervised, the same ground is `auto-sdd`.

**Usage**: `/dev-setup:sdd [TASK_ID] [--worktree] [--stop <point>]`. Without a
task id it lists what is in `SPRINT` and asks. `--worktree` runs the flow in an
isolated checkout. The stop point — how far it goes — is asked at launch and
saved; `--stop` sets or changes it.

## This flow or `quick`

A fix or chore touching at most three files and adding no new component,
dependency or public interface belongs in `quick`; everything else belongs here.
Say so in one line when a task looks misrouted; the developer decides.

## Before you start

- **`reference/intake.md`** — steps 1–4: task, branch, status, brief, and what
  a spec already on disk changes.
- **`reference/stop-point.md`** — the six places the flow can end, and how a
  run resumes from one.
- **`reference/closure.md`** — step 9: gates, commit, merge request.
- **`${CLAUDE_PLUGIN_ROOT}/reference/worktree.md`** — only with `--worktree`.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — the rule for every
  question.
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

Steps 5 to 8 are sub-skills: invoke each by name with the task context.

**Three stops: launch (step 2 — fork point and stop point, one call), discovery
(step 5 — one call, at most two), spec approval (step 7).** A resume with a
saved stop point skips the first; picking a task and the backlog gate add one
when they apply. `sdd-dev`'s summary is not a stop — go on in the same turn.
No final OK in chat: the `ask` rule on `gh pr create`/`glab mr create` is the
real one.

## Expected output

With the stop point at the merge request (the default):

- a branch named after the task, cut from the confirmed fork point;
- a spec in `.specs/`, status `implemented`;
- one commit carrying the code, the spec and whatever the gates changed;
- the task moved `SPRINT` → `IN PROGRESS` → `CODE REVIEW`;
- a merge request linking the task and the spec.

An earlier stop point leaves what `reference/stop-point.md` lists for it.
