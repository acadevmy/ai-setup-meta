# EXISTING mode — detect what the project already is

Step 2 of the procedure and the summary that closes it, for a project that
already has code. UPDATE mode reads this same file: it re-runs the detection
before re-installing. A GREENFIELD run never reads it — there is nothing to
detect yet.

Installing the resources (Steps 2c and 3) happens in every mode and lives in
`install.md`.

## Index

- [Step 2 — Stack detection](#step-2--stack-detection)
- [What the script does not decide](#what-the-script-does-not-decide)
- [Check current AI-tooling conventions](#check-current-ai-tooling-conventions-for-every-detected-framework)
- [Multi-project](#multi-project)
- [Step 9 — Summary for EXISTING](#step-9--summary-for-existing)

---

## Step 2 — Stack detection

The detection is a script, not prose to re-interpret on every run:

```bash
mkdir -p .claude
${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh --json > .claude/.stack.json
```

It returns `LANG`, `FRAMEWORKS`, `PKG_MANAGER`, `VCS`, `MONOREPO`,
`HAS_FRONTEND`, `HAS_MOBILE`, `HAS_INFRA`, `SERVICES_GLOB`, `TEST_CMD`,
`LINT_CMD`, `TYPECHECK_CMD` and `HOOK_MANAGER`. A missing value is the empty
string, never a message, so test for emptiness. `--dir <path>` inspects a
sub-directory, which is what the multi-project section below uses.

Keep the file: Step 4 renders the rules from it, and 4.3 deletes it. It is a
scratch file — do not commit it, do not add it to `.gitignore`.

### What the script does not decide

Four things stay here, because they need judgement or the network:

**Validation library.** Read it off the dependencies: `zod` → Zod, `joi` → Joi,
`yup` → Yup, `class-validator` → class-validator, `pydantic` → Pydantic. A
`pubspec.yaml` means freezed + json_serializable (immutable models and
schema-driven serialization, no Zod). Nothing matching → `not detected`.

**Framework version.** For the framework named in `FRAMEWORKS`, read the version
from `dependencies.<pkg>` or `devDependencies.<pkg>` and parse major.minor
(`"next": "^16.0.7"` → `16.0`; `"next": "~17.2.0"` → `17.2`). Save as
`{FRAMEWORK_FRONTEND}` and `{FRAMEWORK_FRONTEND_VERSION}` — Step 5 needs both.

**Current AI-tooling conventions.** See the section below.

**Sub-project enumeration and command wrapping.** See "Multi-project" below.

### Check current AI-tooling conventions (for every detected framework)

The state of the art for `AGENTS.md` conventions (and equivalents) moves fast —
the profiles in `templates/profiles/<framework>.md` reflect the state at plugin
release, but new frameworks and recent versions introduce patterns the plugin
does not know about yet. For every detected framework (frontend, backend,
infrastructure) query the current documentation.

**Lookup strategy** (in order; the first source that produces a result wins):

1. **`ctx7` CLI** on PATH, or via `npx ctx7@latest` if not installed:
   - `ctx7 library <framework>` to resolve the ID (e.g. `/vercel/next.js`)
   - `ctx7 docs <id> "AGENTS.md convention bundled docs agent rules"` for the query
2. **Context7 MCP**, only if the project registered it (it is not in the default
   configuration, see `mcp-env.md`): `mcp__context7__resolve-library-id` +
   `mcp__context7__query-docs` with the same query
3. **WebSearch** if neither is available: query
   `"AGENTS.md convention <framework> <major>.<minor>"` (e.g.
   `"AGENTS.md convention next.js 16.2"`), preferring the framework's official domain
4. **Skip** if no source is reachable (offline environment) — proceed with the
   hard-coded profiles alone and report the skip in the summary

**What to look for**, for each framework:

- Is there an `AGENTS.md` convention officially supported by the framework (e.g.
  the `BEGIN:nextjs-agent-rules` block in Next.js)?
- Which markers / sections does the framework manage automatically (e.g. through
  a `<framework> upgrade` command)?
- Path of the bundled docs (if applicable, e.g. `node_modules/<framework>/dist/docs/`)
- Codemods or related tooling for existing projects (e.g. `npx @next/codemod@latest agents-md`)
- Minimum framework version that supports the convention

**Source precedence**: the hard-coded profile is the primary source for
frameworks documented at plugin release (deterministic, predictable); the
runtime check is an additional source for frameworks not yet documented in the
plugin, or for newer versions that introduced new conventions.

Save what you find as `{FRAMEWORK_AGENTS_CONVENTION}` (marker name, block
content, source, doc link) — `agents-generation.md` applies it as a
framework-specific block injection, using the same strategy documented there for
Next.js.

**Output to the developer**: one line in the summary per checked framework:

```
- <framework> <version>: convention <name> found via <source> → <action applied>
- <framework> <version>: no documented AI-tooling convention → no action
- <framework> <version>: check skipped (offline) → hard-coded profile only
```

### Multi-project

`MONOREPO` is non-empty when the project is a workspace (`nx`, `turborepo`,
`pnpm-workspace`, `lerna`, `npm-workspaces`, or `structural` when two or more
top-level directories carry a project marker file). The script names the tool;
enumerating the members is this step's job.

**Sub-project enumeration** (in priority order; the first source that produces
results is the one to use):

1. `pnpm-workspace.yaml` → read `packages:` (a list of globs)
2. Root `package.json` → read the `workspaces` field (an array of globs)
3. `lerna.json` → read `packages` (a list of globs)
4. `nx.json` → read `projects` ONLY if the field exists (legacy, Nx ≤ 17). From
   Nx 18+ the field is gone: projects are inferred from `package.json` /
   `project.json` under the workspace paths. In that case use one of the
   previous sources.
5. `turbo.json` → projects are inferred from the pnpm/yarn/npm workspaces;
   Turborepo keeps no list of its own.

Expand the globs into actual directories containing a `package.json`. Optional
cross-check: if the Nx CLI is available in `node_modules/.bin` or on PATH, run
`pnpm nx show projects` (or `npx nx show projects`) and compare the inferred
list against the CLI output.

For each sub-project, run the detection inside it —
`detect-stack.sh --json --dir <path>` — and read its `package.json` for `name`
(the identifier used both in the display path and in command wrapping) and
`scripts` (the available commands).

A sub-project's commands have to be runnable from the workspace root, not only
from its own folder. `agents-generation.md` holds the wrapping form per monorepo
tool — it is where those commands get written into the templates.

### Show the detection summary, then confirm

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

For multi-project (commands already wrapped so they run from the workspace root):

```
Detected stack:
  Multi-project:  yes (Nx + pnpm workspace)
  Sub-projects:
    applications/web/   — node, frontend: yes, test: pnpm --filter web test, lint: pnpm --filter web lint
    applications/api/   — node, frontend: no, test: pnpm --filter api test, lint: pnpm --filter api lint
    iac/                — terraform, infrastructure: yes, test: terraform validate, lint: terraform fmt -check -recursive

Do you confirm these sub-projects? (yes/no)
```

Ask for that confirmation before proceeding: everything downstream is generated
per sub-project.

---

## Step 9 — Summary for EXISTING

```
Setup complete!

Installed files:
  - CLAUDE.md             — entry point for Claude Code (imports AGENTS.md)
  - AGENTS.md             — instructions for AI agents (cross-tool standard)
  - .claude/rules/        — path-scoped governance rules (dev-setup-*.md)
  - REGISTRY.md           — feature and service registry
  - .claude/settings.json — project permissions + Bash sandbox

Available commands (provided by the plugin):
  - /dev-setup:sdd         — interactive SDD (spec → approval → development, with checkpoints)
  - /dev-setup:auto-sdd    — autonomous SDD in a workflow (spec challenged, worktree, PR behind a confirmation)
  - /dev-setup:review      — code review against the project rules

Detected stack:
  - Languages:      <LANG>
  - Test runner:    <TEST_CMD>
  - Linter:         <LINT_CMD>
  - Validation:     <validation library>
  - Infrastructure: <yes|no> (if yes: dev-setup-terraform.md generated, terraform profile applied)
  - VCS:            <github|gitlab|none|other>

NOT modified (existing tooling respected):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Next steps:
  1. Copy CLICKUP_SETUP_LIST_ID from .env.example into .env and fill it in
     (setup cannot write .env: the sandbox denies it)
  2. Check MCP: claude mcp list
  3. Use /dev-setup:sdd (interactive) or /dev-setup:auto-sdd (autonomous) to start a ClickUp task
```

Add the one-line reports collected along the way (3.3, 3.4, 3.5, 3.6, the
framework convention checks, and the ones `rules-generation.md` and
`mcp-env.md` ask for), plus whatever the step-7b branch protection reported.

**In UPDATE mode**, say what happened to `.claude/settings.json` — one of:

```
  - settings.json migrated: sandbox on, <n> deny rules and the ask checkpoints added,
    <retired> dropped from the allowlist; your own entries kept
  - settings.json already current — nothing to migrate
  - settings.json migration DECLINED: the project runs WITHOUT the Bash sandbox.
    .env is not denied to shell commands, gh/glab writes are not behind a confirmation,
    and force push is not blocked. Re-run setup to apply it.
```

The third line is not decoration. `dev-setup-core.md` tells every session that
the sandbox denies reading `.env`; if the developer declined, the summary is the
only place that says otherwise.

### Multi-project variant

Same shape, with the root files listed once and the per-sub-project files
underneath:

```
Setup complete! (Multi-project detected: <MONOREPO>)

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
```

Infrastructure, when detected, notes that `dev-setup-terraform.md` lives at the
root and matches every `*.tf` in the workspace.
