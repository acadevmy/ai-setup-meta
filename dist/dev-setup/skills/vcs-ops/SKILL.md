---
name: vcs-ops
description: Branch, commit, pull/merge request, tag and release conventions, and the git/gh/glab commands that carry them out. Use when creating a branch, writing a commit message, opening or checking a PR or MR, or cutting a release.
user-invocable: false
disable-model-invocation: false
---

# VCS operations

Everything here runs through `git` and the host CLI — `gh` on GitHub, `glab` on
GitLab. Do not use the GitHub or GitLab MCP servers: the CLIs read the token from
the environment, so it never lands on a command line or in a log.

Work out which host this repository is on, once, before anything else:

```bash
git remote get-url origin | tr 'A-Z' 'a-z'
```

`github` in the URL → read [reference/github.md](reference/github.md).
`gitlab` in the URL → read [reference/gitlab.md](reference/gitlab.md).
Neither, on a self-hosted host, → probe `gh auth status --hostname <host>` and
`glab auth status --hostname <host>`; whichever succeeds is the host. If neither
does, stop and ask — do not guess.

The conventions below hold on both. The reference files carry only what differs:
the commands, and the quirks of each CLI.

## Branches

```
<type>/<TASK-ID>-<short-description>
```

`<type>` is `feat`, `fix`, `chore` or `hotfix`. `<TASK-ID>` is the tracker's
custom id (`DE-123`); drop it when there is no task. The description is short,
kebab-case and in English — `feat/DE-123-add-user-auth`.

The base is the project's own reference branch, which is **not always `main`**:

```bash
git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||'
```

## Commits

Conventional Commits, and the project's commitlint config is what enforces it:

```
<type>(<scope>): <description in English, imperative, lowercase>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`,
`ci`, `build`, `revert`. One commit is one coherent change — no half-finished
work, no debug leftovers.

## Pull / merge requests

The title follows Conventional Commits and carries the task id:
`feat(auth): add refresh token rotation [DE-123]`. The body says what changed,
why, and how to test it:

```markdown
## What changed
<description of changes>

## Why
<motivation>

## How to test
- [ ] <step 1>
- [ ] <step 2>

## Checklist
- [ ] No secrets or API keys included
- [ ] CHANGELOG updated
- [ ] project rules respected

## Task
- [DE-XXX](link to task)
```

Labels come from the labels this repository actually defines — list them with
`gh label list` or `glab label list` and pick from those. Do not invent one.

On GitLab the body usually comes from the repo's own MR template instead; the
GitLab reference explains when and how.

## Rules

- Never `git push --force`, under any circumstances.
- Never push directly to the reference branch — open a PR/MR.
- Verify the local branch is up to date before any operation.
- Read the repository's `AGENTS.md` before opening a PR/MR: the team's own
  conventions on title, description language and target branch win over the
  defaults here.
