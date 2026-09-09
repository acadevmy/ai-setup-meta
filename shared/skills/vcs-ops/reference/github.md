# GitHub — the `gh` commands

Read this after `git remote get-url origin` has shown a GitHub host. The
conventions (branch names, commit format, PR body) are in `SKILL.md`; this file
is only the commands.

## Prerequisites

- `gh` installed and authenticated (`gh auth login`).
- `git` configured with `user.name` and `user.email`.

On GitHub Enterprise with an ambiguous hostname, `gh auth status --hostname <host>`
succeeding is the signal that this is the right reference.

## Branch

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||')
git checkout "$BASE" && git pull --ff-only
git checkout -b feat/DE-123-add-user-auth
```

## Pull request

```bash
gh pr create \
  --base "$BASE" \
  --head "$(git branch --show-current)" \
  --title "feat(auth): add refresh token rotation [DE-123]" \
  --body-file /path/to/body.md
```

Prefer `--body-file` over `--body`: a body passed inline loses its newlines the
moment it contains backticks or a `$`, and the PR arrives as one paragraph.

Add `--label <name>` only with a label this repository defines — `gh label list`
shows them. A label that does not exist makes the whole call fail, so the PR is
not created at all.

Do not pass `--fill`: it replaces the body with the commit log and drops the
What / Why / How to test structure.

## Status

```bash
gh pr view <number> --json state,statusCheckRollup,reviewDecision
gh pr list --state open
gh pr checks <number>          # the CI runs, one line each
```

## Tag and release

```bash
git tag -a v1.2.0 -m "v1.2.0"
git push origin v1.2.0
gh release create v1.2.0 --title "v1.2.0" --notes-file CHANGELOG-extract.md
```

On a repository driven by release-please, do none of this by hand: merging the
release PR creates the tag and the release.
