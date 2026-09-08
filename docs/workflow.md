# Operating workflow

A practical guide to how Claude Code works inside the meta-repo, and how the maintainer
deals with it day to day.

> **Scope**: this document describes the workflow for **maintaining the plugin itself**
> (the `ai-setup-meta` meta-repo is hosted on GitHub). End users of the plugin may work on
> GitHub **or** GitLab projects — see [developer-guide.md](./developer-guide.md) for that
> side. The `gh` commands below only concern releasing the plugin.

## The typical life of a change

```
A contributor (human or agent) opens a branch on feat/<scope>
         │
         ▼
  Edits the sources under templates/, shared/, scripts/
  following the rules in CONSTITUTION.md and AGENTS.md
         │
         ▼
  /project:validate  — static checks on skill quality
         │
         ▼
  Conventional commit subject (feat:/fix:/feat!:/docs:/…) +
  push the branch + open a PR
  - build-verify.yml checks that dist/ is in sync
         │
         ▼
  Review + squash-merge into main (build-verify green)
         │
         ▼
  release-please.yml runs automatically on push to main:
  - parses the conventional commits since the last dev-setup-v* tag
  - computes the bump type (major/minor/patch) or nothing (for docs:/chore:/…)
  - if there are relevant commits, opens or updates a running "release PR":
      - bumps the version in templates/dev-setup/.env.example (x-release-please-version marker)
      - bumps the version in dist/dev-setup/.claude-plugin/plugin.json
      - updates .release-please-manifest.json
      - generates or updates the "## [X.Y.Z]" section in templates/dev-setup/CHANGELOG.md
        (grouped by Features / Bug Fixes / Documentation / …)
         │
         ▼
  The maintainer reviews the release PR (they can wait for several feature
  PRs to pile up — release-please updates the PR on every push to main)
         │
         ▼
  The release PR is merged into main
         │
         ▼
  release-please.yml again:
  - annotated tag dev-setup-vX.Y.Z
  - a GitHub Release whose body is the diff of the CHANGELOG section
  - rebuilds dist/ and commits it ("chore(dist): rebuild after release …")
```

> **A note on the helper skills**: the `/project:*` skills are **optional** meta-repo tools (they live in `.claude/skills/`). They are not part of CI. They exist so a contributor can make guided changes (for example updating the CONSTITUTION while keeping the root and the template coherent). A contributor can equally well edit the files by hand — the release flow depends only on the conventional commits, not on how the changes were produced. See [`AGENTS.md → Available skills`](../AGENTS.md#available-skills) for the full list and what each one does.

## How the release works

The release flow uses [release-please](https://github.com/googleapis/release-please) (Google's official, battle-tested action). On every push to `main` the action reads the conventional commits since the last tag and:

- Opens or updates a running "release PR" with the version bump and a generated CHANGELOG
- On merging that release PR, creates the annotated tag and the GitHub Release

No direct push to `main`, no manual trigger, no custom bash. Two workflows:

1. **`release-please.yml`** — runs on every push to `main`. Action: `googleapis/release-please-action@v4`.
2. **`build-verify.yml`** — runs on every PR. Checks that `dist/` is in sync with the source.

### release-please configuration

- **`release-please-config.json`** (root) — defines the package, the `extra-files` to bump and the CHANGELOG path. Single-package mode with the root as scope.
- **`.release-please-manifest.json`** (root) — the current version. release-please updates it automatically; do not edit it by hand.

The `extra-files` configured for the version bump:

- `templates/dev-setup/.env.example` — recognised through the `# x-release-please-version` marker comment
- `dist/dev-setup/skills/setup/templates/.env.example` — the copy the build places under `dist/` (same marker)
- `dist/dev-setup/.claude-plugin/plugin.json` — JSON path `$.version`
- `.claude-plugin/marketplace.json` — JSON path `$.plugins[?(@.name == 'dev-setup')].version`

Every generated file carrying the version has to be on this list: a release PR that bumps only some of them is born out of sync with a rebuild, and the `dist/` drift check goes red on the release PR itself.

Claude Code is the only build target (DE-16489): the `.cursor-plugin/` manifest and catalogue no longer exist.

### Build verification (PR check)

`build-verify.yml` runs on every PR that touches `templates/`, `shared/`, `scripts/builders/`, the marketplace files, or `dist/`:

- Runs `bash scripts/build-plugin.sh <template>`
- Fails if `git diff` finds any difference against the committed `dist/`

It catches the case where someone edits `templates/` and forgets to rebuild `dist/`.

### Overriding the bump type by hand

release-please lets you force the release type with a "release-as" footer in a commit:

```
feat(profile): add some feature

Release-As: 2.0.0
```

Alternatively you can write `release-please-action`-style annotations (see the [official docs](https://github.com/googleapis/release-please#how-do-i-change-the-version-number)).

## Common operations

### Adding a rule to the Constitution
```bash
git checkout -b feat/constitution-new-rule
# Edit templates/dev-setup/CONSTITUTION.md, then:
bash scripts/build-plugin.sh dev-setup
```

### Updating a library's versions
```bash
git checkout -b chore/update-web-stack
# Edit the profile under templates/dev-setup/profiles/, then:
bash scripts/build-plugin.sh dev-setup
```

### Rebuilding the plugin after a source change
```bash
bash scripts/build-plugin.sh dev-setup
# Check and commit the refreshed contents of dist/dev-setup/
```

### Releasing a new version of the plugin

Nothing explicit is required:

1. Merge your feature/fix PRs with conventional commits (`feat:`, `fix:`, …). release-please opens or updates a release PR automatically on every push to `main`.
2. When you want to publish, merge the release PR. release-please creates the tag and the GitHub Release on its own.

To force a specific version (an override): add `Release-As: X.Y.Z` to a commit footer.

## Rules for the maintainer

1. **Never work on `main` directly** — always a branch and a PR
2. **Read every PR Claude opens** before approving it — the responsibility stays human
3. **Do not approve PRs that touch `CONSTITUTION.md`** without a careful review
4. **Update `AGENTS.md`** whenever the team's tools, profiles or processes change
5. **Test `/dev-setup:setup`** on a clean project before every minor/major release
6. **Never edit the template repo directly** — always go through the meta-repo

## Handling Claude Code mistakes

If Claude Code does something unexpected:

1. **Do not merge the PR** — close it without merging
2. Work out what went wrong in `AGENTS.md` or in the slash commands
3. Fix the instructions and try again
4. If the problem keeps coming back, open a PR to improve the prompt

## Recommended branch protection (GitHub Settings)

- Require a pull request before merging
- Require approvals: 1
- Dismiss stale pull request approvals when new commits are pushed
- Require status checks to pass (once the GitHub Actions are configured)
- Do not allow bypassing the above settings
