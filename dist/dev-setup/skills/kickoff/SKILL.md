---
name: kickoff
description: Starts work from an idea already in the conversation, with no task yet — a light discovery from what the session knows, a classification (type, development or hotfix), the fork point, the task on the board on a yes, written in story's format, the branch, then the existing chain — quick under its bar, otherwise sdd-spec, sdd-plan, sdd-dev. Use when the developer describes one piece of work to build now and there is no task id; with one, use sdd; for backlog items someone builds later, or an epic of several stories, use story.
effort: medium
argument-hint: "[idea]"
user-invocable: true
disable-model-invocation: true
---

# Kickoff

The idea-first entry into the chain, for one piece of work built now. `sdd`
starts from a task on the board; this starts from what the conversation
already holds, which is cheaper and keeps the knowledge in context. On a yes it
also creates the task, in the format `story` writes.

## Before you start

- **`reference/classification.md`** — the type, the destination, the check
  that sends several pieces to `story`.
- **`reference/board.md`** — the optional ClickUp task, in story's format.
- **`${CLAUDE_PLUGIN_ROOT}/reference/fork-point.md`** — the base question.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — after you ask,
  the turn ends.
- **`${CLAUDE_PLUGIN_ROOT}/reference/hand-off.md`** — what follows the spec.

## Procedure

### 1. Draft from what you know

Before asking anything, write the Discovery Summary in the shape of
`${CLAUDE_PLUGIN_ROOT}/skills/sdd-discovery/reference/question-bank.md`, from
the conversation, the code already read and `REGISTRY.md`. What the draft
leaves open becomes questions: closed, at most four per call, at most two
calls. Needing more is a sign the work is an epic: `story`'s.

### 2. Classify and pick the fork point

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" --type <type> --title "<title in English>" --json
```

Without `--create` it only reports `BRANCH` and `BASE_BRANCH`. Then one
`AskUserQuestion`: the classification (`reference/classification.md`), the
fork point (`fork-point.md`) and, with a list configured, the task on the
board (`reference/board.md`). End the turn on the call.

### 3. Route

- **Under `quick`'s bar** — at most three files, no new component,
  dependency or public interface, single branch: `quick` cuts its own branch
  and only a person starts it. End with `Next: /dev-setup:quick <description>`.
- **Several pieces**: end with `Next: /dev-setup:story <the idea>`, as
  `reference/classification.md` says. Nothing is created.
- **Otherwise**: `sdd-start.sh` again, with `--base <ref> --create`.

Show the command before running it. Nothing is pushed here.

### 4. Spec

Invoke `sdd-spec` with the Discovery Summary and no task id: it writes
`.specs/<slug>.md` with `> Branch:` naming the branch, which is how
`check-prerequisites.sh` finds the spec on a branch without one.

### 5. Hand off

As `hand-off.md` says: the next step is `sdd-plan`, then the chain.

## Expected output

- a branch cut from the fork point the developer confirmed — or, under the
  bar, the `quick` command to type; with several pieces, the `story` command;
- `.specs/<slug>.md` in `draft`, its `> Branch:` naming the branch;
- on a yes, the task `IN PROGRESS`;
- nothing pushed.
