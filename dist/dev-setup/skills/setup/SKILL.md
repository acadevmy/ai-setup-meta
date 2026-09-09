---
name: setup
description: AI-Native setup for software development projects. Detects the mode (UPDATE/GREENFIELD/EXISTING), auto-detects the stack and configures the project with governance, MCP and workflow.
model: opus
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Dev Setup

Skill that grafts the AI-Native workflow onto software development projects.
Resources are bundled in the plugin — no remote download needed.

---

## Local resources

All template files are available under:
```
${CLAUDE_SKILL_DIR}/templates/
```

It contains: AGENTS.template.md, REGISTRY.md, .env.example, .gitignore, settings.json, settings.user.json, profiles/, rules/

The deterministic work is done by the plugin scripts, not re-derived from this
prose on every run. They live at `${CLAUDE_PLUGIN_ROOT}/scripts/` and all speak
the same contract: `--json` prints a flat object with `UPPER_SNAKE` keys, a
missing value is the empty string, diagnostics go to stderr.

---

## Reading strategy

Files fall into two categories:

- **Verbatim**: read from the plugin and written straight to their final destination (REGISTRY, settings, .gitignore, .env.example). Conflict detection runs before every write.
- **Transformed**: read from the plugin, transformed in memory, then written to their final destination. This covers: the AGENT template (placeholder substitution), the rule templates (rendered by `render-template.sh`), profiles (configuration extraction).

**IMPORTANT**: skills and agents are NOT installed into the project. They are provided by the plugin itself and available automatically.

---

## Full procedure

Run the following steps **in the order given**. Do not skip any step.

### Step 1 — Detect the mode

Analyze the current project to determine the operating mode:

1. **UPDATE** — If `.claude/settings.json` already exists in the project root and the project has either `.claude/rules/dev-setup-core.md` or a legacy `CONSTITUTION.md`, setup has already run. Ask the developer: "Setup has already run. Do you want to update the files from the source repository?" If they say no, stop.

2. **GREENFIELD** — If none of these files exist in the project root: `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `pubspec.yaml`, `Cargo.toml`, and there are no significant source files (no `.ts`, `.js`, `.py`, `.go`, `.dart`, `.rs` file outside config). The project is empty or just initialized.

3. **EXISTING** — In every other case. The project has existing code.

Report the detected mode to the developer before proceeding.

---

### Step 2 — Stack auto-detection (EXISTING mode only)

If the mode is EXISTING, analyze the project to detect:

#### Language
- `package.json` present → **node**
- `pyproject.toml` or `requirements.txt` or `setup.py` present → **python**
- `go.mod` present → **go**
- `pubspec.yaml` present → **flutter**
- `Cargo.toml` present → **rust**
- Any `*.tf` file in the root or in a direct subdirectory (depth ≤ 2) → **terraform**
- None of the above → **unknown**

Several languages can coexist (e.g. node + python, or node + terraform for a full-stack monorepo).

#### Test runner
Look in this order:
1. `package.json` with a `test` script → if it contains `vitest` use `npx vitest`, otherwise `npm test`
2. `pytest.ini` or `pyproject.toml` with `[tool.pytest]` → `pytest`
3. `go.mod` → `go test ./...`
4. `pubspec.yaml` → `flutter test`
5. `Cargo.toml` → `cargo test`
6. Detected languages include `terraform` → `terraform validate` (note: Terraform has no classic test runner; `terraform validate` is the closest built-in. The `terraform.md` profile documents `terraform test` 1.6+ and Terratest as options)
7. None found → `not detected`

#### Linter
Look in this order:
1. An `.eslintrc*` or `eslint.config*` file, or `eslint` in `package.json` → if there is a `lint` script use `npm run lint`, otherwise `npx eslint .`
2. `pyproject.toml` with `[tool.ruff]` → `ruff check .`
3. `.flake8` or `setup.cfg` with `[flake8]` → `flake8`
4. `.golangci.yml` → `golangci-lint run`
5. `analysis_options.yaml` → `dart analyze`
6. `Cargo.toml` → `cargo clippy`
7. Detected languages include `terraform` → `terraform fmt -check -recursive`
8. None found → `not detected`

#### Validation tool
1. `pubspec.yaml` present → **freezed + json_serializable** (immutable models and schema-driven serialization, no Zod)
2. `package.json` with: `zod` → **Zod**, `joi` → **Joi**, `yup` → **Yup**, `class-validator` → **class-validator**
3. `pyproject.toml` or `requirements.txt` with `pydantic` → **Pydantic**
4. None found → `not detected`

#### Frontend detected?
- `package.json` contains `next`, `react`, `@angular/core`, `vue`, `nuxt`, or `svelte` → **yes**
- Or: `.tsx`, `.jsx`, or `.vue` files exist under `src/` → **yes**
- Otherwise → **no**

#### Frontend framework detected?
Only if "Frontend detected?" → **yes**. Identify the main framework and its version (used by Step 5 for framework-specific patterns such as the Next.js AGENTS.md block).

- `package.json` contains `next` → **nextjs**
- `package.json` contains `nuxt` → **nuxt**
- `package.json` contains `@angular/core` → **angular**
- `package.json` contains `vue` (without `nuxt`) → **vue**
- `package.json` contains `svelte` → **svelte**
- `package.json` contains `react` (without `next`/`@angular/core`/`vue`/`nuxt`/`svelte`) → **react**
- Otherwise → `not detected`

When the framework is detected, also read the version from `dependencies.<pkg>` or `devDependencies.<pkg>` and parse major.minor (e.g. `"next": "^16.0.7"` → `16.0`; `"next": "~17.2.0"` → `17.2`). Save as `{FRAMEWORK_FRONTEND}` and `{FRAMEWORK_FRONTEND_VERSION}`.

#### Check current AI-tooling conventions (for every detected framework)

The state of the art for `AGENTS.md` conventions (and equivalents) moves fast — the profiles hard-coded in `profiles/<framework>.md` reflect the state at plugin release, but new frameworks and recent versions introduce extra patterns the plugin does not know about yet. For every detected framework (`{FRAMEWORK_FRONTEND}`, the backend framework if applicable, infrastructure frameworks such as Terraform, and so on) query the current documentation to discover AI-tooling conventions.

**Lookup strategy** (in order; the first source that produces a result wins):

1. **`ctx7` CLI** on PATH, or via `npx ctx7@latest` if not installed:
   - `ctx7 library <framework>` to resolve the ID (e.g. `/vercel/next.js`)
   - `ctx7 docs <id> "AGENTS.md convention bundled docs agent rules"` for the query
2. **Context7 MCP**, only if the project registered it (it is not in the default configuration, see Step 6.2): `mcp__context7__resolve-library-id` + `mcp__context7__query-docs` with the same query
3. **WebSearch** if neither ctx7 nor Context7 is available: query `"AGENTS.md convention <framework> <major>.<minor>"` (e.g. `"AGENTS.md convention next.js 16.2"`), preferring results from the framework's official domain
4. **Skip** if no source is reachable (offline environment) — proceed with the hard-coded profiles alone and report the skip in the Step 9 summary

**What to look for**, for each framework:

- Is there an `AGENTS.md` convention officially supported by the framework (e.g. the `BEGIN:nextjs-agent-rules` block in Next.js)?
- Which markers / sections does the framework manage automatically (e.g. through a `<framework> upgrade` command)?
- Path of the bundled docs (if applicable, e.g. `node_modules/<framework>/dist/docs/`)
- Codemods or related tooling for existing projects (e.g. `npx @next/codemod@latest agents-md`)
- Minimum framework version that supports the convention

**Source precedence**:

- Hard-coded profile (`profiles/<framework>.md`) → primary source for frameworks documented at plugin release (deterministic, predictable)
- Runtime check → additional source for frameworks not yet documented in the plugin **or** for newer versions that introduced new conventions

Save any discovered convention as `{FRAMEWORK_AGENTS_CONVENTION}` (a structured object with: marker name, block content, source, doc link) — Step 5 applies them as a framework-specific block injection using the same strategy documented for Next.js.

**Output to the developer**: one line in the Step 9 summary per checked framework, in this format:
```
- <framework> <version>: convention <name> found via <source> → <action applied>
- <framework> <version>: no documented AI-tooling convention → no action
- <framework> <version>: check skipped (offline) → hard-coded profile only
```

#### Mobile detected?
- `pubspec.yaml` present → **yes**
- `package.json` contains `react-native` or `expo` → **yes**
- Otherwise → **no**

#### Mobile framework detected?
- `pubspec.yaml` present → **flutter**
- otherwise, `package.json` contains `react-native` or `expo` → **react-native**
- otherwise → `not detected`

#### Infrastructure detected?
- Detected languages include `terraform` → **yes**
- Otherwise → **no**

This flag derives from language detection and decides whether Step 4 generates the Terraform rule.

#### Multi-project detected?

**Phase 1 — Monorepo tool**:
- `nx.json` present → **yes** (Nx)
- `turbo.json` present → **yes** (Turborepo)
- `pnpm-workspace.yaml` present → **yes** (pnpm workspace)
- `lerna.json` present → **yes** (Lerna)
- Root `package.json` contains a `workspaces` field → **yes** (Yarn/npm workspaces)

**Sub-project enumeration** (in priority order; the first one that produces results is the one to use):
1. `pnpm-workspace.yaml` → read `packages:` (a list of globs)
2. Root `package.json` → read the `workspaces` field (an array of globs)
3. `lerna.json` → read `packages` (a list of globs)
4. `nx.json` → read `projects` ONLY if the field exists (legacy, Nx ≤ 17). From Nx 18+ the field is gone: projects are inferred from `package.json`/`project.json` under the workspace paths (the "inferred projects" model). In that case use one of the previous sources.
5. `turbo.json` → projects are inferred from the pnpm/yarn/npm workspaces; Turborepo keeps no list of its own.

Expand the globs into actual directories containing a `package.json`. Optional cross-check: if the Nx CLI is available in `node_modules/.bin` or on PATH, run `pnpm nx show projects` (or `npx nx show projects`) and compare the inferred list against the CLI output.

For each sub-project, read its `package.json`:
- `name` → the project identifier (used both for the display path and for command wrapping, see below)
- `scripts` → available commands (`dev`, `build`, `test`, `lint`, ...)
- `dependencies` / `devDependencies` → drivers for stack detection
- Any `nx` field (per-target inputs/outputs/cache) → informational, it does not change the invocation

**Phase 2 — Structural detection** (only if Phase 1 found nothing):
- Look in the top-level directories for project marker files: `package.json`, `pubspec.yaml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`
- If **2 or more** directories contain at least one marker → **yes** (multi-project)
- Ignore common non-project directories: `node_modules`, `.git`, `.claude`, `dist`, `build`, `coverage`, `.github`, `.husky`

**If multi-project is detected** (from Phase 1 or Phase 2):
1. For every sub-project found, run stack auto-detection (Language, Test runner, Linter, Validation tool, Frontend detected?, Mobile detected?) inside the sub-project directory, reading its `package.json` (if present) for `scripts`, `dependencies`, `devDependencies`.
2. **Command wrapping**: in multi-project mode the commands must be runnable from the workspace root, not only from the sub-project folder. When populating `{{TEST_COMMAND}}` / `{{LINT_COMMAND}}` (and any other command) in the per-project template, use the wrapped form matching the detected monorepo tool:
   - **Nx** → `nx run <name>:<target>` (preferred when the target is defined in `nx.json` `targetDefaults` or in `package.json` `nx.targets`); fallback `pnpm --filter <name> <script>` (or the package manager equivalent)
   - **pnpm workspace** (without Nx) → `pnpm --filter <name> <script>`
   - **Yarn workspace** → `yarn workspace <name> <script>`
   - **npm workspace** → `npm run <script> --workspace=<name>`
   - **Lerna** → `lerna run <script> --scope=<name>`
   - Non-Node sub-projects (e.g. Terraform under `iac/`) → raw command, run from the sub-project directory (no wrapping).
3. Show the summary to the developer and ask for confirmation before proceeding.

**Show the detection summary to the developer.**

For a single project:
```
Detected stack:
  Languages:      node
  Test runner:    npm test
  Linter:         npm run lint
  Validation:     Zod
  Frontend:       yes
  Mobile:         no
  Infrastructure: no
```

For multi-project (commands are already wrapped so they run from the workspace root):
```
Detected stack:
  Multi-project:  yes (Nx + pnpm workspace)
  Sub-projects:
    applications/web/   — node, frontend: yes, test: pnpm --filter web test, lint: pnpm --filter web lint
    applications/api/   — node, frontend: no, test: pnpm --filter api test, lint: pnpm --filter api lint
    iac/                — terraform, infrastructure: yes, test: terraform validate, lint: terraform fmt -check -recursive

Do you confirm these sub-projects? (yes/no)
```

---

### Step 2b — Stack selection (GREENFIELD mode only)

If the mode is GREENFIELD, ask the developer to pick the stack:

1. **Web Frontend** — Next.js / Angular / React + ShadCN/UI + Tailwind
2. **Backend Node** — Node.js / NestJS + Prisma + Zod
3. **Mobile** — Flutter / React Native (Expo)
4. **Full-stack** — Frontend + Backend (monorepo)
5. **Infrastructure / Terraform** — HCL, remote state (S3 default), AWS/Azure/GCP

If they pick **Mobile**, also ask:
- **Flutter**
- **React Native (Expo)**

If they pick **Infrastructure / Terraform**: set `languages=[terraform]`, `infrastructure=yes`. **Important note**: Step 8 (greenfield setup) does **not** apply Terraform-specific boilerplate in this version (no auto-generated Terraform `.gitignore`, no auto-emitted Terraform CI workflow, no `versions.tf` scaffold). The `terraform.md` profile carries the CI recipes and the S3 backend as reference text to copy. Report this limitation to the developer in the Step 9 summary.

---

### Step 2c — VCS detection

Determine the project's Git provider. The result drives Steps 5, 8.4, 8.6 and 9.

1. Try reading the remote URL:
   ```bash
   git -C <project-root> remote get-url origin 2>/dev/null
   ```
   If `origin` does not exist, use the first available remote (`git remote | head -1`).

2. If there is no `.git` or no remote configured:
   - `vcs = none`
   - Tell the developer: "No Git remote detected. VCS-specific files (CI, `.releaserc.json`) will not be installed."
   - Skip to Step 3.

3. Otherwise, lowercase the URL and classify:
   - Contains `github.com` → `vcs = github`
   - Contains `gitlab` (any host, e.g. `gitlab.com`, `gitlab.company.internal`) → `vcs = gitlab`
   - Neither → go to point 4 (CLI probe).

4. **CLI probe** for ambiguous self-hosted instances (e.g. `git@git.company.com:...`):
   - Extract the hostname from the URL (handle both HTTPS and SSH).
   - Run `gh auth status --hostname <host> 2>/dev/null` and `glab auth status --hostname <host> 2>/dev/null`.
   - If exactly one of them recognizes the host → `vcs = <that one>`.
   - If neither or both do → ask the developer with `AskUserQuestion`:
     ```
     question: "Which Git provider does this project use?"
     options: [ {label: "GitHub"}, {label: "GitLab"}, {label: "Other / none"} ]
     ```
   - If they pick "Other / none" → `vcs = other` (treated the same as `none` for VCS-specific files).

5. Report the detected VCS to the developer before proceeding. Save the value — it is referenced as `{VCS}` in the following steps.

---

### Step 3 — Install resources from the plugin

Read the template files from the plugin and install them into the project.

#### 3.1 — Transformed files (read into memory)

These files need adapting. Read them from the plugin:

**Rule templates** (rendered in Step 4): they stay on disk — `render-template.sh`
reads them itself, so there is nothing to load into context here. They live in
`${CLAUDE_SKILL_DIR}/templates/rules/`.

**AGENTS template** (will be processed in Step 5):

For a single project:
Read `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md`

For multi-project (or the fullstack stack):
Read `${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md`
Read `${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`

**Stack profile** (GREENFIELD only, applied in Step 8.5):
Read the selected profile from `${CLAUDE_SKILL_DIR}/templates/profiles/`:
- Web Frontend: `profiles/web-frontend.md`
- Backend Node: `profiles/backend-node.md`
- Mobile: `profiles/mobile.md`
- Full-stack: read both `profiles/web-frontend.md` and `profiles/backend-node.md`

#### 3.2 — Verbatim files (straight to destination)

These files are copied exactly. Before every write, check whether the destination file already exists (**conflict detection**): if it does, tell the developer and keep the existing one, skipping the write.

**settings.json** (project permissions + Bash sandbox):
If `.claude/settings.json` does **not** exist:
```bash
mkdir -p .claude
```
Read `${CLAUDE_SKILL_DIR}/templates/settings.json` and write it to `.claude/settings.json`.
If it **already exists**: tell the developer and keep the existing one.

The file carries a `sandbox` block that turns on OS-level filesystem and network
isolation for every Bash command Claude runs (Seatbelt on macOS, bubblewrap on
Linux/WSL2). It denies reads and writes of the `.env` family, denies reads of
`~/.ssh`, `~/.aws` and `~/.kube`, unsets the usual token variables inside
sandboxed commands, and pre-allows a small set of network domains that Step 3.4
adapts to this project. **The file that follows this step is the security
boundary of the project: from here on, you cannot read or write `.env`, and
neither can the shell commands you run.** That is intentional — Steps 6 and 7
below are written to work without ever touching it.

`.claude/settings.user.json` is **not** installed here: it is a user-scope
snippet, handled in Step 3.5.

**If the project's own test or dev command loads one of the denied files**, the
sandbox will break it — the deny covers every sandboxed command, not just the ones
Claude writes. Tell the developer, and fix it by deleting that filename from
`sandbox.filesystem.denyRead` in `.claude/settings.json`. A `denyRead` entry cannot
be re-opened from another settings file: `.claude/settings.local.json` can only add
denies, never remove them. The `credentials.envVars` block stays either way, so the
token variables remain unset inside sandboxed commands.

**REGISTRY.md**:

For a single project:
If `REGISTRY.md` does **not** exist (or the developer confirms the overwrite):
Read `${CLAUDE_SKILL_DIR}/templates/REGISTRY.md` and write it to `REGISTRY.md`.

For multi-project:
Generate one `REGISTRY.md` per confirmed sub-project. Do not generate a REGISTRY.md at the root.
Read `${CLAUDE_SKILL_DIR}/templates/REGISTRY.md` and write it to `<sub-project-path>/REGISTRY.md`.

**.gitignore**:
If `.gitignore` does **not** exist:
Read `${CLAUDE_SKILL_DIR}/templates/.gitignore` and write it to `.gitignore`.

**.env.example**:
If `.env.example` does **not** exist:
Read `${CLAUDE_SKILL_DIR}/templates/.env.example` and write it to `.env.example`.

**IMPORTANT**: write the files you read **exactly as received**, with no changes. Do not reformat, do not adjust, do not improve. The content must be verbatim.

**Check**: verify that the written files are not empty. If a file is empty, tell the developer and stop.

---

#### 3.3 — Adapt the allowlist to the detected package manager

The `.claude/settings.json` template lists all three Node package managers (`Bash(npm *)`, `Bash(pnpm *)`, `Bash(yarn *)`) in the `allow` array, because at plugin release we do not know which one you will use. If the project has a single unambiguous lock file, narrow the allowlist to the PM in use — an agent must not invoke `yarn install` in a pnpm project and bypass the workspace/hoisting conventions.

**Skip if**:
- `.claude/settings.json` already existed at 3.2 and was not overwritten (conflict detection left it intact — post-hoc edits are not yours to make).
- The languages detected in Step 2 do NOT include `node` (e.g. a pure Python/Go/Terraform project): the 3 entries stay to support the occasional `npx <tool>`.

**Package manager detection**:

| Lock file found in root | Package manager |
|---|---|
| `pnpm-lock.yaml` | **pnpm** |
| `yarn.lock` | **yarn** |
| `package-lock.json` | **npm** |
| More than one lock file | **ambiguous** — do not touch the allowlist, report the anomaly in the Step 9 summary |
| No lock file (`package.json` exists but the project has not been `install`-ed yet) | **none** — leave all three entries, report it in the Step 9 summary |

**Allowlist changes** (only if the PM is detected and unambiguous):

- `pnpm` → keep `Bash(pnpm *)`, remove `Bash(npm *)` and `Bash(yarn *)`.
- `yarn` → keep `Bash(yarn *)`, remove `Bash(npm *)` and `Bash(pnpm *)`.
- `npm` → keep `Bash(npm *)`, remove `Bash(yarn *)` and `Bash(pnpm *)`.

**Do not add `Bash(npx *)`, `Bash(pnpx *)`, `Bash(node *)` or `Bash(claude *)`.**
They were removed from the template on purpose: each of them executes arbitrary
code chosen at call time, so an allow rule for them is an allow rule for
everything — including `claude --dangerously-skip-permissions`. One-shot tools
such as `npx ctx7@latest` or `npx @next/codemod@latest` still work: with the
sandbox on, a command that stays inside the filesystem and network boundary runs
without a prompt anyway (`sandbox.autoAllowBashIfSandboxed`), and one that leaves
it is exactly the case that deserves a prompt.

**Leave the deny and ask arrays intact**: do NOT touch them. `Bash(npm publish*)`,
`Bash(pnpm publish*)`, `Bash(yarn publish*)` all stay — an accidental `publish`
through the "wrong" PM is still an event worth blocking — and the `ask` entries
are the human checkpoints on `gh pr create` / `glab mr create` and on ClickUp
writes.

**Implementation (jq, idempotent, preserves the rest of the file)**:

```bash
# Detected PM == "pnpm"
jq '.permissions.allow -= ["Bash(npm *)", "Bash(yarn *)"]' \
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

`jq` is already a declared dependency of the plugin (see `scripts/build-plugin.sh`), so assuming it is present is reasonable.

**Report in the Step 9 summary** (a single line):
- Unambiguous PM detected: `allowlist tightened to <pm>-only commands per detected lock file (<lockfile>)`
- Multiple lock files: `multiple lock files detected (<list>) — allowlist left as default; consider committing to a single PM`
- No lock file but `node` detected: `no lock file present — allowlist left as default; the team should run \`<pm> install\` and re-run setup to tighten`

---

#### 3.4 — Compose the sandbox network allowlist

The template ships a deliberately small `sandbox.network.allowedDomains`. Rewrite
it from what Steps 2 and 2c detected, so the project pre-allows the registries and
the forge it actually uses and nothing else.

**Skip if** `.claude/settings.json` already existed at 3.2 and was not overwritten.

Start from an empty list and add the rows that apply:

| Condition | Domains to add |
|---|---|
| `node` among the detected languages | `registry.npmjs.org` |
| Package manager is `yarn` | `registry.yarnpkg.com` |
| `python` detected | `pypi.org`, `files.pythonhosted.org` |
| `dart` / Flutter detected | `pub.dev`, `storage.googleapis.com` |
| `go` detected | `proxy.golang.org`, `sum.golang.org` |
| Terraform detected | `registry.terraform.io`, `releases.hashicorp.com` |
| `{VCS}` == `github` | `github.com`, `api.github.com`, `codeload.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com` |
| `{VCS}` == `gitlab`, host `gitlab.com` | `gitlab.com` |
| `{VCS}` == `gitlab`, self-hosted | the host from the remote URL (e.g. `gitlab.company.internal`) |
| `CLICKUP_SETUP_LIST_ID` set (see Step 6.1) | `api.clickup.com` |

**Implementation (jq, replaces the list wholesale)**:

```bash
# Example: Node + pnpm project on GitHub with ClickUp configured
DOMAINS='["registry.npmjs.org","github.com","api.github.com","codeload.github.com","objects.githubusercontent.com","raw.githubusercontent.com","api.clickup.com"]'
jq --argjson d "$DOMAINS" '.sandbox.network.allowedDomains = $d' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

A domain missing from the list is not a hard failure: the first time a sandboxed
command needs it, Claude Code asks the developer, and answering "Yes, and don't ask
again" records it in `.claude/settings.local.json`. The list only removes the
prompts the project is guaranteed to hit. (Step 3.5 changes that prompt into a
deny.)

**Report in the Step 9 summary** (a single line):
`sandbox network allowlist: <n> domains (<pm registry>, <vcs host>[, api.clickup.com])`

---

#### 3.5 — Credential masking (user scope, optional)

Three sandbox keys are ignored when they come from a repository's
`.claude/settings.json` or `.claude/settings.local.json`, because they widen what
a project can do to the developer's machine: `sandbox.credentials.*` entries with
`"mode": "mask"`, `sandbox.network.tlsTerminate`, and
`sandbox.network.strictAllowlist`. Shipping them in the project template would
produce a config that reads as protection and enforces nothing — so they live in
`~/.claude/settings.json` instead, and the developer installs them.

**You must not write `~/.claude/settings.json` yourself.** It is a protected path:
print the command and let the developer run it.

Ask the developer with `AskUserQuestion`:

```
question: "How do gh/glab/npm authenticate on this machine?"
options:
  - label: "Interactive login"    (gh auth login / glab auth login — no token in the environment)
  - label: "Environment token"    (GH_TOKEN / GITLAB_TOKEN / NPM_TOKEN exported in the shell)
```

- **Interactive login** → nothing to install. The project settings already unset those
  variables inside sandboxed commands, and the CLIs keep working from their own
  credential store. Report it in the Step 9 summary and move on.
- **Environment token** → the project settings would break those CLIs inside the
  sandbox, because `"mode": "deny"` unsets the variable. Replace deny with masking:
  the command sees a per-session placeholder, and the sandbox proxy swaps in the real
  value only on requests to the host you name. Two edits, in this order:

  1. Drop the masked variables from the project deny list — **`deny` wins over `mask`
     in every scope**, so a leftover deny entry silently disables the mask:

     ```bash
     jq '.sandbox.credentials.envVars |= map(select(.name as $n | ["GH_TOKEN","GITLAB_TOKEN","NPM_TOKEN"] | index($n) | not))' \
       .claude/settings.json > .claude/settings.json.tmp \
       && mv .claude/settings.json.tmp .claude/settings.json
     ```
     Keep the entries for the variables the project does not authenticate with.

  2. Give the developer this command to merge the snippet into their user settings
     (it is `${CLAUDE_SKILL_DIR}/templates/settings.user.json`, printed here so they
     can review it before running anything):

     ```bash
     jq -s '.[0] * .[1]' ~/.claude/settings.json <snippet-path> > /tmp/cc-settings.json \
       && mv /tmp/cc-settings.json ~/.claude/settings.json
     ```

     Trim the snippet to the variables and hosts that apply before printing it — an
     `injectHosts` entry authorizes the proxy to send a real credential to that host.

     The snippet also sets `network.strictAllowlist`, which turns "prompt for an
     unknown domain" into "deny it". Tell the developer they can drop that key to keep
     the prompt.

**Report in the Step 9 summary** (a single line):
- Interactive login: `credential masking not needed — gh/glab authenticate from their own store`
- Environment token: `credential masking snippet printed for ~/.claude/settings.json (GH_TOKEN, ...); project deny entries removed for the masked variables`

---

#### 3.6 — Git over the sandbox: SSH remotes

Sandboxed commands reach the network **only** through the sandbox's HTTP(S) proxy.
There is no raw TCP and no DNS for anything else, so a `git fetch` or `git push` against
an `ssh://` or `git@host:` remote fails inside the sandbox — the hostname does not even
resolve. This is a property of the sandbox, not of the deny rules: it applies to every
project whose `origin` is an SSH URL.

Check the remote read in Step 2c:

```bash
git remote get-url origin
```

If it starts with `git@` or `ssh://`, tell the developer and let them pick with
`AskUserQuestion`:

```
question: "origin is an SSH remote. Inside the Bash sandbox, git cannot reach it. How do you want to handle it?"
options:
  - label: "Switch to HTTPS"   (recommended — the forge CLI holds the credentials)
  - label: "Keep SSH"          (git network commands run outside the sandbox)
```

- **Switch to HTTPS** → print these for the developer to run; the credential helper keeps
  the token out of the URL and out of `ps`:

  ```bash
  # GitHub
  gh auth login && gh auth setup-git
  git remote set-url origin https://github.com/<org>/<repo>.git

  # GitLab
  glab auth login
  git config --global credential.helper '!glab auth git-credential'
  git remote set-url origin https://<host>/<group>/<repo>.git
  ```

  Make sure the HTTPS host is in the `sandbox.network.allowedDomains` written at Step 3.4.

- **Keep SSH** → nothing to change. `git fetch`/`git push` will hit a sandbox violation and
  Claude Code will retry them outside the sandbox, which sends them through the normal
  permission flow: in Manual mode the developer confirms each one. The `deny` rules on
  force push and on the protected branches still apply — they are permission rules, and
  they are evaluated whether or not the command runs sandboxed.

**Report in the Step 9 summary** (a single line):
- HTTPS remote: `origin already on HTTPS — git works inside the sandbox`
- Switched: `switch origin to HTTPS: <command printed>`
- Kept SSH: `origin left on SSH — git network commands will run unsandboxed, with a confirmation each time`

---

### Step 4 — Generate the path-scoped rules

The project's governance is not one document read in full at every session: it
is a set of files under `.claude/rules/`, each declaring in its frontmatter the
globs it applies to. The harness injects a rule when the model touches a file
that matches, which means the match is deterministic, costs nothing on the
sessions that never touch those files, and survives compaction.

Only `core.md` has no `paths:` — it is the one that loads unconditionally, and it
holds only what is unsafe to discover late (secrets, untrusted content,
supply chain, the gates). Everything else arrives with the file it applies to.

#### 4.1 — Read the stack once

```bash
mkdir -p .claude
${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh --json > .claude/.stack.json
```

Everything in this step reads from that object; 4.3 deletes it. It is a scratch
file, not project state — do not commit it and do not add it to `.gitignore`.

#### 4.2 — Pick the rules this project needs

| Template | Generated as | Generate when |
|---|---|---|
| `core.md` | `dev-setup-core.md` | always |
| `code-style.md` | `dev-setup-code-style.md` | always |
| `typescript.md` | `dev-setup-typescript.md` | `LANG` contains `node`, or a `tsconfig.json` exists |
| `nestjs.md` | `dev-setup-nestjs.md` | `FRAMEWORKS` contains `nestjs` |
| `react.md` | `dev-setup-react.md` | `FRAMEWORKS` contains `nextjs` or `react` |
| `react-native.md` | `dev-setup-react-native.md` | `FRAMEWORKS` contains `expo` or `react-native` |
| `vue.md` | `dev-setup-vue.md` | `FRAMEWORKS` contains `nuxt` or `vue` |
| `flutter.md` | `dev-setup-flutter.md` | `FRAMEWORKS` contains `flutter` |
| `dart-analysis.md` | `dev-setup-dart-analysis.md` | `FRAMEWORKS` contains `flutter` |
| `terraform.md` | `dev-setup-terraform.md` | `HAS_INFRA` is `true` |
| `tests.md` | `dev-setup-tests.md` | `TEST_CMD` is non-empty, or the mode is GREENFIELD |
| `backend-services.md` | `dev-setup-backend-services.md` | `SERVICES_GLOB` is non-empty |

`core.md` and `code-style.md` are both generated every time, but only `core.md`
loads unconditionally: `code-style.md` declares source-file globs, so a session
spent on documentation or configuration never pays for it.

**Multi-project**: the table is evaluated against the union of the sub-projects —
a workspace holding a Next app and a NestJS API gets both `dev-setup-react.md`
and `dev-setup-backend-services.md`. The rules live in the workspace root's
`.claude/rules/`, and the globs (`**/*.tsx`, `**/*.service.ts`) already restrict
each one to the right sub-tree.

Do not generate a rule for a stack the project does not have. That is the whole
point of this step: a Flutter project must not carry the React rule, and a Next
project must not carry the Terraform one.

#### 4.3 — Render them

```bash
mkdir -p .claude/rules

# One call per rule selected above.
${CLAUDE_PLUGIN_ROOT}/scripts/render-template.sh \
  --in "${CLAUDE_SKILL_DIR}/templates/rules/<template>.md" \
  --out ".claude/rules/dev-setup-<template>.md" \
  --vars-json .claude/.stack.json
```

`backend-services.md` is the only template with a placeholder: `{{SERVICES_GLOB}}`,
which `detect-stack.sh` resolved from the project's layout. The others render
unchanged — passing `--vars-json` anyway keeps the command identical for every
rule and makes an accidentally-added placeholder an error instead of a
`{{PLACEHOLDER}}` shipped into the project.

**Check**: `render-template.sh` exits non-zero on an unresolved placeholder. If
it does, stop and report — do not write the file by hand.

When every rule is written, remove the scratch file:

```bash
rm -f .claude/.stack.json
```

#### 4.4 — The `dev-setup-` prefix is the contract

Everything this skill writes into `.claude/rules/` is named `dev-setup-*.md`.
Everything the project's own team writes there is not. That single convention is
what makes UPDATE mode safe:

- **GREENFIELD / EXISTING** — write the selected rules. If a `dev-setup-*.md`
  already exists, apply conflict detection: tell the developer and keep theirs.
- **UPDATE** — regenerate every `dev-setup-*.md` the table selects, overwriting
  without asking (they are generated artefacts, and this is what the developer
  asked for). Then delete the `dev-setup-*.md` files the table did **not**
  select: they belong to a stack this project no longer has. **Never** touch a
  file in `.claude/rules/` whose name does not start with `dev-setup-` — those
  are the project's own rules.

#### 4.5 — Migrating a project that still has CONSTITUTION.md

Earlier versions of this setup copied a single `CONSTITUTION.md` into the project
root. If one is there:

1. Generate the rules as above.
2. Tell the developer the file is superseded, and show what replaced it: the
   governance now lives in `.claude/rules/`, and the mechanical parts of it
   (function length, naming, `any`, coverage floors, who may push to the
   reference branch) moved into ESLint, the test runner and branch protection.
3. Ask before deleting it — a team may have added its own rules to that file.
   If they say no, leave it and note that it is no longer read by anything.

---

### Step 5 — Generate AGENTS.md

#### 5A — Single project (not multi-project)

Read the content from `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md` and substitute the placeholders.
The template is the same for every mode: only the source of the values changes.

**Placeholder values for EXISTING mode:**

- `{{STACK_DESCRIPTION}}` → a compact description of the detected stack. Format: `Detected stack: languages[, test: test_command][, linter: lint_command][, validation: tool]`
  - Example: `Detected stack: **node**, test: npm test, linter: npm run lint, validation: Zod`
  - If test/linter/validation are `not detected`, omit them from the string
  - Add the note: `> This stack was detected automatically. If it is wrong, update this section manually.`
- `{{TEST_COMMAND}}` → the detected test command (e.g. `npm test`, `pytest`, `not detected`)
- `{{LINT_COMMAND}}` → the detected linter command (e.g. `npm run lint`, `ruff check .`, `not detected`)
- `{{TYPECHECK_COMMAND}}` → the detected type-check command. For Node projects with a `tsconfig.json`, read `package.json.scripts.typecheck` or `package.json.scripts['type-check']`; if they are missing, use `tsc --noEmit`. For other stacks, leave `not detected`.
- `{{QUALITY_COVERAGE_TARGET}}` → the coverage threshold. Default: `80%` with the comment `(industry baseline; adjust if your team has set a different bar)`. If `package.json` or the test runner config exposes an explicit threshold, use that one.
- `{{VCS_OPS_NOTE}}` → an informational line about the Git provider detected in Step 2c. Pick one of the following based on `{VCS}`:
  - `github` → `> GitHub operations (branch, PR, commit) are performed with the \`gh\` CLI.`
  - `gitlab` → `` > GitLab operations (branch, MR, commit) are performed with the `glab` CLI. MR descriptions follow `.gitlab/merge_request_templates/Default.md` when present. ``
  - `none` / `other` → `` > Git operations via the `git` CLI. No remote provider configured. ``

**Project Identity (interactive, EXISTING and GREENFIELD modes):**

Ask ONE single batched question with three sub-fields and collect the answers. Leave `TODO — <hint>` for empty fields — do not invent values.

> Question to ask the developer:
>
> "To fill in the `Project Identity` section of AGENTS.md I need three short pieces of information (press Enter to skip a field and I will leave it as a TODO):
> - **Name**: the project's short name (e.g. 'Acme Web App')
> - **Purpose**: one sentence on what the project does
> - **Primary users**: who uses it (e.g. 'consumer travelers', 'internal ops')"

Substitutions:
- `{{PROJECT_NAME}}` → the developer's answer, or `TODO — short app name`
- `{{PROJECT_PURPOSE}}` → the developer's answer, or `TODO — one-sentence purpose`
- `{{PROJECT_PRIMARY_USERS}}` → the developer's answer, or `TODO — who uses this app`

**Infrastructure (auto-detect + TODO, EXISTING and GREENFIELD modes):**

Attempt auto-detection in the order below; anything not detectable becomes `TODO — <hint>`:

- `{{INFRA_VCS_CI}}` → combine:
  - VCS: parse the remote URL from `.git/config` (`gitlab.com` → `GitLab`, `github.com` → `GitHub`, `bitbucket.org` → `Bitbucket`, `dev.azure.com` → `Azure DevOps`)
  - CI: presence of `.gitlab-ci.yml` → `GitLab CI`; `.github/workflows/` → `GitHub Actions`; `.circleci/config.yml` → `CircleCI`; `bitbucket-pipelines.yml` → `Bitbucket Pipelines`; `azure-pipelines.yml` → `Azure Pipelines`; `Jenkinsfile` → `Jenkins`
  - Result: `<VCS> + <CI>` (e.g. `GitLab + GitLab CI`). If the VCS is detected but the CI is not, write `<VCS>, CI: TODO — which CI provider`.
- `{{INFRA_SECRETS}}` → presence of `dotenv-vault.json` or `.env.vault` → `dotenv-vault`; `*.tfstate` with a `vault` backend → `HashiCorp Vault`; `aws-secretsmanager` or `aws ssm` references in IaC/CI → `AWS Secrets Manager` / `AWS Parameter Store`. Otherwise `TODO — secrets manager (e.g. dotenv-vault, AWS SSM, Vault)`.
- `{{INFRA_HOSTING}}` → a light heuristic from the CI: detect provider names in deploy steps (`vercel`, `netlify`, `aws-eks`, `kubectl`, `gcloud run`, `firebase deploy`). Otherwise `TODO — hosting/deploy target`.
- `{{INFRA_OBSERVABILITY}}` → presence of `datadog.yaml` / a `dd-trace` dependency → `Datadog`; `sentry.client.config.*` or `@sentry/*` in package.json → `Sentry`; `newrelic.{yml,json}` → `New Relic`. Otherwise `TODO — observability tool`.

**Placeholder values for GREENFIELD mode:**

Based on the stack chosen in Step 2b:

| Stack | `{{STACK_DESCRIPTION}}` | `{{TEST_COMMAND}}` | `{{LINT_COMMAND}}` |
|---|---|---|---|
| Web Frontend | `**Web Frontend**: Next.js 16+ / Angular 22+ / React 19+, ShadCN/UI, Tailwind CSS 4, Zod 4, Jest + Testing Library` | `npm test` | `npm run lint` |
| Backend Node | `**Backend Node**: Node.js 24+, NestJS 11+, Zod 4 via nestjs-zod, Jest + Supertest, Prisma` | `npm test` | `npm run lint` |
| Mobile (Flutter) | `**Mobile**: Flutter 3.47+ (BLoC/Riverpod)` | `flutter test` | `dart analyze` |
| Mobile (React Native) | `**Mobile**: React Native with Expo (Zustand/Jotai)` | `npm test` | `npm run lint` |
| Infrastructure (Terraform) | `**Infrastructure**: Terraform — follow the repo's pinned version, remote state with locking + encryption at rest, HashiCorp style guide` | `terraform validate` | `terraform fmt -check -recursive` |

**For UPDATE mode:** regenerate as for EXISTING or GREENFIELD (depending on the project's state).

**Conflict detection**: if `AGENTS.md` already exists, ask the developer before overwriting.

**Framework-specific block — Next.js (the `AGENTS.md` bundled-docs convention)**:

If `{FRAMEWORK_FRONTEND}` == `nextjs`, prepend the canonical Next.js block to the generated `AGENTS.md`, **before** all the template-derived content:

```md
<!-- BEGIN:nextjs-agent-rules -->

# Next.js: ALWAYS read docs before coding

Before any Next.js work, find and read the relevant doc in `node_modules/next/dist/docs/`. Your training data is outdated — the docs are the source of truth.

<!-- END:nextjs-agent-rules -->

```

The `BEGIN:nextjs-agent-rules` / `END:nextjs-agent-rules` markers delimit a section managed by `next upgrade` (Next.js 16.2+): everything between the markers is rewritten on upgrades, everything outside is preserved. Keeping the plugin's content below the `END` marker guarantees `next upgrade` will not overwrite it. For full details see `profiles/nextjs.md`.

Based on `{FRAMEWORK_FRONTEND_VERSION}` (parsed as major.minor, e.g. `16.0`, `17.2`):

- `>= 16.2` → the docs are bundled in `node_modules/next/dist/docs/`. Add to the Step 9 summary: "run `npx next upgrade@canary` periodically to keep the AGENTS.md block current."
- `< 16.2` → the docs are **not** bundled. Add to the Step 9 summary: "run `npx @next/codemod@latest agents-md` to generate the docs in `.next-docs/` and update the path in the block."

**Brownfield**: if `AGENTS.md` already exists and contains a `BEGIN:nextjs-agent-rules` … `END:nextjs-agent-rules` block, do **not** regenerate the inner content. Preserve the block verbatim and append the plugin template below the `END` marker. The inner block is Next.js territory — rewriting it would conflict with the next `next upgrade`.

**Framework conventions discovered at runtime**:

If the Step 2 check populated `{FRAMEWORK_AGENTS_CONVENTION}` for a framework other than Next.js (or for a Next.js version newer than what is documented above), apply the same injection strategy: delimited markers at the top of the file, the plugin's template content below the closing marker. Precedence: hard-coded profile (e.g. the Next.js block above) → runtime convention → no injection. If a hard-coded profile and the runtime check conflict, the profile wins and the runtime convention is reported as "not applied, hard-coded source takes precedence" in the Step 9 summary.

Write the result to `AGENTS.md` in the project root.

#### 5B — Multi-project (or the fullstack stack)

Generate **two levels** of AGENTS.md: one at the root and one per **application** sub-project. Libraries do not get per-project setup files — their usage is cited in the REGISTRY of the application that consumes them (see "Citing consumed libraries" below).

**Sub-project classification (application vs library)**, in priority order:

1. Path matches `applications/*`, `apps/*`, `services/*` → **application**
2. Path matches `libraries/*`, `libs/*`, `packages/*` → **library**
3. `package.json` has `"private": false` AND `"main"`/`"exports"` → **library** (publishable shape)
4. `package.json` has `scripts.dev` or `scripts.start` → **application** (runnable shape)
5. Otherwise → ask the developer (default: **application**)

Save the classification for each sub-project as `{SUBPROJECT_TYPE}`.

**Root AGENTS.md** — use `${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md`:
- `{{WORKSPACE_STRUCTURE}}` → generate a table with ALL confirmed sub-projects (apps + libs), with a `Type` column and a differentiated `Instructions` column:
  ```
  | Project | Type | Path | Stack | Instructions |
  |---|---|---|---|---|
  | web   | application | apps/web/ | Next.js 16+, React 19+ | [apps/web/AGENTS.md](apps/web/AGENTS.md) |
  | api   | application | apps/api/ | Node.js 24+, NestJS 11+ | [apps/api/AGENTS.md](apps/api/AGENTS.md) |
  | shared | library    | libs/shared/ | TypeScript, Zod | (no per-library file — see consuming app REGISTRY) |
  ```
- Below the table, add this note:
  > Libraries do not get per-project setup files. When a library exposes an interesting pattern, ADR, or breaking change, add a `### library/<name>` entry to the **consuming application's `REGISTRY.md`** under "Services and utilities" — that's where library usage is documented.
- `{{PROJECT_NAME}}`, `{{PROJECT_PURPOSE}}`, `{{PROJECT_PRIMARY_USERS}}`, `{{INFRA_VCS_CI}}`, `{{INFRA_SECRETS}}`, `{{INFRA_HOSTING}}`, `{{INFRA_OBSERVABILITY}}`, `{{QUALITY_COVERAGE_TARGET}}`, `{{TEST_COMMAND}}`, `{{LINT_COMMAND}}`, `{{TYPECHECK_COMMAND}}` → follow the same instructions as Step 5A (interactive prompt for Project Identity, auto-detect for Infrastructure). For workspace commands, prefer the build tool's multi-project form: Nx → `nx run-many -t <target>`; plain pnpm workspace → `pnpm -r <script>`; turbo → `turbo run <task>`. If you detect more than one, use the one exposed as a root script in `package.json`.
- Write the result to `AGENTS.md` in the root

**Per-sub-project AGENTS.md** — use `${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`:

**Only for sub-projects with `{SUBPROJECT_TYPE} == 'application'`**, substitute the placeholders:
- `{{PROJECT_NAME}}` → a descriptive name for the sub-project (e.g. "Web Frontend", "Backend API")
- `{{STACK_DESCRIPTION}}` → the sub-project's detected stack (same criteria as 5A)
- `{{TEST_COMMAND}}` → the test runner detected in the sub-project
- `{{LINT_COMMAND}}` → the linter detected in the sub-project
- `{{ROOT_AGENTS_REL_PATH}}` → the relative path to the root (e.g. `../../AGENTS.md`)

Write the result to `<sub-project-path>/AGENTS.md`.

Sub-projects with `{SUBPROJECT_TYPE} == 'library'` do **not** get AGENTS.md / CLAUDE.md / REGISTRY.md.

**Citing consumed libraries** (for every application):

For each sub-project with `{SUBPROJECT_TYPE} == 'application'`, read its `package.json` and identify the workspace dependencies pointing at the monorepo's libraries. A dependency is workspace-resolved when:
- The value is `workspace:*`, `workspace:^`, `workspace:~`, or `workspace:<version>`
- Or the package name matches exactly the `name` of a sub-project with `{SUBPROJECT_TYPE} == 'library'`

For each consumed library, add an entry to `<app>/REGISTRY.md` under "Services and utilities" using this template:

```markdown
### library/<name>

- **Where**: `libraries/<name>/` (or the actual path) — workspace package
- **Used by**: this application (add the other apps that consume it, comma-separated)
- **Summary**: <one line; use the `description` from `<lib>/package.json` if present, or the first meaningful paragraph of the library README; if neither is usable, write "TBD — refine when first touched">
```

This way the AI agent working in the application immediately sees which libraries it uses, where they live, and has a starting point for investigating their content. When the team adds patterns/ADRs that touch a library, they live in the consuming app's REGISTRY and can reference `### library/<name>` as an anchor.

---

### Step 5b — Generate CLAUDE.md

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. To guarantee compatibility with Claude Code
while keeping `AGENTS.md` as the cross-tool standard,
generate a `CLAUDE.md` that references `AGENTS.md`:

```markdown
@AGENTS.md
```

The `CLAUDE.md` file must contain **only** the line above. Do not add any other
content: every instruction must stay in `AGENTS.md` as the single source of truth.

**Conflict detection**: if `CLAUDE.md` already exists, ask the developer before overwriting.

Write the result to `CLAUDE.md` in the project root.

**Multi-project**: generate a `CLAUDE.md` in every confirmed sub-project too, with the same content (`@AGENTS.md`). The sub-project's CLAUDE.md will point at the sub-project's local AGENTS.md.

---

### Step 6 — Configure MCP servers

The plugin declares **no** MCP servers of its own: every server costs context in every
session, so only what the project actually uses gets registered. This step decides
based on the Step 2 detection.

Check whether the `claude` CLI is available with `command -v claude`. If it is not, print the commands to run manually and move to the next step.

> **Transport**: `-t` accepts `stdio`, `sse`, `http`. `url` is not a valid transport:
> a server declared with `"type": "url"` is silently discarded.

#### 6.1 — ClickUp (user scope, only with the task list configured)

ClickUp is only useful if the team tracks tasks in ClickUp. Look for `CLICKUP_SETUP_LIST_ID`
in this order: environment variable, the plugin's `userConfig`. **Do not read the project's
`.env`** — Step 3.2 denied it to you and to your shell commands, and one list ID is not
worth pulling a file of secrets into the context window. If neither source has it, treat it
as absent.

- **Set** → check with `claude mcp list` whether `clickup` is already configured. If it is not:
  ```bash
  claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
  ```
- **Empty or absent** → do **not** register the server. Report in the Step 9 summary:
  "ClickUp MCP not configured: set `CLICKUP_SETUP_LIST_ID` in `.env` (Step 7 left the key in
  `.env.example`), then run `claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`".

#### 6.2 — Library documentation: the `ctx7` CLI, not MCP

Do **not** register Context7 as an MCP server. `AGENTS.md` declares the `ctx7` CLI as the
preferred source — faster and with no tool-call budget — so the server would
duplicate the same capability while paying for its tool definitions in every session.

Check with `command -v ctx7`:
- **present** → nothing to do
- **absent** → nothing to install: `AGENTS.md` instructs to invoke it via `npx ctx7@latest <command>`

Only if neither the CLI nor `npx` is reachable (an environment without npm network access), report the
manual fallback in the Step 9 summary:
```bash
claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest
```

#### 6.3 — Figma (project scope, only if frontend or mobile is detected)

Only if Step 2 detected frontend or mobile, or if the stack chosen in Step 2b is
web-frontend / mobile / fullstack. On a pure backend Figma is **not** registered.

Ask the developer: "Do you want to configure the Figma MCP? Authentication happens via OAuth in the browser."
If they say yes:
```bash
claude mcp add figma -t http -s project https://mcp.figma.com/mcp
```
On first use, Figma will ask for authorization via the browser (like ClickUp).

---

### Step 7 — Declare the environment variables in .env.example

**You never read or write `.env`.** Step 3.2 denied it at two levels — the file tools
refuse it and the sandbox refuses it to your shell commands — so the real file stays the
developer's. Work on `.env.example`, which is tracked, carries no values, and is
explicitly excluded from those deny rules.

1. If `.env.example` exists and already contains `CLICKUP_SETUP_LIST_ID` → do nothing
2. If `.env.example` exists but does **not** contain `CLICKUP_SETUP_LIST_ID` → append:
   ```

   # ClickUp — task list ID (added by setup)
   CLICKUP_SETUP_LIST_ID=
   ```
3. If `.env.example` does not exist → create it with:
   ```
   # ClickUp — task list ID
   CLICKUP_SETUP_LIST_ID=
   ```

In every case, close with one line for the Step 9 summary telling the developer to copy
the key into their own `.env`:
`CLICKUP_SETUP_LIST_ID declared in .env.example — copy it into .env and fill it in (setup cannot write .env)`

---

### Step 7b — Branch protection on the reference branch

"One review required" and "no direct push to the reference branch" used to be two
bullets in a governance document nobody could enforce. They are settings on the
host, so this step sets them there and they stop being prose.

**Skip this step** when `{VCS}` is `none` or `other`.

#### 7b.1 — Resolve the reference branch

Never assume `main`. The plugin already knows how to work this out:

```bash
BASE=$(${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh --json | jq -r .BASE_BRANCH)
REMOTE=$(git remote | head -1)
BASE_BRANCH=${BASE#"$REMOTE/"}   # BASE_BRANCH comes back remote-qualified (origin/next);
                                 # the host APIs want the bare name
```

It resolves the branch from the repository itself — the upstream, the remote's
default, then `main`/`master`/`develop`/`next` — and picks the one HEAD actually
forked from. On a project whose work targets `next`, protecting `main` would
protect the wrong ref.

#### 7b.2 — Show the developer what will change, then ask

This writes to the remote, and on most hosts it needs admin rights on the
repository. State the branch and the two settings, and ask for a yes before
running anything:

> "Protect `$BASE_BRANCH` on <GitHub|GitLab>? It would require 1 approving review
> on every pull request, block direct pushes, and refuse a merge while CI is red.
> You need admin rights on the repo. (yes / skip)"

If they skip, note it in the Step 9 summary and move on — the rest of the setup
does not depend on it.

#### 7b.3 — Apply it

**GitHub** — first find out which checks this repository actually runs. Their
names differ per project, and a name that was guessed makes every PR
permanently unmergeable:

```bash
CHECKS=$(gh api "repos/{owner}/{repo}/commits/$BASE_BRANCH/check-runs" \
  --jq '[.check_runs[].name] | unique' 2>/dev/null || echo '[]')
```

If the array is non-empty, show the developer the names and ask which ones gate a
merge (default: all of them). Then apply the protection with those checks
required:

```bash
gh api -X PUT "repos/{owner}/{repo}/branches/$BASE_BRANCH/protection" --input - <<JSON
{
  "required_pull_request_reviews": { "required_approving_review_count": 1 },
  "required_status_checks": { "strict": true, "contexts": $CHECKS },
  "enforce_admins": false,
  "restrictions": null
}
JSON
```

If the array is empty — no workflow has ever run on that branch — send
`"required_status_checks": null` instead and tell the developer to re-run this
step once CI has completed once. Do **not** invent context names.

**GitLab** — protected branches are their own endpoint, and approvals are a
separate setting:

```bash
glab api -X POST "projects/:id/protected_branches" \
  -f "name=$BASE_BRANCH" -f "push_access_level=0" -f "merge_access_level=30"
glab api -X POST "projects/:id/approval_rules" \
  -f "name=Default" -f "approvals_required=1"
```

`push_access_level=0` is "no one", `merge_access_level=30` is "developers and
above" — direct pushes are blocked, merge requests still work.

GitLab's equivalent of "cannot merge with a red pipeline" is a project setting,
not part of the protected-branch payload:

```bash
glab api -X PUT "projects/:id" \
  -f "only_allow_merge_if_pipeline_succeeds=true" \
  -f "only_allow_merge_if_all_discussions_are_resolved=true"
```

#### 7b.4 — When it fails

A 403 means no admin rights, a 404 on GitLab means the plan does not include
approval rules. Neither is a setup failure: report exactly what came back, say
which setting is still missing, and continue. Do not retry with different
parameters, and do not fall back to protecting a different branch.

---

### Step 8 — Greenfield setup (GREENFIELD mode only)

This step runs **only** for greenfield projects. For EXISTING and UPDATE, skip to Step 9.

#### 8.1 — Prerequisites

Verify that these are installed: `node` (**v24+**), `npm`, `git`. If any is missing, tell the developer
and stop.

Node 24 is the real minimum, not a preference: `semantic-release@25` requires
`^22.14.0 || >=24.10.0`, `lint-staged@17` requires `>=22.22.1`, `eslint@9` requires
`^20.19.0 || ^22.13.0 || >=24`. Node 20 has been EOL since 2026-04-30.

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
npm install --save-dev husky lint-staged @commitlint/cli @commitlint/config-conventional \
  prettier 'eslint@^9.39.0' '@eslint/js@^9.39.0' typescript-eslint globals typescript
```

**Do not install `eslint` without a pin**: `latest` is 10.x, and the frontend profiles'
plugins (`eslint-plugin-react`, `eslint-plugin-jsx-a11y`, `eslint-plugin-import`)
declare `eslint: ^9` as their peer ceiling — on 10 the install fails with `ERESOLVE`.

`typescript-eslint` (the single package) replaces the
`@typescript-eslint/eslint-plugin` + `@typescript-eslint/parser` pair: it is the form
flat config expects.

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

#### 8.4 — Quality configuration

Copy the files from the boilerplate distributed with the skill
(`${CLAUDE_SKILL_DIR}/templates/boilerplate/`) — do not rewrite them by hand: copying
is the only form that stays aligned with the template.

| Source in the boilerplate | Destination in the project | Condition |
|---|---|---|
| `.commitlintrc.json` | `.commitlintrc.json` | always |
| `.lintstagedrc.json` | `.lintstagedrc.json` | always (the Step 8.3 husky hooks call `npx lint-staged`) |
| `eslint.config.base.mjs` | `eslint.config.base.mjs` | always |
| `.prettierrc.json` | `.prettierrc.json` | stacks **without** Tailwind |
| `.prettierrc.tailwind.json` | `.prettierrc.json` | stacks **with** Tailwind (web-frontend, mobile RN) |
| `.releaserc.github.json` | `.releaserc.json` | `vcs = github` |
| `.releaserc.gitlab.json` | `.releaserc.json` | `vcs = gitlab` |

On `vcs = none` / `other`, **skip** `.releaserc.json`: there is no provider to
publish releases to. The two `.releaserc.*` files differ only in the last
plugin (`@semantic-release/github` vs `@semantic-release/gitlab`).

`.prettierrc.tailwind.json` is identical to the base variant plus
`plugins: ["prettier-plugin-tailwindcss"]`. Copy it **only** if the profile
installs `prettier-plugin-tailwindcss`: without the plugin installed, Prettier
errors out on every run.

`eslint.config.base.mjs` is the shared base in **flat config**. The file
ESLint actually reads is `eslint.config.mjs`, which Step 8.5 creates from the profile
by importing the base. If the stack has no profile with an ESLint config, create an
`eslint.config.mjs` that just re-exports the base:

```javascript
// eslint.config.mjs
import base from './eslint.config.base.mjs';

export default base;
```

#### 8.4b — npm scripts

Without these scripts, `npm run lint`, the husky hooks and the boilerplate CI
fail with *Missing script*. Add them to `package.json`:

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
`flutter test` on Flutter) and `typecheck` to the stack: these are the three commands the
boilerplate CI runs as its quality gate.

#### 8.5 — Apply the stack profile

Read the profile file from `${CLAUDE_SKILL_DIR}/templates/profiles/` (already read in Step 3.1) and apply the configurations it contains:

If the mobile stack is **Flutter** (detected from `pubspec.yaml` or selected in GREENFIELD), follow the ad-hoc Flutter path:

1. **Flutter dependencies**: update `pubspec.yaml` with the profile's packages (`freezed_annotation`, `json_annotation`, `riverpod`/`flutter_bloc`, `dio`, etc.)
2. **Flutter dev dependencies**: include `build_runner`, `freezed`, `json_serializable`, `flutter_lints`, `riverpod_generator` (if using Riverpod codegen)
3. **Flutter linting**: create/update `analysis_options.yaml` including `package:flutter_lints/flutter.yaml`
4. **Code generation**: run `dart run build_runner build --delete-conflicting-outputs`
5. **Quality gate**: run `dart format .`, `dart analyze`, `flutter test`

If the mobile stack is **React Native (Expo)**, follow the Node path:

1. **Dependencies**: extract the JSON dependency block from the profile and install them with `npm install`
2. **ESLint**: if the profile contains an ESLint configuration, create `eslint.config.mjs` with that
   content (flat config — it imports `./eslint.config.base.mjs`, copied in Step 8.4)
3. **TypeScript**: if the profile contains a TypeScript configuration, create `tsconfig.json`
4. **Jest**: if the profile contains a Jest configuration, create `jest.config.mjs` — **not** `.ts`:
   Jest does not parse a TypeScript config without `ts-node` installed

For the **fullstack** stack (multi-project):
- Create the `apps/web/` and `apps/api/` structure
- Apply the web-frontend profile in `apps/web/`
- Apply the backend-node profile in `apps/api/`
- Generate `AGENTS.md`, `CLAUDE.md` and `REGISTRY.md` for each sub-project (as described in Steps 5B and 5b)
- At the root use the workspace template (as described in Step 5B)

#### 8.6 — CI/CD workflow

Pick the CI template based on the `{VCS}` detected in Step 2c.

- `vcs = github` → copy **both** workflows from
  `${CLAUDE_SKILL_DIR}/templates/boilerplate/.github/workflows/` into `.github/workflows/`
  (create the directory if missing): `ci.yml` (quality gate on every PR) and `release.yml`
  (quality gate + semantic-release on the default branch). The release requires the
  `GITHUB_TOKEN` secret, provided by default by GitHub Actions.
- `vcs = gitlab` → copy `${CLAUDE_SKILL_DIR}/templates/boilerplate/.gitlab-ci.yml` to
  `.gitlab-ci.yml` in the project root. It contains the `test` stage (which runs on MR
  pipelines and on the default branch) and the `release` stage. It requires a CI/CD variable
  `GITLAB_TOKEN` with scope `api` + `write_repository` (Settings → CI/CD → Variables).
- `vcs = none` / `other` → **skip this step**. Tell the developer they can manually add a CI workflow for whichever provider they prefer.

Both templates run on **Node 24** and execute the same steps: `npm ci`,
`npm run lint`, `npm run typecheck`, `npm run test:cov` and — only on the default branch and
only if the quality gate is green — `npx semantic-release`. Commits with `[skip ci]`
are bypassed.

The quality gate depends on the npm scripts from Step 8.4b: if they are missing, CI
fails with *Missing script*.

#### 8.7 — .gitignore

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

### Step 9 — Summary

Show the developer a summary in this format:

**For EXISTING:**
```
Setup complete!

Installed files:
  - CLAUDE.md             — entry point for Claude Code (imports AGENTS.md)
  - AGENTS.md             — instructions for AI agents (cross-tool standard)
  - .claude/rules/        — path-scoped governance rules (dev-setup-*.md)
  - REGISTRY.md           — feature and service registry
  - .claude/settings.json — project permissions + Bash sandbox

Available skills (provided by the plugin):
  - /dev-setup:sdd         — interactive SDD (spec → approval → development, with checkpoints)
  - /dev-setup:auto-sdd    — autonomous end-to-end SDD (up to the PR, no human input)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — code review against the project rules

Detected stack:
  - Languages:      <languages>
  - Test runner:    <test_command>
  - Linter:         <lint_command>
  - Validation:     <validation_tool>
  - Infrastructure: <yes|no> (if yes: dev-setup-terraform.md generated, terraform profile applied)
  - VCS:            <github|gitlab|none|other> → vcs-ops reference: <github|gitlab|none>

NOT modified (existing tooling respected):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Next steps:
  1. Copy CLICKUP_SETUP_LIST_ID from .env.example into .env and fill it in
     (setup cannot write .env: the sandbox denies it)
  2. Check MCP: claude mcp list
  3. Use /dev-setup:sdd (interactive) or /dev-setup:auto-sdd (autonomous) to start a ClickUp task
```

**For GREENFIELD:**
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

Available skills (provided by the plugin):
  - /dev-setup:sdd         — interactive SDD (spec → approval → development, with checkpoints)
  - /dev-setup:auto-sdd    — autonomous end-to-end SDD (up to the PR, no human input)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — code review against the project rules

Detected VCS: <github|gitlab|none|other> → vcs-ops reference: <github|gitlab|none>
Infrastructure: <yes|no>

Next steps:
  1. Copy .env.example to .env and fill in the variables
  2. Check MCP: claude mcp list
  3. Use /dev-setup:sdd (interactive) or /dev-setup:auto-sdd (autonomous) to get started!
```

**Terraform GREENFIELD note**: if the chosen stack is **Infrastructure / Terraform**, Step 8 does not generate Terraform boilerplate (no auto-emitted Terraform `.gitignore`, no auto-emitted CI workflow, no `versions.tf` scaffold). The developer must manually create `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf` (or `versions.tf`) and the `backend "s3"` block following the recipes in `profiles/terraform.md`. Add to the GREENFIELD summary:
```
  [Terraform GREENFIELD] The plugin did NOT generate Terraform boilerplate.
                         See profiles/terraform.md for the recommended structure and the CI recipes.
```

**For MULTI-PROJECT (EXISTING):**
```
Setup complete! (Multi-project detected: <tool>)

Files at the root:
  - CLAUDE.md             — entry point for Claude Code
  - AGENTS.md             — general rules + workspace map
  - .claude/rules/        — path-scoped governance rules (dev-setup-*.md)
  - .claude/settings.json — project permissions + Bash sandbox

Configured sub-projects:
  <sub-project-path>/:
    - AGENTS.md           — stack: <stack>
    - CLAUDE.md           — local entry point
    - REGISTRY.md         — feature registry

Available skills (provided by the plugin):
  - /dev-setup:sdd         — interactive SDD (spec → approval → development, with checkpoints)
  - /dev-setup:auto-sdd    — autonomous end-to-end SDD (up to the PR, no human input)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — code review against the project rules

Detected VCS: <github|gitlab|none|other> → vcs-ops reference: <github|gitlab|none>
Infrastructure: <yes|no> (if yes: dev-setup-terraform.md is generated at the root and matches every *.tf in the workspace)

NOT modified (existing tooling respected):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Next steps:
  1. Copy CLICKUP_SETUP_LIST_ID from .env.example into .env and fill it in
     (setup cannot write .env: the sandbox denies it)
  2. Check MCP: claude mcp list
  3. Use /dev-setup:sdd (interactive) or /dev-setup:auto-sdd (autonomous) to start a ClickUp task
```

---

## Important notes

- **Verbatim**: settings.json and REGISTRY.md must be written exactly as read from the plugin. Do not generate the content of these files — read it and copy it. Steps 3.3, 3.4 and 3.5 then narrow settings.json with `jq`; that is the only editing it gets.
- **Secrets**: `.env` and its per-environment variants are denied to the file tools and to sandboxed shell commands, and the usual token variables are unset inside the sandbox. Nothing in this procedure needs them. If a step ever appears to require reading `.env`, that step is wrong — report it instead of working around the deny.
- **Conflict detection**: always ask before overwriting existing files.
- **Existing tooling**: in EXISTING mode, do not install or modify: git hooks, linter, formatter, CI/CD, .gitignore, dependencies. Graft only the AI workflow.
- **Skills and agents**: do NOT install skills and agents into the project. They are provided by the plugin and available automatically as /dev-setup:<skill-name>.
- **gh CLI**: needed only for MCP configuration (Step 6) and for greenfield operations. If it is missing, setup can still complete — print the MCP commands to run manually.
- **VCS (GitHub vs GitLab)**: Step 2c detects the provider from the `origin` remote, but nothing is installed per provider — the single `vcs-ops` skill holds the shared conventions and loads `reference/github.md` or `reference/gitlab.md` after reading the remote itself. The workflow skills (`sdd`, `auto-sdd`) just invoke `vcs-ops`.
