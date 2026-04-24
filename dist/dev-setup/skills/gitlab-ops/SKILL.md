---
name: gitlab-ops
description: Reference documentation for Git and GitLab operations (branch, MR, tag, release)
model: haiku
user-invocable: false
disable-model-invocation: false
---

# Skill: GitLab Operations

Git and GitLab operations via `git` and `glab` CLI.
Do NOT use MCP GitLab — always use direct commands.

## Prerequisites
- `glab` CLI **1.40+** installed and authenticated (`glab auth login`)
  - Required for the `--template` flag used below. Older versions must fall back to reading the template file manually and passing it via `--description`.
  - Install hint: `brew install glab` (macOS) or `apt install glab` (Debian/Ubuntu)
- `git` configured with user.name and user.email

## Self-identify (run first)

Before executing any operation, verify the current repository targets GitLab:

```bash
git remote get-url origin | tr 'A-Z' 'a-z'
```

If the URL does **not** contain `gitlab` (and no other signal identifies the host as GitLab), bail with a single-line message:
`gitlab-ops invoked on a non-GitLab repo (origin=<url>) — use github-ops instead.`

For self-hosted GitLab whose host is ambiguous, probe `glab auth status --hostname <host>`; if it succeeds, proceed.

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

Base: the project default branch unless specified otherwise. Detect with
  git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||'
or fall back to listing recent remote branches:
  git branch -r --sort=-committerdate | head -10
```

### Open a Merge Request

```
glab mr create \
  --source-branch <current-branch> \
  --target-branch <default-branch> \
  --title "<title>" \
  [--template <template-name> | --description "<body>"]
```

Required fields:
- `--title`: follows Conventional Commits, includes customId — e.g. `feat(auth): add refresh token rotation [DE-123]`
- `--source-branch`: current branch
- `--target-branch`: default branch of the project (not always `main` — some projects use `next`, `develop`, etc.)
- Either `--template` **or** `--description`: choose by the discovery rule below.

Do **not** use `-f` / `--fill` (fill-from-commit) — parity with `gh pr create` without `--fill`.

### MR template discovery

Unlike the GitLab web UI, `glab mr create` does **not** auto-apply templates from `.gitlab/merge_request_templates/`. You must pass `--template` explicitly. Pick the template name in this order:

1. **`Default.md` wins**: if `.gitlab/merge_request_templates/Default.md` exists, pass `--template Default` (the `.md` extension is optional).
2. **Branch-prefix heuristic** (when no `Default.md`): inspect `.gitlab/merge_request_templates/*.md` and pick:
   - `feat/` → first template whose name matches `feature` (case-insensitive)
   - `fix/` or `hotfix/` → first whose name matches `bug` or `fix`
   - otherwise → the first template alphabetically
   Pass the chosen name via `--template <name>`.
3. **Fallback (no templates directory, or empty)**: skip `--template` and pass `--description` with the minimal body below.

Minimal fallback body:
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

`glab` reads the template file from the local checkout and populates the MR description before opening — nothing to read or paste manually.

### Create a tag and a Release
```
git tag -a <tag> -m "<message>"
git push origin <tag>
glab release create <tag> --name "<title>" --notes "<body from CHANGELOG>"
```

Requires GitLab 16.0+ for `glab release create`. On older instances, push the tag and create the release through the web UI.

### Check MR status
```
glab mr view <number> --output json
glab mr list --state opened
```

## Rules
- Never use `git push --force` under any circumstances
- Never push directly to the project's production/default ref
- Always verify the local branch is up to date before operations
- When opening an MR, always read the repository's own `AGENTS.md` first — team conventions on MR title format, description language, and target branch may differ from the defaults in this skill (e.g. some projects use `next` as the development target and keep `main` for production)
