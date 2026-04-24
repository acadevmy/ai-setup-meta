---
name: github-ops
description: Reference documentation for Git and GitHub operations (branch, PR, tag, release)
model: haiku
user-invocable: false
disable-model-invocation: false
---

# Skill: GitHub Operations

Git and GitHub operations via `git` and `gh` CLI.
Do NOT use MCP GitHub — always use direct commands.

## Prerequisites
- `gh` CLI installed and authenticated (`gh auth login`)
- `git` configured with user.name and user.email

## Self-identify (run first)

Before executing any operation, verify the current repository targets GitHub:

```bash
git remote get-url origin | tr 'A-Z' 'a-z'
```

If the URL does **not** contain `github` (and no other signal identifies the host as GitHub), bail with a single-line message:
`github-ops invoked on a non-GitHub repo (origin=<url>) — use gitlab-ops instead.`

For GitHub Enterprise whose host is ambiguous, probe `gh auth status --hostname <host>`; if it succeeds, proceed.

## Available operations

### Create a branch
```
git checkout -b <type>/<customId>-<short-description>

Naming convention:
  - Prefix: feat/, fix/, chore/, hotfix/
  - CustomId: the ClickUp task custom_id (e.g. DE-123)
  - Description: short, kebab-case, in English

Examples:
  feat/DE-123-add-user-auth
  fix/DE-456-handle-null-response
  chore/DE-789-update-dependencies

Base: always `main` unless specified otherwise
```

### Open a Pull Request
```
gh pr create --title "<title>" --body "<body>"
Required fields:
  - title: follows Conventional Commits, includes customId — e.g. "feat(auth): add refresh token rotation [DE-123]"
  - body: includes What / Why / How to test sections
  - labels: one of [constitution, template, skill, profile, release]
  - base: main
  - head: current branch
```

PR body template:
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
- [ ] CONSTITUTION respected

## ClickUp
- Task: [DE-XXX](link to task)
```

### Create a tag and a Release
```
git tag -a <tag> -m "<message>"
git push origin <tag>
gh release create <tag> --title "<title>" --notes "<body from CHANGELOG>"
```

### Check PR status
```
gh pr view <number> --json state
gh pr list --state open
```

## Rules
- Never use `git push --force` under any circumstances
- Never push directly to `main`
- Always verify the local branch is up to date before operations
