---
name: odyssey
description: Runs a project on several git worktrees at once, each with its own ports, .env, compose project and tunnels, and readies a project that cannot yet — a readiness report, then a project-local script from a template. Use when branches have to run side by side, when each agent needs its own instance, when a problem has to be reproduced on a branch or environment, or when tunnels are needed.
effort: medium
argument-hint: "[analyze | new | up | list | rm | tunnels | expose] [branch]"
user-invocable: true
disable-model-invocation: true
---

# Odyssey

Several copies of the project running together, one per worktree, without
sharing ports, sessions, containers or a database. The skill holds no runtime:
each project owns its script, and the skill knows which command to run.

## Before you start

- **`reference/readiness.md`** — what blocks parallel instances, and the report.
- **`reference/tunnels.md`** — outbound port-forwards and the inbound URL.
- **`reference/claude-worktrees.md`** — the opt-in `WorktreeCreate` hook.
- **`${CLAUDE_PLUGIN_ROOT}/reference/worktree.md`** — worktrees in this plugin.

## 1. Find the commands

Read `.claude/odyssey.json` in the main checkout (the parent of
`git rev-parse --path-format=absolute --git-common-dir`): one command line per
key — `new`, `dev`, `up`, `list`, `rm`, `tunnels`, `expose` — `null` when the
project has none.

Present → step 3. Absent → look for the project's own scripts first (`package.json`,
`Makefile`, `scripts/`, the README: worktree, tunnel, port-forward). If they
exist, propose recording them in `.claude/odyssey.json` and go to step 3.

## 2. First time: readiness and the script

1. Analyse with `reference/readiness.md` and show the report.
2. On the developer's yes, and only for the fixes approved: apply them; copy
   `${CLAUDE_SKILL_DIR}/templates/odyssey.mjs` to `scripts/odyssey.mjs` and fill
   in **only** its `CONFIG` block; write `.claude/odyssey.json`.
3. Have the developer try it on a throwaway branch: `new` → `list` → `dev` →
   stop → `rm`. Fix `CONFIG` and repeat until it holds.

The script, the config and the fixes are project code: committing them is the
developer's call.

## 3. Run

- **The developer runs** what the sandbox stops: `new` writes `.env`, and
  `tunnels`, `expose` — usually `up` too — reach beyond the sandbox's network
  or `~/.kube`. Give the exact line, run from the main checkout, to type in
  their terminal or after `!`.
- **You run** `list`, and `dev` when the project's server needs nothing outside
  the sandbox — in the background, then check with `list` that it listens.
- **Before starting**, `list`: an instance already up on another branch is not
  the one to verify this branch on.
- **Reproducing a problem** on a branch or environment: that branch's worktree,
  never a branch switch in the main checkout.
- **Production**: say so before anything starts — data, payments and email are
  real.
- **`rm`** never forces: with uncommitted changes it fails, and that is right.

## Expected output

- a readiness report, or the project's commands found;
- with the developer's yes, `scripts/odyssey.mjs` and `.claude/odyssey.json`;
- instances running on distinct ports, each named with its port.
