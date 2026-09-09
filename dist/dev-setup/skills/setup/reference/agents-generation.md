# Steps 5 and 5b — Generate AGENTS.md and CLAUDE.md

`AGENTS.md` is the cross-tool instruction file; `CLAUDE.md` is the one-line entry
point Claude Code reads. Both are generated from the templates bundled with the
skill, never written from scratch.

## Index

- [5A — Single project](#5a--single-project)
- [Project Identity (interactive)](#project-identity-interactive)
- [Infrastructure (auto-detect + TODO)](#infrastructure-auto-detect--todo)
- [GREENFIELD placeholder values](#greenfield-placeholder-values)
- [Framework-specific block — Next.js](#framework-specific-block--nextjs)
- [5B — Multi-project](#5b--multi-project)
- [Command wrapping](#command-wrapping)
- [Step 5b — Generate CLAUDE.md](#step-5b--generate-claudemd)

---

## 5A — Single project

Read `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md` and substitute the
placeholders. The template is the same for every mode: only the source of the
values changes.

**Placeholder values for EXISTING mode:**

- `{{STACK_DESCRIPTION}}` → a compact description of the detected stack. Format:
  `Detected stack: languages[, test: test_command][, linter: lint_command][, validation: tool]`
  - example: `Detected stack: **node**, test: npm test, linter: npm run lint, validation: Zod`
  - if test/linter/validation are `not detected`, omit them from the string
  - add the note: `> This stack was detected automatically. If it is wrong, update this section manually.`
- `{{TEST_COMMAND}}` → `TEST_CMD` from the detection (e.g. `npm test`, `pytest`,
  `not detected`)
- `{{LINT_COMMAND}}` → `LINT_CMD` (e.g. `npm run lint`, `ruff check .`,
  `not detected`)
- `{{TYPECHECK_COMMAND}}` → `TYPECHECK_CMD`
- `{{QUALITY_COVERAGE_TARGET}}` → the coverage threshold. Default: `80%` with the
  comment `(industry baseline; adjust if your team has set a different bar)`. If
  `package.json` or the test runner config exposes an explicit threshold, use
  that one.
- `{{VCS_OPS_NOTE}}` → one informational line about the provider detected at
  Step 2c:
  - `github` → `> GitHub operations (branch, PR, commit) are performed with the \`gh\` CLI.`
  - `gitlab` → `` > GitLab operations (branch, MR, commit) are performed with the `glab` CLI. MR descriptions follow `.gitlab/merge_request_templates/Default.md` when present. ``
  - `none` / `other` → `` > Git operations via the `git` CLI. No remote provider configured. ``

**For UPDATE mode**: regenerate as for EXISTING or GREENFIELD, depending on the
project's state.

**Conflict detection**: if `AGENTS.md` already exists, ask before overwriting.

Write the result to `AGENTS.md` in the project root.

## Project Identity (interactive)

EXISTING and GREENFIELD alike. Ask ONE batched question with three sub-fields
and collect the answers. Leave `TODO — <hint>` for empty fields — do not invent
values.

> "To fill in the `Project Identity` section of AGENTS.md I need three short
> pieces of information (press Enter to skip a field and I will leave it as a
> TODO):
> - **Name**: the project's short name (e.g. 'Acme Web App')
> - **Purpose**: one sentence on what the project does
> - **Primary users**: who uses it (e.g. 'consumer travelers', 'internal ops')"

- `{{PROJECT_NAME}}` → the answer, or `TODO — short app name`
- `{{PROJECT_PURPOSE}}` → the answer, or `TODO — one-sentence purpose`
- `{{PROJECT_PRIMARY_USERS}}` → the answer, or `TODO — who uses this app`

## Infrastructure (auto-detect + TODO)

Attempt detection in this order; anything undetectable becomes `TODO — <hint>`:

- `{{INFRA_VCS_CI}}` → combine:
  - VCS: parse the remote URL from `.git/config` (`gitlab.com` → `GitLab`,
    `github.com` → `GitHub`, `bitbucket.org` → `Bitbucket`, `dev.azure.com` →
    `Azure DevOps`)
  - CI: `.gitlab-ci.yml` → `GitLab CI`; `.github/workflows/` →
    `GitHub Actions`; `.circleci/config.yml` → `CircleCI`;
    `bitbucket-pipelines.yml` → `Bitbucket Pipelines`; `azure-pipelines.yml` →
    `Azure Pipelines`; `Jenkinsfile` → `Jenkins`
  - result: `<VCS> + <CI>` (e.g. `GitLab + GitLab CI`). If the VCS is detected
    but the CI is not, write `<VCS>, CI: TODO — which CI provider`.
- `{{INFRA_SECRETS}}` → `dotenv-vault.json` or `.env.vault` → `dotenv-vault`;
  `*.tfstate` with a `vault` backend → `HashiCorp Vault`;
  `aws-secretsmanager` or `aws ssm` references in IaC/CI →
  `AWS Secrets Manager` / `AWS Parameter Store`. Otherwise
  `TODO — secrets manager (e.g. dotenv-vault, AWS SSM, Vault)`.
- `{{INFRA_HOSTING}}` → a light heuristic from the CI: provider names in deploy
  steps (`vercel`, `netlify`, `aws-eks`, `kubectl`, `gcloud run`,
  `firebase deploy`). Otherwise `TODO — hosting/deploy target`.
- `{{INFRA_OBSERVABILITY}}` → `datadog.yaml` / a `dd-trace` dependency →
  `Datadog`; `sentry.client.config.*` or `@sentry/*` in package.json →
  `Sentry`; `newrelic.{yml,json}` → `New Relic`. Otherwise
  `TODO — observability tool`.

## GREENFIELD placeholder values

From the stack chosen at Step 2b:

| Stack | `{{STACK_DESCRIPTION}}` | `{{TEST_COMMAND}}` | `{{LINT_COMMAND}}` |
|---|---|---|---|
| Web Frontend | `**Web Frontend**: Next.js 16+ / Angular 22+ / React 19+, ShadCN/UI, Tailwind CSS 4, Zod 4, Jest + Testing Library` | `npm test` | `npm run lint` |
| Backend Node | `**Backend Node**: Node.js 24+, NestJS 11+, Zod 4 via nestjs-zod, Jest + Supertest, Prisma` | `npm test` | `npm run lint` |
| Mobile (Flutter) | `**Mobile**: Flutter 3.47+ (BLoC/Riverpod)` | `flutter test` | `dart analyze` |
| Mobile (React Native) | `**Mobile**: React Native with Expo (Zustand/Jotai)` | `npm test` | `npm run lint` |
| Infrastructure (Terraform) | `**Infrastructure**: Terraform — follow the repo's pinned version, remote state with locking + encryption at rest, HashiCorp style guide` | `terraform validate` | `terraform fmt -check -recursive` |

## Framework-specific block — Next.js

If `{FRAMEWORK_FRONTEND}` == `nextjs`, prepend the canonical Next.js block to
the generated `AGENTS.md`, **before** all the template-derived content:

```md
<!-- BEGIN:nextjs-agent-rules -->

# Next.js: ALWAYS read docs before coding

Before any Next.js work, find and read the relevant doc in `node_modules/next/dist/docs/`. Your training data is outdated — the docs are the source of truth.

<!-- END:nextjs-agent-rules -->

```

The `BEGIN:nextjs-agent-rules` / `END:nextjs-agent-rules` markers delimit a
section managed by `next upgrade` (Next.js 16.2+): everything between the
markers is rewritten on upgrades, everything outside is preserved. Keeping the
plugin's content below the `END` marker guarantees `next upgrade` will not
overwrite it. For full details see `profiles/nextjs.md`.

Based on `{FRAMEWORK_FRONTEND_VERSION}` (major.minor, e.g. `16.0`, `17.2`):

- `>= 16.2` → the docs are bundled in `node_modules/next/dist/docs/`. Add to the
  summary: "run `npx next upgrade@canary` periodically to keep the AGENTS.md
  block current."
- `< 16.2` → the docs are **not** bundled. Add to the summary: "run
  `npx @next/codemod@latest agents-md` to generate the docs in `.next-docs/` and
  update the path in the block."

**Brownfield**: if `AGENTS.md` already exists and contains a
`BEGIN:nextjs-agent-rules` … `END:nextjs-agent-rules` block, do **not**
regenerate the inner content. Preserve the block verbatim and append the plugin
template below the `END` marker. The inner block is Next.js territory —
rewriting it would conflict with the next `next upgrade`.

**Conventions discovered at runtime**: if the Step 2 check populated
`{FRAMEWORK_AGENTS_CONVENTION}` for a framework other than Next.js (or for a
Next.js version newer than what is documented here), apply the same injection
strategy: delimited markers at the top of the file, the plugin's template
content below the closing marker. Precedence: hard-coded profile → runtime
convention → no injection. If the two conflict, the profile wins and the runtime
convention is reported as "not applied, hard-coded source takes precedence" in
the summary.

## 5B — Multi-project

Generate **two levels** of AGENTS.md: one at the root and one per **application**
sub-project. Libraries do not get per-project setup files — their usage is cited
in the REGISTRY of the application that consumes them.

**Sub-project classification (application vs library)**, in priority order:

1. path matches `applications/*`, `apps/*`, `services/*` → **application**
2. path matches `libraries/*`, `libs/*`, `packages/*` → **library**
3. `package.json` has `"private": false` AND `"main"`/`"exports"` → **library**
   (publishable shape)
4. `package.json` has `scripts.dev` or `scripts.start` → **application**
   (runnable shape)
5. otherwise → ask the developer (default: **application**)

Save the classification for each sub-project as `{SUBPROJECT_TYPE}`.

**Root AGENTS.md** — use
`${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md`:

- `{{WORKSPACE_STRUCTURE}}` → a table with ALL confirmed sub-projects (apps +
  libs), with a `Type` column and a differentiated `Instructions` column:

  ```
  | Project | Type | Path | Stack | Instructions |
  |---|---|---|---|---|
  | web   | application | apps/web/ | Next.js 16+, React 19+ | [apps/web/AGENTS.md](apps/web/AGENTS.md) |
  | api   | application | apps/api/ | Node.js 24+, NestJS 11+ | [apps/api/AGENTS.md](apps/api/AGENTS.md) |
  | shared | library    | libs/shared/ | TypeScript, Zod | (no per-library file — see consuming app REGISTRY) |
  ```

- below the table, add this note:

  > Libraries do not get per-project setup files. When a library exposes an
  > interesting pattern, ADR, or breaking change, add a `### library/<name>`
  > entry to the **consuming application's `REGISTRY.md`** under "Services and
  > utilities" — that's where library usage is documented.

- `{{PROJECT_NAME}}`, `{{PROJECT_PURPOSE}}`, `{{PROJECT_PRIMARY_USERS}}`,
  `{{INFRA_VCS_CI}}`, `{{INFRA_SECRETS}}`, `{{INFRA_HOSTING}}`,
  `{{INFRA_OBSERVABILITY}}`, `{{QUALITY_COVERAGE_TARGET}}`,
  `{{TEST_COMMAND}}`, `{{LINT_COMMAND}}`, `{{TYPECHECK_COMMAND}}` → same
  instructions as 5A. For workspace commands, prefer the build tool's
  multi-project form: Nx → `nx run-many -t <target>`; plain pnpm workspace →
  `pnpm -r <script>`; turbo → `turbo run <task>`. If more than one is present,
  use the one exposed as a root script in `package.json`.

Write the result to `AGENTS.md` in the root.

**Per-sub-project AGENTS.md** — use
`${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`, **only** for
sub-projects with `{SUBPROJECT_TYPE} == 'application'`:

- `{{PROJECT_NAME}}` → a descriptive name (e.g. "Web Frontend", "Backend API")
- `{{STACK_DESCRIPTION}}` → the sub-project's detected stack (same criteria as 5A)
- `{{TEST_COMMAND}}` / `{{LINT_COMMAND}}` → the sub-project's commands, in the
  wrapped form below
- `{{ROOT_AGENTS_REL_PATH}}` → the relative path to the root (e.g. `../../AGENTS.md`)

**Command wrapping.** A command written into a sub-project's file still has to
run from the workspace root, so use the form the detected monorepo tool expects:

- **Nx** → `nx run <name>:<target>` (preferred when the target is defined in
  `nx.json` `targetDefaults` or in `package.json` `nx.targets`); fallback
  `pnpm --filter <name> <script>` (or the package manager equivalent)
- **pnpm workspace** (without Nx) → `pnpm --filter <name> <script>`
- **Yarn workspace** → `yarn workspace <name> <script>`
- **npm workspace** → `npm run <script> --workspace=<name>`
- **Lerna** → `lerna run <script> --scope=<name>`
- non-Node sub-projects (e.g. Terraform under `iac/`) → the raw command, run
  from the sub-project directory; no wrapping.

Write the result to `<sub-project-path>/AGENTS.md`. Sub-projects classified as
`library` do **not** get AGENTS.md / CLAUDE.md / REGISTRY.md.

**Citing consumed libraries** (for every application): read its `package.json`
and identify the workspace dependencies pointing at the monorepo's libraries. A
dependency is workspace-resolved when the value is `workspace:*`,
`workspace:^`, `workspace:~` or `workspace:<version>`, or when the package name
matches exactly the `name` of a sub-project classified as `library`.

For each consumed library, add an entry to `<app>/REGISTRY.md` under "Services
and utilities":

```markdown
### library/<name>

- **Where**: `libraries/<name>/` (or the actual path) — workspace package
- **Used by**: this application (add the other apps that consume it, comma-separated)
- **Summary**: <one line; use the `description` from `<lib>/package.json` if present, or the first meaningful paragraph of the library README; if neither is usable, write "TBD — refine when first touched">
```

This way the agent working in the application immediately sees which libraries
it uses, where they live, and has a starting point for investigating them. When
the team adds patterns or ADRs that touch a library, they live in the consuming
app's REGISTRY and can reference `### library/<name>` as an anchor.

---

## Step 5b — Generate CLAUDE.md

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. To guarantee compatibility while
keeping `AGENTS.md` as the cross-tool standard, generate a `CLAUDE.md` that
references it:

```markdown
@AGENTS.md
```

The file must contain **only** that line. Do not add any other content: every
instruction stays in `AGENTS.md` as the single source of truth.

**Conflict detection**: if `CLAUDE.md` already exists, ask before overwriting.

**Multi-project**: generate a `CLAUDE.md` in every confirmed application
sub-project too, with the same content — it points at the sub-project's local
`AGENTS.md`.
