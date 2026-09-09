# GitLab — the `glab` commands

Read this after `git remote get-url origin` has shown a GitLab host. The
conventions (branch names, commit format, MR body) are in `SKILL.md`; this file
is only the commands, plus the one thing GitLab does differently — MR templates.

## Prerequisites

- `glab` **1.40+**, authenticated (`glab auth login`). 1.40 is where `--template`
  landed; on an older build, read the template file yourself and pass its content
  through `--description`.
  Install: `brew install glab` (macOS), `apt install glab` (Debian/Ubuntu).
- `git` configured with `user.name` and `user.email`.

On self-hosted GitLab with an ambiguous hostname, `glab auth status --hostname <host>`
succeeding is the signal that this is the right reference.

## Branch

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||')
git checkout "$BASE" && git pull --ff-only
git checkout -b feat/DE-123-add-user-auth
```

If `origin/HEAD` is not set locally, `git branch -r --sort=-committerdate | head`
shows which long-lived branches the project actually uses — several use `next` or
`develop` as the target and keep `main` for production.

## Merge request

```bash
glab mr create \
  --source-branch "$(git branch --show-current)" \
  --target-branch "$BASE" \
  --title "feat(auth): add refresh token rotation [DE-123]" \
  --template Default            # or: --description "<body>"
```

Do not pass `-f` / `--fill`: it replaces the body with the commit log.

### Template discovery

Unlike the web UI, `glab mr create` does **not** apply
`.gitlab/merge_request_templates/` on its own — you have to name the template.
Pick it in this order:

1. `Default.md` exists → `--template Default` (the extension is optional).
2. No `Default.md` → match the branch prefix against the template names:
   `feat/` → the first matching `feature`, `fix/` or `hotfix/` → the first
   matching `bug` or `fix`, otherwise the first alphabetically.
3. No templates directory, or empty → drop `--template` and pass the SKILL.md
   body through `--description`.

`glab` reads the template out of the local checkout and fills the description
before opening the MR: nothing to paste by hand.

Add `--label <name>` only with a label the project defines — `glab label list`
shows them.

## Status

```bash
glab mr view <number> --output json
glab mr list --state opened
glab ci status
```

## Tag and release

```bash
git tag -a v1.2.0 -m "v1.2.0"
git push origin v1.2.0
glab release create v1.2.0 --name "v1.2.0" --notes-file CHANGELOG-extract.md
```

`glab release create` needs GitLab 16.0+. On an older instance, push the tag and
create the release from the web UI.
