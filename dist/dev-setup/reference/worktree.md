# Working in a worktree

A worktree is a second checkout of the same repository, with its own files and
its own branch. One task per worktree means two sessions never edit the same
file, and neither one has to finish before the other starts.

`n` *interactive* tasks are `n` invocations of `sdd` or `quick`, one terminal
each: a flow that stops to ask needs a chat of its own. `n` *autonomous* tasks
are one `multi-sdd`, which fans out one `auto-sdd` run per task from a single
session. Either way the review queue, not the tooling, is what caps how many are
worth having open — and `multi-sdd` puts that cap at five, in a script.

## Index

- [Starting one](#starting-one)
- [The fork point](#the-fork-point)
- [The files git does not carry](#the-files-git-does-not-carry)
- [Dependencies](#dependencies)
- [The dev server port](#the-dev-server-port)
- [Are two worktrees fighting?](#are-two-worktrees-fighting)
- [What isolation refuses](#what-isolation-refuses)
- [Cleaning up](#cleaning-up)

## Starting one

From a terminal, before the session exists:

```bash
claude --worktree DE-123
```

The worktree lands at `.claude/worktrees/DE-123/` on a branch named
`worktree-DE-123`; `sdd-start.sh` then creates the real task branch inside it.
Run the command again with another id in another terminal for a second task.

Inside a session, `--worktree` on `/dev-setup:sdd` or `/dev-setup:quick` means
the same thing through the `EnterWorktree` tool: name the worktree after the
task id, so `git worktree list` reads as a list of what is in flight.

## The fork point

**`worktree.baseRef` cannot name a branch.** It takes `"fresh"` (the remote
default branch, usually `main`) or `"head"` (the local `HEAD` you started from,
unpushed commits included). On a project whose work targets `next` while the
remote default is still `main`, `"fresh"` silently forks the worktree from the
wrong branch — which is why the setup writes `"head"` for those projects, and
why the fork point is passed explicitly anyway:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" \
  --task DE-123 --title "<name>" --base origin/next --create --json
```

Take that ref from `check-prerequisites.sh` in the main checkout — `BASE_BRANCH`
— and pass it in. Guessing it inside a fresh worktree is how a branch ends up
carrying the whole `main..next` delta.

## The files git does not carry

A worktree is a clean checkout, so gitignored files — `.env`, `.env.local` — are
simply absent, and the app fails to boot for a reason that looks like a code
problem. `.worktreeinclude` at the repository root fixes it: `.gitignore`
syntax, and Claude Code copies every file that matches **and is gitignored**
into each new worktree. The setup installs one; add the project's own patterns
to it rather than copying files by hand.

It is not processed when a `WorktreeCreate` hook is configured, because the hook
replaces worktree creation wholesale. That is the reason this plugin ships no
such hook.

## Dependencies

`node_modules/` is gitignored and far too large to copy, so install after
entering:

```bash
pnpm install    # or the PKG_MANAGER detect-stack.sh reports
```

With pnpm's global store this is close to free — it links, it does not download.
There is no post-create hook to hang this on (see above), so it is a step of the
flow, and skipping it produces a "module not found" that has nothing to do with
the task.

## The dev server port

Every worktree runs the same `dev` script, so they all want the same port. Take
the offset from the tooling instead of picking a number:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-info.sh" --json
```

`PORT_OFFSET` is this worktree's index in `git worktree list` — 0 for the main
checkout, 1 for the first worktree, and so on. Start the server on
`<the project's base port> + PORT_OFFSET`: `PORT=3001 pnpm dev`, `--port 4201`,
whatever the framework takes. Say which port you used; the developer has several
tabs open.

## Are two worktrees fighting?

The same call answers it. `OVERLAPS` lists every file that more than one active
worktree declares in its spec's `## Impact` section, with the branches that
declared it:

```
src/app.module.ts	feat/DE-123-add-auth,feat/DE-124-add-billing
```

Report it to the developer once, at the start, and name the file and both
branches. It is a warning and nothing else: two tasks may legitimately touch the
same module, and the point is that the rebase is expected rather than
discovered. A worktree with no spec contributes nothing to the comparison.

Before a fan-out there is no spec and no worktree yet, only an estimate per task.
`--impact <label>=<files>` feeds those through the same comparison, so the answer
is computed in one place either way — and the tasks about to start are checked
against the worktrees already in flight for free:

```bash
worktree-info.sh --json --impact "DE-1=src/app.module.ts" --impact "DE-2=src/app.module.ts"
```

## What isolation refuses

While a session is in a worktree, the harness blocks the calls that would reach
back into the main checkout: an `Edit`/`Write` at a path outside the worktree, a
Bash command whose working directory resolves there, and any `git -C`,
`GIT_DIR`, `GIT_WORK_TREE` or `cd` that redirects git out of it. These are not
permission prompts and there is nothing to approve — the refusal names the
worktree, and the fix is to do the work inside it. A change that genuinely
belongs in the main checkout belongs in a different session.

Hook commands are the exception worth knowing: `$CLAUDE_PROJECT_DIR` still
points at the main checkout, so a hook reads the worktree path from the `cwd`
field of its payload.

## Cleaning up

Leaving the session prompts to keep or remove the worktree; a worktree holding
changes or commits is kept. By hand:

```bash
git worktree list
git worktree remove <path>          # --force if it still holds changes
```

Removing it deletes the branch and everything not pushed. A failed run is worth
keeping until it has been read.
