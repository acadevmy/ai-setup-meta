---
name: sdd-plan
description: Presents a technical spec to the developer and iterates on it until they approve it, then marks it approved. Use when a draft spec exists and needs the developer's review before development starts.
effort: medium
user-invocable: false
disable-model-invocation: false
allowed-tools: AskUserQuestion
---

# SDD plan

Present a spec for review, discussion and approval. This is the supervision
checkpoint of the interactive flow: nothing downstream runs until the developer
approves, and approval is theirs to give — never inferred from silence.

## Before you start

- **`reference/approval-loop.md`** — the question to ask and what each answer
  means.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — after you ask, the
  turn ends.

## Procedure

### 1. Locate the spec

- **a path in `$ARGUMENTS`** (e.g. `.specs/DE-123-add-auth.md`) → read that
  file; if it does not exist, say so and stop;
- **a custom id** (e.g. `DE-123`) → find `.specs/DE-123-*.md`; if there is no
  match, say so and stop;
- **nothing** → list the `.md` files in `.specs/`. None: say so and stop. One:
  open it. Several: ask which one.

### 2. Present it

Show the spec in full, with clear formatting, and state its current status
(`draft` / `approved` / `implemented`).

### 3. Discuss and iterate

Follow `reference/approval-loop.md`.

### 4. Confirm

```
Spec: .specs/<filename>
Status: <updated status>
```

## Expected output

- the spec presented and discussed with the developer;
- the spec file updated with whatever was agreed;
- `Status: approved` and the approval date, when it was approved.
