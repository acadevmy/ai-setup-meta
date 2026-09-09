---
name: vcs-ops
description: Branch, commit, pull/merge request, tag and release conventions, and the git/gh/glab commands that carry them out. Use when creating a branch, writing a commit message, opening or checking a PR or MR, or cutting a release.
user-invocable: false
disable-model-invocation: false
---

# VCS operations

Everything runs through `git` plus the host CLI — `gh` on GitHub, `glab` on
GitLab. Do not use the GitHub or GitLab MCP servers: the CLIs read the token from
the environment, so it never lands on a command line or in a log. `git` needs
`user.name` and `user.email` configured.

Work out the host once, before anything else:

```bash
git remote get-url origin | tr 'A-Z' 'a-z'
```

`github` in the URL → [reference/github.md](reference/github.md).
`gitlab` in the URL → [reference/gitlab.md](reference/gitlab.md).
Neither, on a self-hosted host → probe `gh auth status --hostname <host>` and
`glab auth status --hostname <host>`; whichever succeeds is the host. If neither
does, stop and ask.

Those two files hold **only** what differs: the CLI invocations and each tool's
quirks. Everything below is plain git, or a convention, and is the same on both.

## Branch

```
<type>/<TASK-ID>-<short-description>
```

`<type>` is `feat`, `fix`, `chore` or `hotfix`; `<TASK-ID>` is the tracker's
custom id (`DE-123`), dropped when there is no task; the description is short,
kebab-case and in English.

The base is the project's reference branch, which is **not always `main`**:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||')
git checkout "$BASE" && git pull --ff-only
git checkout -b feat/DE-123-add-user-auth
```

If `origin/HEAD` is unset locally, `git branch -r --sort=-committerdate | head`
shows which long-lived branches the project uses — several target `next` or
`develop` and keep `main` for production.

## Commits

Conventional Commits; the project's commitlint config enforces it.

```
<type>(<scope>): <description in English, imperative, lowercase>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`,
`ci`, `build`, `revert`. One commit is one coherent change.

## Pull / merge requests

Title follows Conventional Commits and carries the task id:
`feat(auth): add refresh token rotation [DE-123]`. Body:

```markdown
## What changed
<description of changes>

## Why
<motivation>

## How to test
- [ ] <step 1>

## Checklist
- [ ] No secrets or API keys included
- [ ] CHANGELOG updated
- [ ] project rules respected

## Task
- [DE-XXX](link to task)
```

Never fill the body from the commit log (`--fill`): it drops that structure.
Labels come from what the repository defines — list them, pick from those, do
not invent one. On GitLab the body usually comes from the repo's own MR
template; its reference explains when.

Read the repository's `AGENTS.md` first: the team's conventions on title,
language and target branch win over the defaults here.

## Tag and release

```bash
git tag -a v1.2.0 -m "v1.2.0"
git push origin v1.2.0
```

Then the host's release command. On a repository driven by release-please or
semantic-release, do none of this by hand — merging the release PR creates the
tag and the release.
