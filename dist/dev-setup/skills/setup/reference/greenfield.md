# GREENFIELD mode — pick a stack, then scaffold it

Steps 2b and 8 of the procedure, for an empty or just-initialized project. An
EXISTING run never reads this file, and a GREENFIELD run never reads
`existing.md`.

## Index

- [Step 2b — Stack selection](#step-2b--stack-selection)
- [Step 8 — Scaffold the project](#step-8--scaffold-the-project)
- [Step 9 — Summary for GREENFIELD](#step-9--summary-for-greenfield)

---

## Step 2b — Stack selection

Ask the developer to pick the stack:

1. **Web Frontend** — Next.js / Angular / React + ShadCN/UI + Tailwind
2. **Backend Node** — Node.js / NestJS + Prisma + Zod
3. **Mobile** — Flutter / React Native (Expo)
4. **Full-stack** — Frontend + Backend (monorepo)
5. **Infrastructure / Terraform** — HCL, remote state (S3 default), AWS/Azure/GCP

If they pick **Mobile**, also ask: **Flutter** or **React Native (Expo)**.

If they pick **Infrastructure / Terraform**: set `LANG=terraform`,
`HAS_INFRA=true`. **Important**: Step 8 does **not** apply Terraform-specific
boilerplate in this version (no auto-generated Terraform `.gitignore`, no
auto-emitted Terraform CI workflow, no `versions.tf` scaffold). The
`terraform.md` profile carries the CI recipes and the S3 backend as reference
text to copy. Report this limitation in the summary.

### What the choice decides downstream

The project has no code yet, so `detect-stack.sh` finds nothing: the stack
picked here is the input for everything that follows. Carry it forward as the
equivalent detection values —

| Stack | `LANG` | `FRAMEWORKS` | `HAS_FRONTEND` | `HAS_MOBILE` | `HAS_INFRA` |
|---|---|---|---|---|---|
| Web Frontend | `node` | `nextjs` \| `angular` \| `react` | `true` | `false` | `false` |
| Backend Node | `node` | `nestjs` | `false` | `false` | `false` |
| Mobile (Flutter) | `dart` | `flutter` | `false` | `true` | `false` |
| Mobile (Expo) | `node` | `expo`, `react-native` | `false` | `true` | `false` |
| Full-stack | `node` | both of the above | `true` | `false` | `false` |
| Infrastructure | `terraform` | — | `false` | `false` | `true` |

— because `rules-generation.md` selects the rules from those keys, and on a
greenfield project it has nothing else to go on.

---

## Step 8 — Scaffold the project

Runs **only** in GREENFIELD mode.

### 8.1 — Prerequisites

Verify that `node` (**v24+**), `npm` and `git` are installed. If any is missing,
tell the developer and stop.

Node 24 is the real minimum, not a preference: `semantic-release@25` requires
`^22.14.0 || >=24.10.0`, `lint-staged@17` requires `>=22.22.1`, `eslint@9`
requires `^20.19.0 || ^22.13.0 || >=24`. Node 20 has been EOL since 2026-04-30.

### 8.2 — Initialize the project

```bash
npm init -y   # only if package.json does not exist
git init      # only if .git does not exist
```

### 8.3 — Install quality tools

```bash
npm install --save-dev husky lint-staged @commitlint/cli @commitlint/config-conventional \
  prettier 'eslint@^9.39.0' '@eslint/js@^9.39.0' typescript-eslint globals typescript
```

**Do not install `eslint` without a pin**: `latest` is 10.x, and the frontend
profiles' plugins (`eslint-plugin-react`, `eslint-plugin-jsx-a11y`,
`eslint-plugin-import`) declare `eslint: ^9` as their peer ceiling — on 10 the
install fails with `ERESOLVE`.

`typescript-eslint` (the single package) replaces the
`@typescript-eslint/eslint-plugin` + `@typescript-eslint/parser` pair: it is the
form flat config expects.

Initialize Husky and create the git hooks:

```bash
npx husky init
```

**`.husky/pre-commit`**:

```bash
npx lint-staged
```

**`.husky/commit-msg`**:

```bash
npx --no -- commitlint --edit "$1"
```

Make them executable:

```bash
chmod +x .husky/pre-commit .husky/commit-msg
```

### 8.4 — Quality configuration

Copy the files from the boilerplate distributed with the skill
(`${CLAUDE_SKILL_DIR}/templates/boilerplate/`) — do not rewrite them by hand:
copying is the only form that stays aligned with the template.

| Source in the boilerplate | Destination in the project | Condition |
|---|---|---|
| `.commitlintrc.json` | `.commitlintrc.json` | always |
| `.lintstagedrc.json` | `.lintstagedrc.json` | always (the 8.3 husky hooks call `npx lint-staged`) |
| `eslint.config.base.mjs` | `eslint.config.base.mjs` | always |
| `.prettierrc.json` | `.prettierrc.json` | stacks **without** Tailwind |
| `.prettierrc.tailwind.json` | `.prettierrc.json` | stacks **with** Tailwind (web-frontend, mobile RN) |
| `.releaserc.github.json` | `.releaserc.json` | `vcs = github` |
| `.releaserc.gitlab.json` | `.releaserc.json` | `vcs = gitlab` |

On `vcs = none` / `other`, **skip** `.releaserc.json`: there is no provider to
publish releases to. The two `.releaserc.*` files differ only in the last plugin
(`@semantic-release/github` vs `@semantic-release/gitlab`).

`.prettierrc.tailwind.json` is identical to the base variant plus
`plugins: ["prettier-plugin-tailwindcss"]`. Copy it **only** if the profile
installs `prettier-plugin-tailwindcss`: without the plugin installed, Prettier
errors out on every run.

`eslint.config.base.mjs` is the shared base in **flat config**. The file ESLint
actually reads is `eslint.config.mjs`, which 8.5 creates from the profile by
importing the base. If the stack has no profile with an ESLint config, create an
`eslint.config.mjs` that just re-exports the base:

```javascript
// eslint.config.mjs
import base from './eslint.config.base.mjs';

export default base;
```

### 8.4b — npm scripts

Without these scripts, `npm run lint`, the husky hooks and the boilerplate CI
fail with *Missing script*:

```bash
npm pkg set \
  scripts.lint="eslint ." \
  scripts.lint:fix="eslint . --fix" \
  scripts.format="prettier --write ." \
  scripts.typecheck="tsc --noEmit" \
  scripts.test="jest" \
  scripts.test:cov="jest --coverage" \
  scripts.prepare="husky"
```

Adapt `test`/`test:cov` to the profile's runner (`vitest` / `vitest --coverage`,
`flutter test` on Flutter) and `typecheck` to the stack: these are the three
commands the boilerplate CI runs as its quality gate.

### 8.5 — Apply the stack profile

Read the profile from `${CLAUDE_SKILL_DIR}/templates/profiles/` (already read at
3.1) and apply what it contains.

**Flutter** (`pubspec.yaml` present, or selected here):

1. **Dependencies**: update `pubspec.yaml` with the profile's packages
   (`freezed_annotation`, `json_annotation`, `riverpod`/`flutter_bloc`, `dio`, …)
2. **Dev dependencies**: `build_runner`, `freezed`, `json_serializable`,
   `flutter_lints`, `riverpod_generator` (if using Riverpod codegen)
3. **Linting**: create/update `analysis_options.yaml` including
   `package:flutter_lints/flutter.yaml`
4. **Code generation**: `dart run build_runner build --delete-conflicting-outputs`
5. **Quality gate**: `dart format .`, `dart analyze`, `flutter test`

**React Native (Expo)** and every other Node stack:

1. **Dependencies**: extract the JSON dependency block from the profile and
   install it with `npm install`
2. **ESLint**: if the profile carries an ESLint configuration, create
   `eslint.config.mjs` with that content (flat config — it imports
   `./eslint.config.base.mjs`, copied at 8.4)
3. **TypeScript**: if the profile carries a TypeScript configuration, create
   `tsconfig.json`
4. **Jest**: if the profile carries a Jest configuration, create
   `jest.config.mjs` — **not** `.ts`: Jest does not parse a TypeScript config
   without `ts-node` installed

**Full-stack** (multi-project):

- create the `apps/web/` and `apps/api/` structure
- apply the web-frontend profile in `apps/web/`, the backend-node profile in
  `apps/api/`
- generate `AGENTS.md`, `CLAUDE.md` and `REGISTRY.md` per sub-project, and the
  workspace template at the root (see `agents-generation.md`)

### 8.6 — CI/CD workflow

Pick the CI template from the `{VCS}` detected at Step 2c.

- `vcs = github` → copy **both** workflows from
  `${CLAUDE_SKILL_DIR}/templates/boilerplate/.github/workflows/` into
  `.github/workflows/` (create the directory if missing): `ci.yml` (quality gate
  on every PR) and `release.yml` (quality gate + semantic-release on the default
  branch). The release requires the `GITHUB_TOKEN` secret, provided by default
  by GitHub Actions.
- `vcs = gitlab` → copy
  `${CLAUDE_SKILL_DIR}/templates/boilerplate/.gitlab-ci.yml` to `.gitlab-ci.yml`
  in the project root. It contains the `test` stage (which runs on MR pipelines
  and on the default branch) and the `release` stage. It requires a CI/CD
  variable `GITLAB_TOKEN` with scope `api` + `write_repository` (Settings →
  CI/CD → Variables).
- `vcs = none` / `other` → **skip**. Tell the developer they can add a CI
  workflow for whichever provider they prefer.

Both templates run on **Node 24** and execute the same steps: `npm ci`,
`npm run lint`, `npm run typecheck`, `npm run test:cov` and — only on the default
branch and only if the quality gate is green — `npx semantic-release`. Commits
with `[skip ci]` are bypassed.

The quality gate depends on the npm scripts from 8.4b: if they are missing, CI
fails with *Missing script*.

### 8.7 — .gitignore

If `.gitignore` does not exist, create it with:

```
# Dependencies
node_modules/
.pnp
.pnp.js

# Build
dist/
build/
.next/
out/

# Environment
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Testing
coverage/

# Misc
*.log
npm-debug.log*
```

---

## Step 9 — Summary for GREENFIELD

```
Setup complete!

Project configuration:
  - CLAUDE.md               — entry point for Claude Code (imports AGENTS.md)
  - AGENTS.md               — instructions for AI agents (cross-tool standard)
  - .claude/rules/          — path-scoped governance rules (dev-setup-*.md)
  - REGISTRY.md             — feature and service registry
  - .claude/settings.json   — project permissions + Bash sandbox
  - .husky/                 — git hooks (lint + commit)
  - .lintstagedrc.json      — lint-staged (used by the pre-commit hook)
  - eslint.config.base.mjs  — ESLint base (flat config)
  - eslint.config.mjs       — ESLint <stack> profile (imports the base)
  - .prettierrc.json        — Prettier (Tailwind variant if the stack uses it)
  - .commitlintrc.json      — Conventional Commits
  - .releaserc.json         — semantic-release (<github|gitlab> variant)
  - <CI config>             — .github/workflows/{ci,release}.yml (GitHub) or .gitlab-ci.yml (GitLab)
  - .env.example            — environment variables
  - package.json scripts    — lint, lint:fix, format, typecheck, test, test:cov

Available commands (provided by the plugin):
  - /dev-setup:sdd         — interactive SDD (spec → approval → development, with checkpoints)
  - /dev-setup:auto-sdd    — autonomous end-to-end SDD (up to the PR, no human input)
  - /dev-setup:review      — code review against the project rules

Detected VCS: <github|gitlab|none|other>
Infrastructure: <yes|no>

Next steps:
  1. Copy .env.example to .env and fill in the variables
  2. Check MCP: claude mcp list
  3. Use /dev-setup:sdd (interactive) or /dev-setup:auto-sdd (autonomous) to get started!
```

Add the one-line reports collected along the way (3.3, 3.4, 3.5, 3.6, and the
ones `rules-generation.md` and `mcp-env.md` ask for), plus whatever the step-7b
branch protection reported.

**Terraform note**: if the chosen stack is **Infrastructure / Terraform**, Step 8
generated no Terraform boilerplate. The developer must create `main.tf`,
`variables.tf`, `outputs.tf`, `terraform.tf` (or `versions.tf`) and the
`backend "s3"` block following the recipes in `profiles/terraform.md`. Append:

```
  [Terraform GREENFIELD] The plugin did NOT generate Terraform boilerplate.
                         See profiles/terraform.md for the recommended structure and the CI recipes.
```
