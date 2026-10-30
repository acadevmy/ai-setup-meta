# Claude Code's worktrees, opt-in

Claude Code creates worktrees of its own — `claude --worktree`, subagents with
`isolation: "worktree"`, background sessions — under `.claude/worktrees/`,
copying what `.worktreeinclude` lists. They get no port and no `.env` of their
own: two agents that each start the server collide.

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
      { "hooks": [{ "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR/scripts/odyssey.mjs\" hook-create" }] }
    ],
    "WorktreeRemove": [
      { "hooks": [{ "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR/scripts/odyssey.mjs\" hook-remove" }] }
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
