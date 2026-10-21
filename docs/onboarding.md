# Onboarding — from zero to your first task

One page. Four steps. Everything else is in
[developer-guide.md](./developer-guide.md).

**You need**: `git`, the `claude` CLI — Claude Code 2.1.281 or later, on every
machine and runner that works on the project — and `gh` (GitHub repos) or `glab`
(GitLab repos) already authenticated. The setup stops on an older client: it
writes no `CLAUDE.md`, and an older Claude Code does not read `AGENTS.md`.

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
| Project context for any agent, Claude Code included | `AGENTS.md` |
| What already exists in the project | `REGISTRY.md` |
| The pull request template, in the language you pick | `.github/PULL_REQUEST_TEMPLATE.md` or `.gitlab/merge_request_templates/Default.md` |
| The merge request language and labels — yours to edit | `.claude/merge-request.json` |

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

It stops three times: once at launch — which branch to fork from (the base
resolved from the repository is the default) and how far to go — once for
discovery, only about what the task leaves open, and once to approve the spec.
Then development, the gates, one commit and the merge request.

## Know where a flow is

The phases of an `sdd` show as a task list, the session is named after its
task in `claude --resume`, every closing report ends on a `Next:` line, and a
permission prompt during a task sends a desktop notification naming it. Two
settings are yours, in your **user** settings (`~/.claude/settings.json`) or the
managed ones, never the project's `.claude/settings.json`, which ignores
`footerLinksRegexes`:

```json
{
  "preferredNotifChannel": "terminal_bell",
  "footerLinksRegexes": [
    { "type": "regex", "pattern": "(?<id>DE-\\d+)",
      "url": "https://app.clickup.com/t/<workspace-id>/{id}", "label": "{id}" }
  ]
}
```

`"terminal_bell"` rings in any terminal — the default `auto` notifies only in
iTerm2, Ghostty and Kitty. The second entry makes every `DE-123` a ClickUp link.

## Where to go next

| Question | Read |
|---|---|
| Which command for which job, and what the sandbox blocks | [developer-guide.md](./developer-guide.md) |
| Coming from plugin v2 — what broke | [migration-v2-to-v3.md](./migration-v2-to-v3.md) |
| Why the rules are enforced instead of written down | [training.md](./training.md) |
| Changing the plugin itself | [workflow.md](./workflow.md) |
