# Worktrees made elsewhere

Claude Code creates worktrees of its own — `claude --worktree`, subagents with
`isolation: "worktree"`, background sessions — under `.claude/worktrees/`,
copying what `.worktreeinclude` lists. They get no port and no `.env` of their
own: two agents that each start the server collide. So does a worktree made by
hand with `git worktree add`. Two ways to give them an instance: `adopt` one
after the fact, or let the hook create every one.

## Adopt one after the fact

```bash
node scripts/parallel.mjs adopt <name | branch | path> [--skip-setup]
```

It gives the worktree the first free slot, rewrites its `.env` from the main
checkout's with that slot's values — a copied `.env` still carries the main
checkout's ports — and runs `CONFIG.setup` unless `--skip-setup` says the
dependencies are already there. Then `dev` starts it like any other. A
worktree that already has a slot is left as it is; the main checkout is slot 0
and is refused.

This is the way to try the result of an `auto-sdd` or `multi-sdd` run: the
run's `worktreePath` is the argument. It writes `.env`, so the developer runs
it, like `new`. `rm` on an adopted worktree removes it the git way, which the
run's own cleanup would have done anyway.

## The hook

A `WorktreeCreate` hook **replaces** worktree creation wholesale. It receives a
JSON payload on stdin with `name` and `cwd`, and prints **only** the worktree
path on stdout; a non-zero exit fails the creation. `WorktreeRemove` fires for
the worktrees the hook created, with `worktree_path`. With the hook in place,
`.worktreeinclude` is **not** applied — which is why the plugin ships no such
hook (`worktree.md`).

A project that runs its agents in parallel instances can opt in: the generated
script already has both ends. `hook-create` cuts `worktree-<name>` from the HEAD
of `cwd` into `../<repo>.wt/claude-<name>` with its own slot, and copies what
`CONFIG.env.copy` lists — that list takes over from `.worktreeinclude`, so
everything the project's `.worktreeinclude` carries has to be in it.
`hook-remove` stops the containers and removes the worktree, without `--force`.

## The settings

Proposed, never installed on the developer's behalf. In the project's
`.claude/settings.local.json` for one developer, in `.claude/settings.json` for
the team:

```json
{
  "hooks": {
    "WorktreeCreate": [
      { "hooks": [{ "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR/scripts/parallel.mjs\" hook-create" }] }
    ],
    "WorktreeRemove": [
      { "hooks": [{ "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR/scripts/parallel.mjs\" hook-remove" }] }
    ]
  }
}
```

The hook runs as a hook, outside the Bash sandbox, so it can write the
worktree's `.env`.

## When not to

- A long `setup` (install and a monorepo build): every subagent pays it before
  it starts. If the agents do not start services, the default worktrees are
  enough.
- A project whose own worktree script deliberately leaves Claude Code's
  worktrees out: do not lay the hook over it without asking.
