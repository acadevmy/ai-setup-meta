# Operating workflow

A practical guide to how Claude Code works inside the meta-repo, and how the maintainer
deals with it day to day.

> **Scope**: this document describes the workflow for **maintaining the plugin itself**
> (the `ai-setup-meta` meta-repo is hosted on GitHub). End users of the plugin may work on
> GitHub **or** GitLab projects — see [developer-guide.md](./developer-guide.md) for that
> side. The `gh` commands below only concern releasing the plugin.

## Branching

Two long-lived branches, and they have different jobs.

| Branch | Job |
|---|---|
| `next` | **The base branch.** Every feature and fix PR targets it |
| `main` | **The release branch.** release-please watches it and nothing else |

So a change lands on `next`, and `next` reaches `main` when the maintainer wants
a release cut. Opening a PR against `main` is the mistake to watch for: it
bypasses the accumulation `next` exists to provide, and it triggers a release
computation on a change nobody has decided to release.

**Stacked PRs.** When a chain of PRs depends on the one before it, the next
branch starts from **the previous PR's branch**, not from `next` — otherwise it
carries none of the work it builds on and the diff is unreadable. Retarget it
onto `next` once the parent merges. Always branch from the most up-to-date thing
available:

```bash
# The parent PR is merged into next
git checkout next && git pull && git checkout -b feat/DE-124-second-step

# The parent PR is still open
git checkout feat/DE-123-first-step && git checkout -b feat/DE-124-second-step
# …and retarget onto next after the parent merges:
gh pr edit <number> --base next
```

Branch names carry the ClickUp customId: `feat/DE-123-add-user-auth`,
`fix/DE-456-broken-contract`, `chore/sync-constitution-v2` for work with no
ticket.

## The typical life of a change

```
A contributor (human or agent) opens a branch off next (or off the
parent PR's branch, when the chain is stacked)
         │
         ▼
  Edits the sources under templates/, shared/, scripts/
  following the project rules in .claude/rules/ and AGENTS.md
         │
         ▼
  bash scripts/build-plugin.sh dev-setup   — if templates/ or shared/ changed
         │
         ▼
  /project:validate  — static checks on skill, workflow and doc quality
         │
         ▼
  Conventional commit subject (feat:/fix:/feat!:/docs:/…) +
  push the branch + open a PR against next
  - ci.yml runs four jobs, build-verify.yml checks that dist/ is in sync
         │
         ▼
  Review + squash-merge into next (all five jobs green)
         │
         ▼
  next → main, when a release is wanted
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

### The maintainer's commands

These live in the meta-repo, not in the plugin. They are optional: a contributor
can equally well edit the files and run the scripts by hand, because the release
flow depends only on the conventional commits, not on how the changes were
produced.

| Command | What it does |
|---|---|
| `/project:validate` | The static checks on skill, workflow and documentation quality — the same script CI runs |
| `/project:build-plugin` | Builds `dist/` from a template's `manifest.json` |
| `/project:auto-maintain` | One unsupervised maintenance cycle: picks the top ClickUp task, applies it, opens a PR |

See [`AGENTS.md → Available skills`](../AGENTS.md#available-skills) for what each
one does in detail.

## What CI checks

Five jobs, on every PR to `main` or `next` and on every push to those branches.
Nothing lands with one of them red.

| Job | Workflow | Checks |
|---|---|---|
| `plugin-validate` | `ci.yml` | `claude plugin validate --strict` on the built plugin and on the marketplace catalogue |
| `shellcheck` | `ci.yml` | Every `*.sh` under `scripts/`, `templates/`, `dist/`, at `--severity=warning` |
| `static-checks` | `ci.yml` | Manifest references, plus the static checks in `scripts/validate-plugin.sh` |
| `bash-tests` | `ci.yml` | `scripts/test-plugin-scripts.sh`: the plugin scripts and hooks against their fixtures |
| `verify` | `build-verify.yml` | `dist/` is in sync with `templates/`, `shared/` and the build scripts |

**The documentation is one of the things `static-checks` checks.** Every command,
script, path and rule name cited in `README.md`, `AGENTS.md` and `docs/*.md` has
to exist in the repo, and every public command has to be documented in the
developer guide. Docs cannot go stale in silence: renaming a script without
touching the page that names it turns the job red. The one exception is
[migration-v2-to-v3.md](./migration-v2-to-v3.md), whose subject is precisely the
things that no longer exist.

**The baseline.** `scripts/validate-baseline.txt` lists findings that are
reported without failing CI. It has been empty since DE-16478 and the rule is
that it stays that way: a new finding gets fixed, not baselined, and whoever
fixes a baselined defect removes its line in the same PR (`--fail-on-stale`
turns the job red on an orphaned entry). The repo's real state, baseline
ignored: `bash scripts/validate-plugin.sh --strict`.

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

Claude Code is the only build target (DE-16489): the manifest and catalogue for the
other runtimes no longer exist.

### Build verification (PR check)

`build-verify.yml` runs on every PR to `main` or `next` and on every push to
them — no path filter, because the previous one let through direct pushes and
changes outside its list, which are exactly the cases where `dist/` drift
reached a branch without turning the job red:

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

### Adding or changing a rule
```bash
git checkout -b feat/DE-123-new-rule next
# Edit the template under templates/dev-setup/rules/, then:
bash scripts/build-plugin.sh dev-setup
```

Two invariants the static checks enforce: `core.md` stays the only template
without `paths:` frontmatter, and it stays under 150 lines. A rule a machine can
check does not belong here at all — it belongs in ESLint, the test runner or
branch protection. Projects pick a rule change up on the setup's UPDATE run.

### Updating a library's versions
```bash
git checkout -b chore/update-web-stack next
# Edit the profile under templates/dev-setup/profiles/, then:
bash scripts/build-plugin.sh dev-setup
```

### Changing the documentation

The pages under `docs/` and the two root files are checked in CI: a command,
script, path or rule name they cite has to exist, and a public command has to be
cited by the developer guide. So renaming a script means touching the page that
names it, in the same PR.

```bash
bash scripts/validate-plugin.sh --strict     # the docs checks run with the rest
```

### Rebuilding the plugin after a source change
```bash
bash scripts/build-plugin.sh dev-setup
# Check and commit the refreshed contents of dist/dev-setup/
```

### Releasing a new version of the plugin

Nothing explicit is required:

1. Merge your feature/fix PRs into `next` with conventional commits (`feat:`, `fix:`, …).
2. Merge `next` into `main` when you want a release computed. release-please opens or updates a release PR automatically on every push to `main`.
3. When you want to publish, merge the release PR. release-please creates the tag and the GitHub Release on its own.

To force a specific version (an override): add `Release-As: X.Y.Z` to a commit footer.

## Rules for the maintainer

1. **Never work on `main` or `next` directly** — always a branch and a PR
2. **Feature PRs target `next`**, never `main`; `main` is where releases are computed
3. **Read every PR Claude opens** before approving it — the responsibility stays human
4. **Do not approve PRs that touch `templates/*/rules/`** without a careful review
5. **Update `AGENTS.md`** whenever the team's tools, profiles or processes change
6. **Test `/dev-setup:setup`** on a clean project before every minor/major release
7. **Never edit a generated file under `dist/`** — edit the source and rebuild

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
