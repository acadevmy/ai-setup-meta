# Onboarding — from zero to your first task

One page. Four steps. Everything else is in
[developer-guide.md](./developer-guide.md).

**You need**: `git`, the `claude` CLI, and `gh` (GitHub repos) or `glab` (GitLab
repos) already authenticated.

## 1. Add the marketplace, install the plugin

Once per machine, in any Claude Code session:

```
/plugin marketplace add acadevmy/ai-setup-meta
/plugin install dev-setup@acadevmy
```

## 2. Configure the project

From the project root:

```bash
cd <your-project>
claude
```

```
/dev-setup:setup
```

It reads the repository and picks its own mode — **GREENFIELD** for an empty
directory, **EXISTING** for a project that already has code, **UPDATE** for one
this plugin has configured before. Then it writes:

| What | Where |
|---|---|
| The rules the harness loads by file type | `.claude/rules/dev-setup-*.md` |
| Permissions, Bash sandbox, quality gate | `.claude/settings.json` |
| Project context for any agent | `AGENTS.md`, `CLAUDE.md` |
| What already exists in the project | `REGISTRY.md` |

It asks before overwriting anything, and it never reads or writes `.env`.
Coming from an older version of the plugin? Read
[migration-v2-to-v3.md](./migration-v2-to-v3.md) before the UPDATE run.

## 3. Do a small task

A one-line fix does not need a spec:

```
/dev-setup:quick DE-123
```

or, with no ticket, `/dev-setup:quick fix the empty-state copy on the dashboard`.

It creates the branch, makes the change, commits it behind the quality gate and
opens the merge request. Two things will stop and ask you: the gate refuses a
commit whose lint, types or tests are red — read the output, fix, commit again —
and opening the merge request needs your confirmation.

## 4. Do a real one

Anything above three files, or that adds a component, a dependency or a public
interface:

```
/dev-setup:sdd DE-124
```

Discovery, then a technical spec you approve — that approval is the flow's one
unconditional stop — then development, the gates, one commit and the merge
request.

## Where to go next

| Question | Read |
|---|---|
| Which command for which job, and what the sandbox blocks | [developer-guide.md](./developer-guide.md) |
| Coming from plugin v2 — what broke | [migration-v2-to-v3.md](./migration-v2-to-v3.md) |
| Why the rules are enforced instead of written down | [training.md](./training.md) |
| Changing the plugin itself | [workflow.md](./workflow.md) |
