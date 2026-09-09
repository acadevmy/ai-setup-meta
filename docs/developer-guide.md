# Developer guide — from setup to your first task

A practical guide for a developer who has already installed the `dev-setup` plugin and
wants to start working with the AI-native workflow.

> **Prerequisite**: having run `/dev-setup:setup` in the project root.

---

## 1. Workflow overview

The day-to-day flow follows this cycle:

```
Task on ClickUp (SPRINT)
       │
       ▼
/dev-setup:sdd DE-123          ← interactive flow (recommended)
  → creates the branch feat/DE-123-description (sdd-start.sh resolves the base)
  → moves the task to IN PROGRESS
  → discovery + technical spec + your approval  ← the one checkpoint
       │
       ▼
Development driven by the spec
  → backend: TDD cycle (Red → Green → Refactor)
  → frontend: BDD cycle (Given/When/Then)
       │
       ▼
Closure, in this order
  → simplify, verify against the spec, review + REGISTRY
  → one commit: code + spec + REGISTRY, with the gate running here
       │
       ▼
Push + Pull Request  ← the confirmation prompt is the checkpoint
       │
       ▼
The sdd flow moves the task to IN REVIEW and posts the PR link
       │
       ▼
Merge → semantic-release (greenfield projects)
```

> **A fix or a chore does not need any of that.** At most three files, and no new
> component, dependency or public interface → `/dev-setup:quick DE-123` (a plain
> description works too, with no ticket): branch, change, commit behind the gate,
> PR. Zero discovery, zero spec. Anything larger goes through `sdd`, whose spec is
> what a reviewer reads the diff against. Claude may say a task looks misrouted;
> the choice is yours, and the command you type is the choice.

> Alternatively, `/dev-setup:auto-sdd DE-123` runs the whole thing as a background
> workflow — spec, three adversarial reviews of it, development in its own
> worktree, the real test suite — and comes back with the PR ready for your
> confirmation, or with the objections that stopped it.

> **Two tasks at once?** One worktree each: `claude --worktree DE-123` in one
> terminal, `claude --worktree DE-124` in another. The setup installs
> `.worktreeinclude` so `.env` follows you in, and
> `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-info.sh` gives each worktree a
> different dev-server port and warns when two of them declare the same file.

---

## 2. Quick configuration checklist

Before you start, check that everything is in place:

```bash
# Claude Code installed and working
claude --version

# Authenticated against the project's provider
gh auth status     # for GitHub repos
glab auth status   # for GitLab repos (add --hostname <host> when self-hosted)

# MCP servers connected (only the ones setup registered for this stack)
claude mcp list

# AGENTS.md, CLAUDE.md and the generated rules present in the project
ls AGENTS.md CLAUDE.md .claude/rules/
```

If something is missing, run `/dev-setup:setup` again in the project root.

---

## 3. Starting your first task

### 3.1 Pick a task from ClickUp

Open Claude Code in your project root:

```bash
claude
```

Then start the interactive SDD flow with the ClickUp task id:

```
/dev-setup:sdd DE-123
```

Claude Code:
1. Fetches the task details from ClickUp (title, description, acceptance criteria)
2. Creates the branch following the convention: `feat/DE-123-short-description`
3. Moves the ClickUp task to **IN PROGRESS**
4. Runs an interactive discovery, generates the technical spec and puts it in front of
   you for approval before any development starts

> **No id?** You can run `/dev-setup:sdd` with no arguments — Claude Code will show you
> the tasks assigned to you in the current sprint.

> **Fully autonomous?** `/dev-setup:auto-sdd DE-123` runs spec → challenge → dev →
> verify as a workflow, with no interview and no approval turn. Two checkpoints
> survive on purpose: it stops by itself when two of three reviewers refuse the
> spec, and the PR still waits for your confirmation. Best on well-defined tasks —
> a vague one comes back as `needs-human` with the reasons.

### 3.2 Develop with TDD or BDD

There is nothing to type here: the cycle is part of development, and the layer
you are on decides which one it is — `.claude/rules/dev-setup-tests.md` is where
that is written down, and it loads by itself when you open a test file.

| Layer | Methodology | Minimum coverage |
|---|---|---|
| Backend (services, utils) | TDD — Red/Green/Refactor | 80% services, 90% utils |
| Frontend (UI components) | BDD — Given/When/Then | 70% components |
| Controllers/API | TDD | 60% controllers |

**TDD, on a backend service.** Inside `/dev-setup:sdd`, development runs one
plan step at a time:

1. **RED** — the failing test first, describing the expected behaviour
2. **GREEN** — the minimum code that makes it pass
3. **REFACTOR** — improve it while the tests stay green

It runs the plan through without stopping: the plan was approved as a whole, and
a per-step confirmation was a second approval wearing a different hat. A step
that cannot be carried out as written does stop, and says why.

**BDD, on a frontend component.** The same loop, one level up:

1. **Scenario** — Given/When/Then in plain language
2. **Test** — the test with Testing Library
3. **Implementation** — the component that satisfies the scenario

Both cycles live in one place, `sdd-dev/reference/methodologies.md`, read by
whoever is writing the code: the `sdd-dev` skill in the interactive flow, the dev
agent in the `auto-sdd` workflow. (The `/dev-setup:tdd` and `/dev-setup:bdd`
commands were removed in v3: they restated that file, and nothing in the flow
ever called them.)

### 3.3 Write atomic commits

Every commit follows **Conventional Commits** and carries the task id:

```
feat(auth): add JWT token validation [DE-123]
fix(users): handle empty email in registration [DE-123]
test(auth): add integration tests for login flow [DE-123]
refactor(auth): extract token service from controller [DE-123]
```

Inside the `sdd` flow you get one commit per task, made at the end, after
simplify, verify and review — the three bookkeeping commits the flow used to add
(`refactor: simplify`, `docs(registry)`, `docs(spec)`) are gone. Committing more
often while you work is fine; nothing requires it.

The git hooks (configured by the setup skill) validate automatically:
- **commitlint** — the commit message format
- **prettier** — code formatting
- **eslint** — code quality

If a hook fails, fix the problem and commit again. Never use `--no-verify`.

### 3.4 Run the review

Once you have finished developing:

```
/dev-setup:review
```

Claude Code:
1. Checks compliance with the **project rules** in `.claude/rules/`
2. Reviews code quality (duplication, complexity, security)
3. Updates **REGISTRY.md** with the new components/services/patterns

Inside `/dev-setup:sdd` this runs before the commit, together with `simplify` and
the spec check, so one commit carries the code and everything the gates produced.
Invoked on its own it changes `REGISTRY.md` in your working tree and commits
nothing — you decide which commit takes it.

### 3.5 Push and open the MR/PR

```bash
git push -u origin feat/DE-123-short-description

# On GitHub
gh pr create

# On GitLab (setup detects the provider and uses the right skill)
glab mr create --source-branch feat/DE-123-short-description \
               --target-branch <default-branch> \
               --title "..." --description "..."
```

The two flows (`/dev-setup:sdd`, `/dev-setup:auto-sdd`) call the right VCS skill
(`vcs-ops`, which picks its GitHub or GitLab reference) based on the `origin` remote. On GitLab, the MR body follows
`.gitlab/merge_request_templates/Default.md` when the repo has one.

The MR/PR must have:
- **Title**: Conventional Commits format (`feat(scope): description`)
- **Description**: What / Why / How to test (or the repo's MR template, on GitLab)
- **At least 1 approving review** before the merge
- **Green tests** in CI

### 3.6 Keep the task in sync

The `sdd` and `auto-sdd` flows update ClickUp themselves once the PR is open: they move the
task to the review status and post the PR link as a comment. An `auto-sdd` run that
stopped instead moves the task to `BLOCKED`, with the objections or the failing
output in the note — move it back to `SPRINT` once you have answered them. If you opened the PR by hand,
ask Claude Code to update the task, or move it on the board yourself.

---

## 4. Core rules

These rules come from `.claude/rules/` — they are mandatory for all code, whether you
wrote it or Claude Code did.

### TypeScript

- `strict: true` always on — no `any`, ever
- Validate all external data with **Zod** (schema-first)
- Pure functions, 40 lines at most, one responsibility
- Named constants: no magic numbers or magic strings

### Architecture

- Layer separation: **Controller → Service → Repository**
- No shortcuts (the controller never talks to the DB directly)
- Dependency Injection: never `new` a heavy dependency inside a function

### Naming

| Kind | Convention | Example |
|---|---|---|
| Variables and functions | camelCase | `getUserById` |
| Classes and interfaces | PascalCase | `UserService` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |

### Security

- **Zero secrets in the code** — only `.env` (gitignored)
- Validate every input with Zod and sanitise it before it reaches a DB or a template
- `npm audit` every time you add a dependency

### Git

- **Never push straight to main** — always a branch and a PR
- **Atomic commits** — one logical change per commit
- **Conventional Commits** are mandatory, with the task id

---

## 5. Slash commands — quick reference

| Command | When to use it |
|---|---|
| `/dev-setup:quick [ID \| description]` | A fix or chore: ≤3 files, no new component, dependency or public interface. Branch → change → commit → PR, no spec |
| `/dev-setup:sdd [ID] [--worktree]` | Interactive SDD flow on a ClickUp task (spec → your approval → development). Anything above the `quick` bar |
| `/dev-setup:auto-sdd [ID]` | Autonomous SDD as a workflow: spec, three challenges, worktree, real tests — PR behind your confirmation |
| `/dev-setup:review` | Code review before opening the PR |

---

## 6. Troubleshooting

### The git hooks reject my commit

Do not use `--no-verify`. Read the error and fix it:
- **commitlint**: the message does not follow Conventional Commits
- **prettier**: the code is not formatted — save the file and try again
- **eslint**: there are errors in the code — fix them before committing

### ClickUp does not respond

On first use, ClickUp opens the browser for OAuth authentication.
If the session has expired, restart Claude Code — the OAuth flow starts again on its own.

### The setup skill does not detect my stack

Make sure the project root holds:
- `package.json` with the dependencies (for Next.js, Angular, React, NestJS)
- `pubspec.yaml` (for Flutter)
- `app.json` with `expo` (for React Native/Expo)

---

## 7. Upgrading the plugin

When a new version of `dev-setup` ships, two distinct actions are needed:

**1. Update the installed plugin** (new skills, agents, boilerplate):

```bash
# In your Claude Code
/plugin update dev-setup@acadevmy
```

That updates the plugin's *bundled* skills, agents and templates — no file in your project is touched.

**2. Reapply the templates to the project** (refresh the governance files):

```
/dev-setup:setup
```

The skill detects **UPDATE** mode (`.claude/rules/dev-setup-core.md` + `.claude/settings.json` already present) and regenerates:

- `.claude/rules/dev-setup-*.md`, `AGENTS.md`, `CLAUDE.md`, `REGISTRY.md`

For each file it asks before overwriting (**conflict detection**). Accepting overwrites the file wholesale — any manual edits to it are lost. Declining keeps the current version.

**What UPDATE does NOT touch**:
- Tooling (git hooks, ESLint, Prettier, CI/CD, `.gitignore`)
- Dependencies, lock files
- Source code, `.env`

**Recommendation**: keep any team customisation out of the regenerated files (in a `TEAM_NOTES.md`, say, or in an extra section of `REGISTRY.md` that you maintain by hand) — that way an upgrade is always a risk-free accept-overwrite.

**Post-upgrade check**:

```bash
# Check that the detected VCS is right
git remote get-url origin

# Check the active VCS skill (it must match the repo's provider)
grep -i 'gh\|glab' AGENTS.md
```

If the project moved from GitHub to GitLab (or the other way round), UPDATE detects the new `origin` and generates the right `{{VCS_OPS_NOTE}}`.

---

## 8. Next steps

Once you have finished your first task:

1. **Explore REGISTRY.md** — to see what has already been built in the project
2. **Read your project's stack profile** in `AGENTS.md` — it holds stack-specific rules
3. **Use `ctx7`** — `AGENTS.md` declares the `ctx7` CLI as the source for up-to-date library
   documentation (`npx ctx7@latest <command>`), so you can ask for precise references
   without looking them up by hand
4. **Figma (optional)** — if the setup registered the Figma MCP, Claude Code can read the
   designs straight from the Figma files and generate components that match them
