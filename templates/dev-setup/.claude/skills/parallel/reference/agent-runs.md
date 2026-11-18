# Letting the agent run new and adopt

`new` and `adopt` write the worktree's `.env`, which the Bash sandbox denies,
so by default the developer types them. A project that wants its agents to
prepare worktrees on their own — `multi-sdd` does, before its fan-out — can let
those two commands leave the sandbox. A command outside the sandbox runs
project code past every OS boundary, so it is allowed only with three guards,
and `${CLAUDE_PLUGIN_ROOT}/scripts/parallel-guard.sh --json` is what says
whether they are there: `GUARDED`, and `MISSING` for each entry still lacking.

## The three guards

1. **The direct invocation, never an alias.** The command recorded for `new`
   and `adopt` in `.claude/parallel.json` names the script file:
   `node scripts/parallel.mjs new`, not `pnpm wt new` or `npm run wt -- new`.
   An alias runs whatever `package.json` says today, and `package.json` has to
   stay editable. Resolve the alias once, here — `"wt": "node
   scripts/worktree.mjs"` gives `node scripts/worktree.mjs` — and record that.
   The developer keeps typing the alias by hand; only the agent needs the
   direct form. An alias that resolves to no script file (a `make` target with
   logic of its own) cannot be guarded: leave it, and the line stays theirs.
2. **The script cannot be written from inside the session**: the file in
   `sandbox.filesystem.denyWrite`, and `Edit(**/<file>)` in `permissions.deny`,
   which covers every file tool. What runs outside the sandbox is then the code
   the developer committed, not code rewritten a minute ago. They edit it by
   hand.
3. **Every run asks**: `Bash(<command> *)` in `permissions.ask`, next to the
   pattern in `sandbox.excludedCommands`.

## The block to propose

For `node scripts/parallel.mjs`:

```json
{
  "sandbox": {
    "excludedCommands": ["node scripts/parallel.mjs new *", "node scripts/parallel.mjs adopt *"],
    "filesystem": { "denyWrite": ["scripts/parallel.mjs"] }
  },
  "permissions": {
    "ask": ["Bash(node scripts/parallel.mjs new *)", "Bash(node scripts/parallel.mjs adopt *)"],
    "deny": ["Edit(**/scripts/parallel.mjs)"]
  }
}
```

Merged into the existing arrays, never replacing them. `.claude/settings.json`
gives it to the team, `.claude/settings.local.json` to one developer; the
script reads both. Proposed after the script works (step 2 of the skill),
written only on a yes, and the session cannot write the settings itself: the
developer applies it.

## What it leaves open

The `setup` commands of `CONFIG` run outside the sandbox too, and an install
runs the lifecycle scripts of `package.json` and of the dependencies — files
the session can edit. The `ask` is where the developer sees each run. In auto
mode that approval can come from the classifier instead of a person, so a flow
in auto mode passes the line to the developer even when `GUARDED` is true.

The plugin ships no such exclusion: every project decides for itself, and a
port-forward or a tunnel stays the developer's to run.
