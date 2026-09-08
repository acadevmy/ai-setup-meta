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
  → creates the branch feat/DE-123-description
  → moves the task to IN PROGRESS
  → discovery + technical spec + approval
       │
       ▼
Development driven by the spec
  → backend: TDD cycle (Red → Green → Refactor)
  → frontend: BDD cycle (Given/When/Then)
       │
       ▼
Commits following Conventional Commits
  feat(auth): add login endpoint [DE-123]
       │
       ▼
/dev-setup:review
  → checks the project rules
  → updates REGISTRY.md
       │
       ▼
Push + Pull Request
       │
       ▼
The sdd flow moves the task to IN REVIEW and posts the PR link
       │
       ▼
Merge → semantic-release (greenfield projects)
```

> Alternatively, `/dev-setup:auto-sdd DE-123` runs the **whole** flow autonomously —
> from discovery to the PR — with no manual checkpoint.

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

> **Fully autonomous?** `/dev-setup:auto-sdd DE-123` runs the same flow end to end
> (discovery → spec → development → review → PR) **without** interactive checkpoints:
> useful for well-defined tasks or unattended runs (CI, batch).

### 3.2 Develop with TDD or BDD

Which cycle you use depends on the layer you are working on:

| Layer | Methodology | Command | Minimum coverage |
|---|---|---|---|
| Backend (services, utils) | TDD — Red/Green/Refactor | `/dev-setup:tdd` | 80% services, 90% utils |
| Frontend (UI components) | BDD — Given/When/Then | `/dev-setup:bdd` | 70% components |
| Controllers/API | TDD | `/dev-setup:tdd` | 60% controllers |

**Example — a TDD cycle for a backend service:**

```
/dev-setup:tdd
```

Claude Code walks you through:

1. **RED** — writes the failing test (describing the expected behaviour)
2. **GREEN** — writes the minimum code that makes the test pass
3. **REFACTOR** — improves the code while keeping the tests green

It asks for confirmation at each step before moving on.

**Example — a BDD cycle for a frontend component:**

```
/dev-setup:bdd
```

Claude Code walks you through:

1. **Scenario** — defines Given/When/Then in plain language
2. **Test** — writes the test with Testing Library
3. **Implementation** — builds the component that satisfies the scenario

### 3.3 Write atomic commits

Every commit follows **Conventional Commits** and carries the task id:

```
feat(auth): add JWT token validation [DE-123]
fix(users): handle empty email in registration [DE-123]
test(auth): add integration tests for login flow [DE-123]
refactor(auth): extract token service from controller [DE-123]
```

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

The workflow skills (`/dev-setup:sdd`, `/dev-setup:auto-sdd`) call the right VCS skill
(`github-ops` or `gitlab-ops`) based on the `origin` remote. On GitLab, the MR body follows
`.gitlab/merge_request_templates/Default.md` when the repo has one.

The MR/PR must have:
- **Title**: Conventional Commits format (`feat(scope): description`)
- **Description**: What / Why / How to test (or the repo's MR template, on GitLab)
- **At least 1 approving review** before the merge
- **Green tests** in CI

### 3.6 Keep the task in sync

The `sdd` and `auto-sdd` flows update ClickUp themselves once the PR is open: they move the
task to the review status and post the PR link as a comment. If you opened the PR by hand,
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
| `/dev-setup:sdd [ID]` | Interactive SDD flow on a ClickUp task (spec → approval → development) |
| `/dev-setup:auto-sdd [ID]` | Autonomous end-to-end SDD flow (up to the PR, no checkpoints) |
| `/dev-setup:sdd-discovery` | Structured interview to gather the requirements before the spec |
| `/dev-setup:tdd` | Backend development with the Red/Green/Refactor cycle |
| `/dev-setup:bdd` | Frontend development with Given/When/Then scenarios |
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
