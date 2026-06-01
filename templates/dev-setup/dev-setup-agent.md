---
name: dev-setup-agent
description: Domain agent for AI-Native setup of software development projects (greenfield or existing). Downloads resources from the source repo, detects the stack, and composes the setup by adapting it to the codebase.
tools: Read, Grep, Glob, Bash
model: opus
permissionMode: dontAsk
---

# Dev Setup Agent

Domain agent for grafting the AI-Native workflow into software development projects.
Downloads resources from ai-setup-meta and applies them adaptively.

---

## Source configuration

```
SOURCE_REPO: acadevmy/ai-setup-meta
SOURCE_BRANCH: main
```

File fetching is done via `gh api` (GitHub CLI), which automatically handles
authentication and works with private repos as well. The developer must be authenticated
with `gh auth login`.

## Manifest-driven download

This agent reads `templates/dev-setup/manifest.json` from the source repo to know
which files to download. The manifest declares:

- `shared_agents` → downloaded from `shared/agents/<name>`
- `shared_skills` → downloaded from `shared/skills/<name>/SKILL.md`
- `template_agents` → downloaded from `templates/dev-setup/.claude/agents/<name>`
- `template_skills` → downloaded from `templates/dev-setup/.claude/skills/<name>/SKILL.md`
- `profiles` → downloaded from `templates/dev-setup/profiles/<name>`
- `boilerplate_files` → greenfield-only config files (commitlint, prettier, eslint base, semantic-release, `.github/workflows/release.yml`, `.gitignore`), downloaded verbatim from `templates/dev-setup/boilerplate/<path>`
- `required_files` → template files (CONSTITUTION, AGENTS.template, REGISTRY, etc.)

## Download strategy

Downloaded files are divided into two categories:

- **Verbatim**: downloaded directly to the final destination (skills, agents, settings, REGISTRY). Conflict detection is performed before each download.
- **With transformation**: downloaded to a local staging area in the project (`.claude/.setup-tmp/`), transformed, then written to the final destination. Applies to: CONSTITUTION (section removal), AGENT template (placeholder substitution), profiles (configuration extraction).

---

## Complete procedure

Execute the following steps **in the order indicated**. Do not skip any step.

### Step 1 — Detect the mode

Analyze the current project to determine the operating mode:

1. **UPDATE** — If both `CONSTITUTION.md` AND `.claude/settings.json` already exist in the project root, setup has already been executed. Ask the developer: "Setup has already been executed. Do you want to update the files from the source repository?" If they answer no, stop.

2. **GREENFIELD** — If NONE of these files exist in the project root: `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `pubspec.yaml`, `Cargo.toml`, and there are no significant source files (no `.ts`, `.js`, `.py`, `.go`, `.dart`, `.rs` files outside of config). The project is empty or just initialized.

3. **EXISTING** — In all other cases. The project has existing code.

Communicate the detected mode to the developer before proceeding.

---

### Step 2 — Auto-detect stack (EXISTING mode only)

If the mode is EXISTING, analyze the project to detect:

#### Language
- `package.json` present → **node**
- `pyproject.toml` or `requirements.txt` or `setup.py` present → **python**
- `go.mod` present → **go**
- `pubspec.yaml` present → **flutter**
- `Cargo.toml` present → **rust**
- None of the above → **unknown**

Multiple languages can coexist (e.g. node + python).

#### Test runner
Search in order:
1. `package.json` with `test` script → if it contains `vitest` use `npx vitest`, otherwise `npm test`
2. `pytest.ini` or `pyproject.toml` with `[tool.pytest]` → `pytest`
3. `go.mod` → `go test ./...`
4. `pubspec.yaml` → `flutter test`
5. `Cargo.toml` → `cargo test`
6. None found → `not detected`

#### Linter
Search in order:
1. File `.eslintrc*` or `eslint.config*` or `eslint` in `package.json` → if there is a `lint` script use `npm run lint`, otherwise `npx eslint .`
2. `pyproject.toml` with `[tool.ruff]` → `ruff check .`
3. `.flake8` or `setup.cfg` with `[flake8]` → `flake8`
4. `.golangci.yml` → `golangci-lint run`
5. `analysis_options.yaml` → `dart analyze`
6. `Cargo.toml` → `cargo clippy`
7. None found → `not detected`

#### Validation tool
1. `package.json` with: `zod` → **Zod**, `joi` → **Joi**, `yup` → **Yup**, `class-validator` → **class-validator**
2. `pyproject.toml` or `requirements.txt` with `pydantic` → **Pydantic**
3. `pubspec.yaml` with: `freezed` → **Freezed**, `json_serializable` → **json_serializable**, `built_value` → **built_value**
4. None found → `not detected`

#### Frontend detected?
- `package.json` contains `next`, `react`, `@angular/core`, `vue`, `nuxt`, or `svelte` → **yes**
- Or: `.tsx`, `.jsx`, or `.vue` files exist in `src/` → **yes**
- Otherwise → **no**

#### Frontend framework (only if Frontend detected == yes)
Search in order:
1. `package.json` contains `nuxt` → **nuxt**
2. `package.json` contains `next` → **next**
3. `package.json` contains `@angular/core` → **angular**
4. `package.json` contains `react` (without `next`) → **react**
5. `package.json` contains `vue` (without `nuxt`) → **vue**
6. `package.json` contains `svelte` → **svelte**
7. None of the above → **unknown**

When the framework is detected, also read the version from `dependencies.<pkg>` or `devDependencies.<pkg>` and parse the major.minor (e.g. `"next": "^16.0.7"` → `16.0`). Save as `{FRAMEWORK_FRONTEND}` and `{FRAMEWORK_FRONTEND_VERSION}` for use in Step 5 (framework-specific AGENTS.md block injection).

#### AI-tooling conventions verification (per detected framework)

The state of the art for `AGENTS.md` conventions (and equivalents) moves quickly — hard-coded `profiles/<framework>.md` files reflect the state at plugin release, but newer framework versions introduce additional patterns the plugin doesn't yet know. For each detected framework (`{FRAMEWORK_FRONTEND}`, backend framework if applicable, infrastructure tools like Terraform, etc.), query current documentation to discover AI-tooling conventions.

**Lookup strategy** (in order, first source that yields a result wins):

1. **`ctx7` CLI** if available in PATH:
   - `ctx7 library <framework>` to resolve the ID (e.g. `/vercel/next.js`)
   - `ctx7 docs <id> "AGENTS.md convention bundled docs agent rules"` for the query
2. **Context7 MCP** as fallback: `mcp__context7__resolve-library-id` + `mcp__context7__query-docs` with the same query
3. **WebSearch** if neither ctx7/Context7 is reachable: query `"AGENTS.md convention <framework> <major>.<minor>"` (e.g. `"AGENTS.md convention next.js 16.2"`), preferring results from the framework's official domain
4. **Skip** if no source is reachable (offline environment) — proceed with hard-coded profiles only and note the skip in the Step 9 summary

**What to look for**, per framework:

- Is there an `AGENTS.md` convention officially supported by the framework (e.g. Next.js's `BEGIN:nextjs-agent-rules` block)?
- Which markers / sections are framework-managed (e.g. by a `<framework> upgrade` command)?
- Path of bundled docs (if applicable, e.g. `node_modules/<framework>/dist/docs/`)
- Codemod or related tooling for existing projects (e.g. `npx @next/codemod@latest agents-md`)
- Minimum framework version that supports the convention

**Source precedence**:

- Hard-coded profile (`profiles/<framework>.md`) → primary source for frameworks documented at plugin release time (deterministic, predictable)
- Runtime verification → additional source for frameworks not yet documented in the plugin **or** for newer versions that introduced new conventions

Save any discovered convention as `{FRAMEWORK_AGENTS_CONVENTION}` (structured object: marker name, block content, source, doc link) — Step 5 applies it as framework-specific block injection following the same strategy documented for Next.js.

**Output to the developer**: one line in the Step 9 summary per verified framework:

```
- <framework> <version>: convention <name> found via <source> → <action applied>
- <framework> <version>: no documented AI-tooling convention → no action
- <framework> <version>: verification skipped (offline) → only hard-coded profile applied
```

#### Mobile detected?
- `pubspec.yaml` present → **yes**
- `package.json` contains `react-native` or `expo` → **yes**
- Otherwise → **no**

#### Multi-project detected?

**Phase 1 — Monorepo tool**:
- `nx.json` present → **yes** (Nx)
- `turbo.json` present → **yes** (Turborepo)
- `pnpm-workspace.yaml` present → **yes** (pnpm workspace)
- `lerna.json` present → **yes** (Lerna)
- Root `package.json` contains `workspaces` field → **yes** (Yarn/npm workspaces)

**Sub-project enumeration** (priority order, first source that yields results wins):
1. `pnpm-workspace.yaml` → read `packages:` (glob list)
2. Root `package.json` → read `workspaces` field (array of globs)
3. `lerna.json` → read `packages` (glob list)
4. `nx.json` → read `projects` ONLY if the field exists (legacy, Nx ≤ 17). From Nx 18+ the field is gone: projects are inferred from `package.json`/`project.json` under workspace paths ("inferred projects" model). In that case use one of the sources above.
5. `turbo.json` → projects are inferred from the underlying pnpm/yarn/npm workspace; Turborepo does not maintain its own list.

Expand globs to actual directories containing a `package.json`. Optional cross-check: if the Nx CLI is available in `node_modules/.bin` or PATH, run `pnpm nx show projects` (or `npx nx show projects`) and compare the inferred list against the CLI output.

For each sub-project, read its `package.json`:
- `name` → project identifier (used both for the display path and for command wrapping, see below)
- `scripts` → available commands (`dev`, `build`, `test`, `lint`, ...)
- `dependencies` / `devDependencies` → drivers for stack detection
- Optional `nx` field (per-target inputs/outputs/cache) → informational, does not change the invocation

**Phase 2 — Structural detection** (only if Phase 1 found nothing):
- Search first-level directories for project indicator files: `package.json`, `pubspec.yaml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`
- If **2 or more** directories contain at least one indicator → **yes** (multi-project)
- Ignore common non-project directories: `node_modules`, `.git`, `.claude`, `dist`, `build`, `coverage`, `.github`, `.husky`

**If multi-project detected** (from Phase 1 or Phase 2):
1. For each sub-project found, run auto-detection (Language, Test runner, Linter, Validation tool, Frontend detected?, Mobile detected?) in the sub-project directory, reading its `package.json` (if present) for `scripts`, `dependencies`, `devDependencies`.
2. **Invocation wrapping**: in multi-project mode commands must be runnable from the workspace root, not only from the sub-project folder. When populating `{{TEST_COMMAND}}` / `{{LINT_COMMAND}}` (and any other command) in the per-project template, use the wrapped form matching the detected monorepo tool:
   - **Nx** → `nx run <name>:<target>` (preferred when the target is defined in `nx.json` `targetDefaults` or in `package.json` `nx.targets`); fallback `pnpm --filter <name> <script>` (or the equivalent for the package manager)
   - **pnpm workspace** (no Nx) → `pnpm --filter <name> <script>`
   - **Yarn workspace** → `yarn workspace <name> <script>`
   - **npm workspace** → `npm run <script> --workspace=<name>`
   - **Lerna** → `lerna run <script> --scope=<name>`
   - Non-Node sub-projects (e.g. Terraform under `iac/`) → raw command, run from the sub-project directory (no wrapping).
3. Show the summary to the developer and ask for confirmation before proceeding.

**Show the detection summary to the developer.**

For single project:
```
Detected stack:
  Languages:    node
  Test runner:  npm test
  Linter:       npm run lint
  Validation:   Zod
  Frontend:     yes
  Framework:    nuxt
  Mobile:       no
```

For multi-project (commands are already wrapped to be runnable from the workspace root):
```
Detected stack:
  Multi-project: yes (Nx + pnpm workspace)
  Sub-projects:
    applications/web/   — node, frontend: yes, test: pnpm --filter web test, lint: pnpm --filter web lint
    applications/api/   — node, frontend: no, test: pnpm --filter api test, lint: pnpm --filter api lint
    iac/                — terraform, infrastructure: yes, test: terraform validate, lint: terraform fmt -check -recursive

Do you confirm these sub-projects? (yes/no)
```

---

### Step 2b — Stack selection (GREENFIELD mode only)

If the mode is GREENFIELD, ask the developer to choose the stack:

1. **Web Frontend** — Next.js / Angular / React + ShadCN/UI + Tailwind
2. **Web Frontend (Nuxt)** — Nuxt 3 / Vue 3 + shadcn-vue + Tailwind
3. **Backend Node** — Node.js / NestJS + Prisma + Zod
4. **Mobile** — Flutter / React Native (Expo)
5. **Full-stack** — Frontend + Backend (monorepo)

If they choose **Mobile**, also ask:
- **Flutter**
- **React Native (Expo)**

If they choose **Full-stack**, also ask which frontend variant (React-like or Nuxt).

---

### Step 3 — Download resources from the source repo

Use `gh api` to download files from the `acadevmy/ai-setup-meta` repo. This command handles
authentication automatically and works with private repos.

**Prerequisite**: verify that `gh` is authenticated with `gh auth status`. If it is not, inform
the developer to run `gh auth login` and stop.

**Command to download a file**:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/<PATH> -H "Accept: application/vnd.github.raw" > <OUTPUT>
```

**IMPORTANT**: Write the downloaded files **exactly as received**, without modifications. Do not reformat, fix, or improve. The content must be verbatim.

#### 3.0 — Prepare staging and download the manifest

Create the local staging directory in the project for files that require transformation:
```bash
mkdir -p .claude/.setup-tmp
```

Download the manifest to staging:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/manifest.json -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/manifest.json
```

Read the manifest and use it to guide subsequent downloads.

#### 3.1 — Files with transformation (to staging)

These files require adaptation before being installed. Download them to local staging:

**CONSTITUTION.md** (will be adapted in Step 4):
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/CONSTITUTION.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/CONSTITUTION_SOURCE.md
```

**AGENTS template** (will be processed in Step 5):

For single project:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/AGENTS.template.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/AGENTS_TEMPLATE.md
```

For multi-project (or fullstack stack):
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/AGENTS.workspace-template.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/AGENTS_WORKSPACE_TEMPLATE.md
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/AGENTS.project-template.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/AGENTS_PROJECT_TEMPLATE.md
```

**Stack profile** (GREENFIELD only, will be applied in Step 9.5):

Download the selected profile from the manifest `profiles`:
- Web Frontend (React/Next/Angular): `gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/profiles/web-frontend.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/profile.md`
- Web Frontend (Nuxt): `gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/profiles/web-frontend-nuxt.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/profile.md`
- Backend Node: `gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/profiles/backend-node.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/profile.md`
- Mobile: `gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/profiles/mobile.md -H "Accept: application/vnd.github.raw" > .claude/.setup-tmp/profile.md`
- Full-stack: download the selected frontend profile (`web-frontend.md` or `web-frontend-nuxt.md`) plus `backend-node.md` (as `profile_web.md` and `profile_api.md`)

#### 3.2 — Verbatim files (directly to destination)

These files are copied exactly as received. Before each download, check whether the destination file already exists (**conflict detection**): if it does, inform the developer and keep the existing one by skipping the download.

**Create the directory structure**:
```bash
mkdir -p .claude/skills .claude/agents
mkdir -p .claude/skills/{auto-sdd,tdd,bdd,review,setup,sdd,sdd-spec,sdd-plan,sdd-dev}
mkdir -p .claude/skills/{clickup,github-ops}
```

**settings.json**:
If `.claude/settings.json` does **not** exist:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/.claude/settings.json -H "Accept: application/vnd.github.raw" > .claude/settings.json
```
If it **already exists**: inform the developer and keep the existing one.

**REGISTRY.md**:

For single project:
If `REGISTRY.md` does **not** exist (or the developer confirms overwriting):
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/REGISTRY.md -H "Accept: application/vnd.github.raw" > REGISTRY.md
```

For multi-project:
Generate a `REGISTRY.md` for each confirmed sub-project. Do not generate REGISTRY.md at the root.
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/REGISTRY.md -H "Accept: application/vnd.github.raw" > <sub-project-path>/REGISTRY.md
```

**Skills** (from manifest):

Download and install the appropriate skills based on the project.

**Common skills** (always installed): review
**SDD skills** (always installed): sdd, auto-sdd, sdd-spec, sdd-plan, sdd-dev
**Shared skills** (always installed): clickup, github-ops

**Methodology skills** (based on project type):
- If **frontend detected** (or Web Frontend / Mobile / Full-stack stack) → install `bdd`
- If **backend detected** (or Backend Node / Full-stack stack) → install `tdd`
- If **full-stack** or undeterminable → install both (`tdd` + `bdd`)

For each shared skill to install, if `.claude/skills/<SKILL_NAME>/SKILL.md` does **not** exist:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/shared/skills/<SKILL_NAME>/SKILL.md -H "Accept: application/vnd.github.raw" > .claude/skills/<SKILL_NAME>/SKILL.md
```

For each template skill to install, if `.claude/skills/<SKILL_NAME>/SKILL.md` does **not** exist:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/.claude/skills/<SKILL_NAME>/SKILL.md -H "Accept: application/vnd.github.raw" > .claude/skills/<SKILL_NAME>/SKILL.md
```

If it **already exists**: inform the developer and keep the existing one.

**Agent files** (from manifest):

For each agent in `shared_agents`, if `.claude/agents/<AGENT_NAME>` does **not** exist:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/shared/agents/<AGENT_NAME> -H "Accept: application/vnd.github.raw" > .claude/agents/<AGENT_NAME>
```

For each agent in `template_agents`, if `.claude/agents/<AGENT_NAME>` does **not** exist:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/.claude/agents/<AGENT_NAME> -H "Accept: application/vnd.github.raw" > .claude/agents/<AGENT_NAME>
```

If it **already exists**: inform the developer and keep the existing one.

**Keep setup.md**: The `.claude/skills/setup/SKILL.md` file (the dispatcher skill) is already present. Do not touch it.

**Verify that downloads succeeded**: check that downloaded files are not empty and do not contain JSON errors (e.g. `{"message":"Not Found"}`). If a download fails, inform the developer and stop.

---

#### 3.3 — Tighten allowlist to the detected package manager

The `.claude/settings.json` template lists all three Node package managers (`Bash(npm *)`, `Bash(pnpm *)`, `Bash(yarn *)`) in the `allow` array because at plugin release time we don't know which one you'll use. If the project has a single lock file, narrow the allowlist to the PM in use — an agent shouldn't run `yarn install` in a pnpm project and bypass workspace/hoisting conventions.

**Skip if**:
- `.claude/settings.json` already existed at the time of 3.2 and was not overwritten (conflict detection left it alone — post-hoc edits aren't your job).
- Detected languages from Step 2 do NOT include `node` (e.g. pure Python/Go/Terraform project): the three entries stay so an occasional `npx <tool>` still works.

**Package manager detection**:

| Lock file detected at root | Package manager |
|---|---|
| `pnpm-lock.yaml` | **pnpm** |
| `yarn.lock` | **yarn** |
| `package-lock.json` | **npm** |
| Multiple lock files | **ambiguous** — leave the allowlist alone, flag the anomaly in the Step 9 summary |
| No lock file (`package.json` exists but `install` has not yet been run) | **none** — leave all three entries, flag in the Step 9 summary |

**Allowlist edits** (only when a single PM is detected):

- `pnpm` → keep `Bash(pnpm *)`, add `Bash(pnpx *)` if not already present, remove `Bash(npm *)` and `Bash(yarn *)`. **Keep `Bash(npx *)`** — it is universal, used by the `ctx7` CLI (`npx ctx7@latest`), official codemods (`npx @next/codemod@latest`), and many one-shot tool READMEs. Removing `npx` breaks those flows for no real gain.
- `yarn` → keep `Bash(yarn *)` and `Bash(npx *)`, remove `Bash(npm *)` and `Bash(pnpm *)`.
- `npm` → keep `Bash(npm *)` and `Bash(npx *)`, remove `Bash(yarn *)` and `Bash(pnpm *)`.

**Deny array untouched**: do NOT modify the `deny` array. `Bash(npm publish*)`, `Bash(pnpm publish*)`, `Bash(yarn publish*)` all remain — an accidental `publish` via the "wrong" PM is still an event worth blocking.

**Implementation (jq, idempotent, preserves the rest of the file)**:

```bash
# Detected PM == "pnpm"
jq '.permissions.allow |= ((. - ["Bash(npm *)", "Bash(yarn *)"]) | if any(. == "Bash(pnpx *)") then . else . + ["Bash(pnpx *)"] end)' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Detected PM == "yarn"
jq '.permissions.allow -= ["Bash(npm *)", "Bash(pnpm *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Detected PM == "npm"
jq '.permissions.allow -= ["Bash(yarn *)", "Bash(pnpm *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

`jq` is already a declared dependency of the plugin (see `scripts/build-plugin.sh`), so it is reasonable to assume it is present.

**Report in the Step 9 summary** (one line):
- Single PM detected: `allowlist tightened to <pm>-only commands per detected lock file (<lockfile>)`
- Multiple lock files: `multiple lock files detected (<list>) — allowlist left as default; consider committing to a single PM`
- No lock file but `node` detected: `no lock file present — allowlist left as default; the team should run \`<pm> install\` and re-run setup to tighten`

---

### Step 4 — Adapt CONSTITUTION.md

Start from the content downloaded to `.claude/.setup-tmp/CONSTITUTION_SOURCE.md`.

#### For EXISTING mode:

Apply the following removal/adaptation rules based on the detected stack.
Rules are applied in order A → B → C → D → E. Renumbering (rule E) happens last.

**Rule A — Section VI (Frontend: Next.js / Angular / React) and Section VII (Frontend: Nuxt / Vue)**:
- If frontend was **not** detected → remove both Section VI (from `## VI.` up to before `## VII.`) and Section VII (from `## VII.` up to before `## VIII.`)
- If frontend **is** detected, apply the sub-rule based on the framework identified in Step 2:
  - `framework == nuxt` or `framework == vue` → remove Section VI (keep only Section VII Nuxt/Vue)
  - `framework ∈ {next, angular, react, svelte, unknown}` → remove Section VII (keep only Section VI React-like)
- **Multi-project**: evaluate per sub-project. Keep Section VI if **any** sub-project uses a React-like framework; keep Section VII if **any** sub-project uses Nuxt/Vue. Both sections can coexist if the monorepo mixes stacks.

**Rule B — Section VIII (Mobile)**:
- If mobile was **not** detected → remove the entire Section VIII (from `## VIII.` up to before `## IX.`)
- **Multi-project**: keep Section VIII if **any** sub-project has mobile detected
- If mobile is detected as **Flutter only** (no React Native) → remove only rule 38 (React Native)
- If mobile is detected as **React Native only** (no Flutter) → remove rules 28-37 (Flutter/Dart) and keep only rule 38

**Rule C — Sections I-V (TypeScript-specific)**:
- If the detected language includes `node` → keep sections I-V in full
- If the detected language does **not** include `node` but includes `flutter` → remove TypeScript-specific rules:
  - Rule 1 (Schema-first with Zod): remove entirely — Flutter data validation is covered by rule 31 (freezed/json_serializable)
  - Rule 2 (TypeScript strict — zero `any`): remove entirely — Dart type safety is covered by rule 30
  - Rule 7 (Dependency Injection): replace `DI (native NestJS, or manual for pure Node projects)` with `DI via service locator (get_it) or framework-native injection`
  - Rule 14 (Pull Request): replace `ESLint` with `static analysis (dart analyze)`
  - Rule 17 (Input validation with Zod): replace the Zod reference with:
    ```
    Every external input is potentially malicious. Always validate with the
    typed tools of your stack (freezed + json_serializable for Flutter/Dart),
    sanitize before using in queries or template strings.
    ```
  - Rule 18 (Dependency audit): replace `npm audit` with `dart pub outdated` and `flutter pub deps`
  - Keep rules 3-5 (error handling, pure functions, no magic numbers) intact — they are universal
  - Keep rules 6, 8 (layer separation, naming) intact — they are universal
- If the detected language includes **neither** `node` nor `flutter` → adapt tool-specific references:
  - Rule 1 (Schema-first with Zod): replace `Zod` with `the schema validation tool of your stack` and remove the TypeScript example. Keep the principle
  - Rule 2 (TypeScript strict): replace with the generic principle:
    ```
    ### N. Strict typing — zero unsafe types
    The language's strict typing is mandatory. Avoid unsafe generic types
    (any, dynamic, Object without narrowing, void*, interface{}).
    ```
  - Rule 7 (Dependency Injection): replace the NestJS reference with `DI via the idiomatic pattern of the language`
  - Rule 14 (Pull Request): replace `ESLint` with `the configured linter`
  - Rule 17 (Input validation): replace the Zod reference with `the validation tool of your stack`
  - Rule 18 (Dependency audit): replace `npm audit` with the appropriate command (`govulncheck` for Go, `pip audit` for Python, `cargo audit` for Rust)
  - Add this note immediately after `## I. Core principles`:
    - **Multi-project**: add the note only if **no** sub-project uses `node` or `flutter`
    ```
    > **Note**: This project does not use TypeScript or Flutter/Dart.
    > Rules have been adapted to universal principles. Apply the idiomatic tools
    > of your stack for validation, typing, and dependency audit.
    ```

**Rule D — Section III Testing (stack adaptation)**:
When frontend is **not** detected (Rule A applied):
- Rule 9 (Testing methodology): remove the `#### Frontend (components, pages, user flows) — BDD` subsection and its BDD points 1-4. Keep only the `#### Backend` subsection
- Rule 10 (Minimum coverage): remove the `UI components | 70% (with Testing Library)` row from the table
- Rule 11 (Test structure): remove the `#### Frontend — BDD` subsection with the Gherkin example. Keep only the `#### Backend — TDD` subsection

When frontend **is** detected but backend is **not** detected:
- Rule 9: remove the `#### Backend (logic, API, services) — TDD` subsection. Keep only the `#### Frontend` subsection
- Rule 11: remove the `#### Backend — TDD` subsection. Keep only the `#### Frontend — BDD` subsection

When the language is `flutter` (without `node`):
- Rule 9: keep both subsections (Flutter uses TDD for UseCase + BDD for widget/screen)
- Rule 10: replace the `UI components | 70% (with Testing Library)` row with `Widget / Screen | 70% (with flutter_test + WidgetTester)`
- Rule 11: replace the TypeScript example in the Backend TDD subsection with a Dart example:
  ```dart
  group('CreateUserUseCase', () {
    test('should create a user with valid email', () async { ... });
    test('should return Failure if email is invalid', () async { ... });
    test('should return Failure if email already exists', () async { ... });
  });
  ```
  Replace the Gherkin example in the Frontend BDD subsection with a widget test:
  ```dart
  testWidgets('Login with valid credentials', (tester) async {
    // Given: the user is on the login page
    await tester.pumpWidget(const LoginScreen());
    // When: they enter valid email and password and press "Sign in"
    await tester.enterText(find.byKey(Key('email')), 'test@example.com');
    await tester.enterText(find.byKey(Key('password')), 'password123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    // Then: they are redirected to the dashboard
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
  ```

**Rule E — Renumbering**:
After all removals and adaptations (rules A-D), renumber the remaining rules sequentially (1, 2, 3, ...) to avoid gaps in numbering.

**Quick decision summary**:

| Detected stack | Sec. I-V | Sec. III (Test) | Sec. VI (Frontend React-like) | Sec. VII (Frontend Nuxt/Vue) | Sec. VIII (Mobile) |
|---|---|---|---|---|---|
| Node/TS backend only | Keep | TDD only | Remove | Remove | Remove |
| Node/TS frontend (React-like) | Keep | BDD only | Keep | Remove | Remove |
| Node/TS frontend (Nuxt/Vue) | Keep | BDD only | Remove | Keep | Remove |
| Node/TS fullstack (React-like) | Keep | TDD + BDD | Keep | Remove | Remove |
| Node/TS fullstack (Nuxt) | Keep | TDD + BDD | Remove | Keep | Remove |
| Flutter only | Adapt (C) | Adapt Dart (D) | Remove | Remove | Flutter only |
| React Native only | Keep TS | TDD + BDD | Remove | Remove | RN only |
| Node + Flutter (multi) | Keep | TDD + BDD | Depends | Depends | Keep |
| Other language | Adapt generic (C) | Depends on stack | Remove | Remove | Remove |

#### For GREENFIELD mode:

Apply the same adaptation rules (A-E) based on the stack chosen in Step 2b:
- **Web Frontend** (React-like): remove Sec. VII (Nuxt) and Sec. VIII (Mobile), keep Sec. VI, Sec. III BDD only
- **Web Frontend (Nuxt)**: remove Sec. VI (React-like) and Sec. VIII (Mobile), keep Sec. VII, Sec. III BDD only
- **Backend Node**: remove Sec. VI, VII, and VIII, Sec. III TDD only
- **Mobile (Flutter)**: remove Sec. VI and VII, remove rule 38 (RN), adapt TS rules (C), adapt tests (D)
- **Mobile (React Native)**: remove Sec. VI and VII, remove rules 28-37 (Flutter), keep TS rules (RN uses TypeScript)
- **Full-stack** (React-like frontend): remove Sec. VII and Sec. VIII, keep Sec. VI
- **Full-stack** (Nuxt frontend): remove Sec. VI and Sec. VIII, keep Sec. VII

#### For UPDATE mode:

Overwrite the existing CONSTITUTION.md with the downloaded version, applying the same rules as EXISTING based on the detection from Step 2.

**Conflict detection**: If `CONSTITUTION.md` already exists in the project, ask the developer before overwriting.

Write the result to `CONSTITUTION.md` in the project root.

---

### Step 5 — Generate AGENTS.md

#### 5A — Single project (not multi-project)

Read the content downloaded from `.claude/.setup-tmp/AGENTS_TEMPLATE.md` and replace the placeholders.
The template is the same for all modes: only the source of values changes.

**Placeholder values for EXISTING mode:**

- `{{STACK_DESCRIPTION}}` → compact description of the detected stack. Format: `Detected stack: languages[, test: test_command][, linter: lint_command][, validation: tool]`
  - Example: `Detected stack: **node**, test: npm test, linter: npm run lint, validation: Zod`
  - If test/linter/validation are `not detected`, omit them from the string
  - Add note: `> This stack was auto-detected. If it is incorrect, update this section manually.`
- `{{TEST_COMMAND}}` → the detected test command (e.g. `npm test`, `pytest`, `not detected`)
- `{{LINT_COMMAND}}` → the detected linter command (e.g. `npm run lint`, `ruff check .`, `not detected`)
- `{{TYPECHECK_COMMAND}}` → the detected type-check command. For Node projects with `tsconfig.json`, read `package.json.scripts.typecheck` or `package.json.scripts['type-check']`; if missing, use `tsc --noEmit`. For other stacks, leave as `not detected`.
- `{{QUALITY_COVERAGE_TARGET}}` → coverage threshold. Default: `80%` with the comment `(industry baseline; adjust if your team has set a different bar)`. If `package.json` or the test runner config exposes an explicit threshold, use that.

**Project Identity (interactive, EXISTING and GREENFIELD modes):**

Emit ONE batched question with three sub-fields and collect the answers. Leave `{{TODO: <hint>}}` for empty fields — never invent values.

> Question to ask the developer:
>
> "To populate the `Project Identity` section in AGENTS.md I need three short pieces of info (press Enter to skip a field, I'll leave a TODO):
> - **Name**: short project name (e.g. 'Acme Web App')
> - **Purpose**: one sentence on what the project does
> - **Primary users**: who uses it (e.g. 'consumer travelers', 'internal ops')"

Substitutions:
- `{{PROJECT_NAME}}` → developer's answer, or `{{TODO: short app name}}`
- `{{PROJECT_PURPOSE}}` → developer's answer, or `{{TODO: one-sentence purpose}}`
- `{{PROJECT_PRIMARY_USERS}}` → developer's answer, or `{{TODO: who uses this app}}`

**Infrastructure (auto-detect + TODO, EXISTING and GREENFIELD modes):**

Try auto-detection in the order below; anything not detectable becomes `{{TODO: <hint>}}`:

- `{{INFRA_VCS_CI}}` → combine:
  - VCS: parse the remote URL from `.git/config` (`gitlab.com` → `GitLab`, `github.com` → `GitHub`, `bitbucket.org` → `Bitbucket`, `dev.azure.com` → `Azure DevOps`)
  - CI: presence of `.gitlab-ci.yml` → `GitLab CI`; `.github/workflows/` → `GitHub Actions`; `.circleci/config.yml` → `CircleCI`; `bitbucket-pipelines.yml` → `Bitbucket Pipelines`; `azure-pipelines.yml` → `Azure Pipelines`; `Jenkinsfile` → `Jenkins`
  - Result: `<VCS> + <CI>` (e.g. `GitLab + GitLab CI`). If VCS detected but CI not, write `<VCS>, CI: {{TODO: which CI provider}}`.
- `{{INFRA_SECRETS}}` → presence of `dotenv-vault.json` or `.env.vault` → `dotenv-vault`; `*.tfstate` with `vault` backend → `HashiCorp Vault`; `aws-secretsmanager` or `aws ssm` references in IaC/CI → `AWS Secrets Manager` / `AWS Parameter Store`. Otherwise `{{TODO: secrets manager (e.g. dotenv-vault, AWS SSM, Vault)}}`.
- `{{INFRA_HOSTING}}` → light heuristic from CI: detect provider names in deploy steps (`vercel`, `netlify`, `aws-eks`, `kubectl`, `gcloud run`, `firebase deploy`). Otherwise `{{TODO: hosting/deploy target}}`.
- `{{INFRA_OBSERVABILITY}}` → presence of `datadog.yaml` / `dd-trace` dependency → `Datadog`; `sentry.client.config.*` or `@sentry/*` in package.json → `Sentry`; `newrelic.{yml,json}` → `New Relic`. Otherwise `{{TODO: observability tool}}`.

**Boundaries (semi-auto, EXISTING and GREENFIELD modes):**

- `{{BOUNDARIES_ALWAYS}}` → auto-seed with the detected quality commands as a bullet list:
  - `- Run \`{{TEST_COMMAND}}\` before commit` (omit if `{{TEST_COMMAND}}` is `not detected`)
  - `- Run \`{{LINT_COMMAND}}\` before commit` (omit if `{{LINT_COMMAND}}` is `not detected`)
  - `- Run \`{{TYPECHECK_COMMAND}}\` before commit` (omit if `{{TYPECHECK_COMMAND}}` is `not detected`)
  - If all three are `not detected`, leave `{{TODO: list always-do actions for this project}}`
- `{{BOUNDARIES_ASK_FIRST}}` → `{{TODO: list actions that require explicit go-ahead (e.g. adding new dependencies, schema migrations, brand-color changes)}}`
- `{{BOUNDARIES_NEVER_EXTRA}}` → empty by default (the base `Never Do` list is already in the template; only add project-specific prohibitions here). Example if you detect a non-standard prod ref: `- Push to <branch-name> without explicit go-ahead`.

**Placeholder values for GREENFIELD mode:**

Based on the stack chosen in Step 2b:

| Stack | `{{STACK_DESCRIPTION}}` | `{{TEST_COMMAND}}` | `{{LINT_COMMAND}}` |
|---|---|---|---|
| Web Frontend | `**Web Frontend**: Next.js 14+ / Angular 17+ / React 18+, ShadCN/UI, Tailwind CSS, Zod, Jest + Testing Library` | `npm test` | `npm run lint` |
| Backend Node | `**Backend Node**: Node.js 20+, NestJS 10+, Zod + class-validator, Jest + Supertest, Prisma` | `npm test` | `npm run lint` |
| Mobile (Flutter) | `**Mobile**: Flutter 3.24+ (BLoC/Riverpod)` | `flutter test` | `dart analyze` |
| Mobile (React Native) | `**Mobile**: React Native with Expo (Zustand/Jotai)` | `npm test` | `npm run lint` |

**For UPDATE mode:** Regenerate as for EXISTING or GREENFIELD (depending on the project state).

**Conflict detection**: If `AGENTS.md` already exists, ask the developer before overwriting.

**Framework-specific block — Next.js (`AGENTS.md` bundled-docs convention)**:

If `{FRAMEWORK_FRONTEND}` == `next`, prepend the canonical Next.js block to the generated `AGENTS.md`, **before** any template-derived content:

```md
<!-- BEGIN:nextjs-agent-rules -->

# Next.js: ALWAYS read docs before coding

Before any Next.js work, find and read the relevant doc in `node_modules/next/dist/docs/`. Your training data is outdated — the docs are the source of truth.

<!-- END:nextjs-agent-rules -->

```

The `BEGIN:nextjs-agent-rules` / `END:nextjs-agent-rules` markers delimit a section managed by `next upgrade` (Next.js 16.2+): everything inside the markers is rewritten on upgrade, everything outside is preserved. Keeping plugin content below the `END` marker ensures `next upgrade` never overwrites it. See `profiles/nextjs.md` for full details.

Based on `{FRAMEWORK_FRONTEND_VERSION}` (parsed as major.minor):

- `>= 16.2` → docs are bundled at `node_modules/next/dist/docs/`. Add to the Step 9 summary: "run `npx next upgrade@canary` periodically to keep the AGENTS.md block current."
- `< 16.2` → docs are **not** bundled. Add to the Step 9 summary: "run `npx @next/codemod@latest agents-md` to generate docs at `.next-docs/` and update the path in the block."

**Brownfield**: if `AGENTS.md` already exists and contains a `BEGIN:nextjs-agent-rules` … `END:nextjs-agent-rules` block, **do not regenerate** the inside content. Preserve the block verbatim and plug the plugin template below the `END` marker. The inner block is Next.js's territory — rewriting it would conflict with the next `next upgrade`.

**Runtime-discovered conventions**:

If the verification step in Step 2a populated `{FRAMEWORK_AGENTS_CONVENTION}` for a framework other than Next.js (or for a Next.js version newer than what's documented above), apply the same injection strategy: delimited markers at the top of the file, plugin template content below the closing marker. Precedence: hard-coded profile (e.g. the Next.js block above) → runtime convention → no injection. On conflict between hard-coded and runtime, the hard-coded profile wins and the runtime convention is reported as "not applied, hard-coded source has precedence" in the Step 9 summary.

Write the result to `AGENTS.md` in the project root.

#### 5B — Multi-project (or fullstack stack)

Generate **two levels** of AGENTS.md: one at the root and one for each **application** sub-project. Libraries do not get per-project setup files — their usage is cited in the consuming application's REGISTRY (see "Library citations" below).

**Sub-project classification (application vs library)**, in priority order:

1. Path matches `applications/*`, `apps/*`, `services/*` → **application**
2. Path matches `libraries/*`, `libs/*`, `packages/*` → **library**
3. `package.json` has `"private": false` AND `"main"`/`"exports"` → **library** (publishable shape)
4. `package.json` has `scripts.dev` or `scripts.start` → **application** (runnable shape)
5. Otherwise → ask the developer (default: **application**)

Save the classification per sub-project as `{SUBPROJECT_TYPE}`.

**Root AGENTS.md** — use `.claude/.setup-tmp/AGENTS_WORKSPACE_TEMPLATE.md`:
- `{{WORKSPACE_STRUCTURE}}` → generate a table with ALL confirmed sub-projects (apps + libs), with a `Type` column and the `Instructions` column differentiated:
  ```
  | Project | Type | Path | Stack | Instructions |
  |---|---|---|---|---|
  | web   | application | apps/web/ | Next.js 14+, React 18+ | [apps/web/AGENTS.md](apps/web/AGENTS.md) |
  | api   | application | apps/api/ | Node.js 20+, NestJS 10+ | [apps/api/AGENTS.md](apps/api/AGENTS.md) |
  | shared | library    | libs/shared/ | TypeScript, Zod | (no per-library file — see consuming app REGISTRY) |
  ```
- Add a note below the table:
  > Libraries do not get per-project setup files. When a library exposes an interesting pattern, ADR, or breaking change, add a `### library/<name>` entry to the **consuming application's `REGISTRY.md`** under "Services and utilities" — that's where library usage is documented.
- Write the result to `AGENTS.md` at the root

**AGENTS.md for sub-projects** — use `.claude/.setup-tmp/AGENTS_PROJECT_TEMPLATE.md`:

**Only for sub-projects with `{SUBPROJECT_TYPE} == 'application'`**, replace the placeholders:
- `{{PROJECT_NAME}}` → descriptive name of the sub-project (e.g. "Web Frontend", "Backend API")
- `{{STACK_DESCRIPTION}}` → detected stack of the sub-project (same criteria as point 5A)
- `{{TEST_COMMAND}}` → test runner detected in the sub-project
- `{{LINT_COMMAND}}` → linter detected in the sub-project
- `{{ROOT_AGENTS_REL_PATH}}` → relative path to the root (e.g. `../../AGENTS.md`)

Write the result to `<sub-project-path>/AGENTS.md`.

Sub-projects with `{SUBPROJECT_TYPE} == 'library'` **do not receive** AGENTS.md / CLAUDE.md / REGISTRY.md files.

**Library citations** (per application):

For each sub-project with `{SUBPROJECT_TYPE} == 'application'`, read its `package.json` and identify workspace dependencies on monorepo libraries. A dependency is workspace-resolved when:
- The value is `workspace:*`, `workspace:^`, `workspace:~`, or `workspace:<version>`
- Or the package name matches exactly the `name` of a sub-project with `{SUBPROJECT_TYPE} == 'library'`

For each consumed library, add an entry to `<app>/REGISTRY.md` "Services and utilities" section using this template:

```markdown
### library/<name>

- **Where**: `libraries/<name>/` (or the actual path) — workspace package
- **Used by**: this application (add any other apps that consume it, comma-separated)
- **Summary**: <one line; use the `description` from `<lib>/package.json` if present, or the first meaningful paragraph from the library's README; if neither is usable, write "TBD — refine when first touched">
```

This way the AI agent working in the application immediately sees which libraries it uses, where they live, and has a starting point to investigate them. When the team adds patterns/ADRs that touch a library, they live in the consuming app's REGISTRY and can reference `### library/<name>` as an anchor.

---

### Step 5b — Generate CLAUDE.md

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. To ensure compatibility with Claude Code
while maintaining `AGENTS.md` as the cross-tool standard (Codex, Copilot, Cursor, etc.),
generate a `CLAUDE.md` that references `AGENTS.md`:

```markdown
@AGENTS.md
```

The `CLAUDE.md` file must contain **only** the line shown above. Do not add
any other content: all instructions must remain in `AGENTS.md` as the single source of truth.

**Conflict detection**: If `CLAUDE.md` already exists, ask the developer before overwriting.

Write the result to `CLAUDE.md` in the project root.

**Multi-project**: also generate `CLAUDE.md` in each confirmed sub-project, with the same content (`@AGENTS.md`). The sub-project's CLAUDE.md will point to the local AGENTS.md of that sub-project.

---

### Step 6 — Configure MCP servers

Check if the `claude` CLI is available with `command -v claude`. If it is not, print the commands to run manually and proceed to the next step.

#### 6.1 — ClickUp (user scope, always)

Check with `claude mcp list` whether `clickup` is already configured.
If not:
```bash
claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
```

#### 6.2 — Context7 (project scope, always)

Check whether `context7` is already configured.
If not:
```bash
claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest
```

#### 6.3 — Figma (only if frontend or mobile detected, or web-frontend/mobile/fullstack stack)

If frontend or mobile detected, ask the developer: "Do you want to configure the Figma MCP? Authentication is done via OAuth in the browser."
If they answer yes:
```bash
claude mcp add figma -s project --type url https://mcp.figma.com/mcp
```
On first use, Figma will request authorization via the browser (like ClickUp).

---

### Step 7 — Set up .env file

1. If `.env` exists and already contains `CLICKUP_SETUP_LIST_ID` → do nothing
2. If `.env` exists but does **not** contain `CLICKUP_SETUP_LIST_ID` → append:
   ```

   # ClickUp — ID of the task list (added by setup agent)
   CLICKUP_SETUP_LIST_ID=
   ```
3. If `.env` does not exist but `.env.example` exists and does not contain `CLICKUP_SETUP_LIST_ID` → append as above to `.env.example`
4. If neither `.env` nor `.env.example` exist → create `.env.example` with:
   ```
   # ClickUp — ID of the task list
   CLICKUP_SETUP_LIST_ID=
   ```

---

### Step 8 — Greenfield setup (GREENFIELD mode only)

This step is executed **only** for greenfield projects. For EXISTING and UPDATE, skip to Step 9.

#### 8.1 — Prerequisites

Verify that the following are installed: `node` (v20+), `npm`, `git`. If any are missing, inform the developer and stop.

#### 8.2 — Initialize the project

If `package.json` does not exist:
```bash
npm init -y
```

If `.git` does not exist:
```bash
git init
```

#### 8.3 — Install quality tools

```bash
npm install --save-dev husky lint-staged @commitlint/cli @commitlint/config-conventional prettier eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser
```

Initialize Husky:
```bash
npx husky init
```

Create the git hooks:

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

#### 8.4 — Quality configurations (verbatim download)

Download the boilerplate config files listed in the manifest `boilerplate_files`:
`.commitlintrc.json`, `.prettierrc.json`, `.releaserc.json`, `.eslintrc.base.json`.

For each entry in `boilerplate_files` whose path does **not** start with `.github/` and is **not** `.gitignore`, and only if the destination file does not already exist:

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/boilerplate/<BOILERPLATE_FILE> -H "Accept: application/vnd.github.raw" > <BOILERPLATE_FILE>
```

The destination path equals the source path (e.g. `boilerplate/.prettierrc.json` → `.prettierrc.json` in project root).

If the destination file **already exists**: inform the developer and keep the existing one. **Do not** overwrite a config the developer may have customised.

#### 8.5 — Apply stack profile

Read the downloaded profile file (`.claude/.setup-tmp/profile.md`) and apply the configurations it contains:

1. **Dependencies**: Extract the JSON dependencies block from the profile and install them with `npm install`
2. **ESLint**: If the profile contains an ESLint configuration, create `.eslintrc.json` with that content
3. **TypeScript**: If the profile contains a TypeScript configuration, create `tsconfig.json`
4. **Jest**: If the profile contains a Jest configuration, create `jest.config.ts`

For the **fullstack** stack (multi-project):
- Create the `apps/web/` and `apps/api/` structure
- Apply the web-frontend profile in `apps/web/`
- Apply the backend-node profile in `apps/api/`
- Generate `AGENTS.md`, `CLAUDE.md` and `REGISTRY.md` for each sub-project (as described in Steps 5B and 5b)
- At the root use the workspace template (as described in Step 5B)

#### 8.6 — CI/CD workflow (verbatim download)

Download the GitHub Actions workflow from the manifest `boilerplate_files`:

```bash
mkdir -p .github/workflows
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/boilerplate/.github/workflows/release.yml -H "Accept: application/vnd.github.raw" > .github/workflows/release.yml
```

If `.github/workflows/release.yml` already exists: inform the developer and keep the existing one.

> **Note**: If the developer uses GitLab CI or another provider, adapt the workflow to the project's CI/CD provider while keeping the same steps (checkout, setup, install, semantic-release).

#### 8.7 — .gitignore (verbatim download)

Download the default `.gitignore` from the manifest `boilerplate_files`, only if it does not already exist in the project:

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup/boilerplate/.gitignore -H "Accept: application/vnd.github.raw" > .gitignore
```

If `.gitignore` already exists: inform the developer and keep the existing one.

---

### Step 9 — Cleanup

Remove the staging directory:
```bash
rm -rf .claude/.setup-tmp
```

---

### Step 10 — Summary

Show a summary to the developer in this format:

**For EXISTING:**
```
Setup complete!

Installed files:
  - CLAUDE.md             — entry point for Claude Code (imports AGENTS.md)
  - AGENTS.md             — instructions for AI agents (cross-tool standard)
  - CONSTITUTION.md       — governance rules
  - REGISTRY.md           — feature and service registry
  - .claude/              — settings + skills + agents

Detected stack:
  - Languages:    <languages>
  - Test runner:  <test_command>
  - Linter:       <lint_command>
  - Validation:   <validation_tool>

NOT modified (existing tooling respected):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Next steps:
  1. Fill in CLICKUP_SETUP_LIST_ID in the .env file
  2. Verify MCP: claude mcp list
  3. Use /project:sdd (interactive) or /project:auto-sdd (autonomous) on a ClickUp task
```

**For GREENFIELD:**
```
Setup complete!

Project configuration:
  - CLAUDE.md             — entry point for Claude Code (imports AGENTS.md)
  - AGENTS.md             — instructions for AI agents (cross-tool standard)
  - CONSTITUTION.md       — governance rules
  - REGISTRY.md           — feature and service registry
  - .claude/              — settings + skills + agents
  - .husky/               — git hooks (lint + commit)
  - .eslintrc.base.json   — base ESLint
  - .eslintrc.json        — ESLint <stack> profile
  - .prettierrc.json      — Prettier
  - .commitlintrc.json    — Conventional Commits
  - .releaserc.json       — semantic-release
  - .github/workflows/    — CI/CD (semantic-release)
  - .env.example          — environment variables

Next steps:
  1. Copy .env.example to .env and fill in the variables
  2. Verify MCP: claude mcp list
  3. Use /project:sdd (interactive SDD) or /project:auto-sdd (autonomous SDD) to get started!
```

**For MULTI-PROJECT (EXISTING):**
```
Setup complete! (Multi-project detected: <tool>)

Root files:
  - CLAUDE.md             — entry point for Claude Code
  - AGENTS.md             — general rules + workspace map
  - CONSTITUTION.md       — governance rules
  - .claude/              — settings + skills + agents

Configured sub-projects:
  <sub-project-path>/:
    - AGENTS.md           — stack: <stack>
    - CLAUDE.md           — local entry point
    - REGISTRY.md         — feature registry

NOT modified (existing tooling respected):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Next steps:
  1. Fill in CLICKUP_SETUP_LIST_ID in the .env file
  2. Verify MCP: claude mcp list
  3. Use /project:sdd (interactive) or /project:auto-sdd (autonomous) on a ClickUp task
```

---

## Important notes

- **Verbatim**: skills, agents, and settings.json must be copied exactly as downloaded. Do not generate the content of these files — download and copy it.
- **Conflict detection**: Always ask before overwriting existing files.
- **Existing tooling**: In EXISTING mode, do not install or modify: git hooks, linter, formatter, CI/CD, .gitignore, dependencies. Only graft the AI workflow.
- **Download errors**: If `gh api` returns an error (e.g. 404, 401) or an empty file, inform the developer and stop. Do not proceed with partial content.
- **Authentication**: The developer must be authenticated with `gh auth login`. If `gh auth status` fails, stop and ask them to authenticate.
