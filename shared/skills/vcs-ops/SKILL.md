---
name: vcs-ops
description: Branch, commit, pull/merge request, tag and release conventions, and the git/gh/glab commands that carry them out. Use when creating a branch, writing a commit message, opening or checking a PR or MR, or cutting a release.
user-invocable: false
disable-model-invocation: false
---

# VCS operations

Everything runs through `git` plus the host CLI — `gh` on GitHub, `glab` on
GitLab. Not the GitHub or GitLab MCP servers: the CLIs read the token from the
environment, so it never lands on a command line or in a log. `git` needs
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
quirks. Everything below is the same on both hosts.

## Branch

```
<type>(<context>)/<TASK-ID>_<short-description>
```

`feat(auth)/DE-123_add-refresh-token`. `<type>` is `feat`, `fix`, `chore`,
`docs`, `refactor`, `perf` or `test`; `(<context>)` names the area touched and is
dropped when there is no single one; `<TASK-ID>` is the tracker's custom id,
dropped when there is none; the description is short, kebab-case, **English**.

The base is resolved, never guessed — `main` is not always it. The script names
the branch and returns `BASE_BRANCH`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" --type feat --context auth \
  --task DE-123 --title "add refresh token" --create --json
```

## Commits

Conventional Commits; the project's commitlint config enforces it.

```
<type>(<scope>): <description in English, imperative, lowercase>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`,
`ci`, `build`, `revert`. One commit is one coherent change.

## Pull / merge requests

The project decides the shape; `.claude/merge-request.json` (written by the
setup, edited by the team) holds it. Ask the script, never re-derive it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/mr-meta.sh" --summary "<what was done, in LANGUAGE>" \
  [--breaking] [--priority <task priority>] --json
```

- **Title** — `TITLE`: `Feat: Aggiunta rotazione del refresh token [DE-123]`.
  The summary is written in `LANGUAGE`; the commits keep Conventional Commits.
- **Body** — `TEMPLATE`, the repository's own template, **filled in and short**,
  in `LANGUAGE`. Never `--fill`, never the template unfilled.
- **Labels** — `LABELS`, passed as they are. Never invent one.

[reference/merge-request.md](reference/merge-request.md) has the rest: the
brevity rule, the test section, no metadata file, no template.

The repository's `AGENTS.md` wins over every default here.

**A merge request carrying a task id does not end the task**: the board still
says `IN PROGRESS` and its work clock is still running. Close both as
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md` describes, here, even when
no flow sent you.

## Tag and release

```bash
git tag -a v1.2.0 -m "v1.2.0"
git push origin v1.2.0
```

Then the host's release command. Under release-please or semantic-release, none
of this by hand: merging the release PR creates the tag and the release.
