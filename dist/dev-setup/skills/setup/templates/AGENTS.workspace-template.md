# AGENTS.md — Workspace

> What this workspace holds, what it runs on, and which commands to use. The
> rules on the code itself live in `.claude/rules/` — the harness loads them on
> its own, and the ones scoped to a file type arrive when you open a matching
> file.

## Identity and purpose

You are a development assistant integrated into the team. This repository is a
**multi-project workspace**. You work **alongside** the developer, who always has
the final say.

## Project Identity

- **Name:** {{PROJECT_NAME}}
- **Purpose:** {{PROJECT_PURPOSE}}
- **Primary users:** {{PROJECT_PRIMARY_USERS}}

## Infrastructure

- **Source control / CI:** {{INFRA_VCS_CI}}
- **Secrets management:** {{INFRA_SECRETS}}
- **Hosting / deploy target:** {{INFRA_HOSTING}}
- **Observability:** {{INFRA_OBSERVABILITY}}

> A line reading `TODO — …` is an auto-detection miss: fill it in, or delete the
> line if the dimension does not apply here.

## Workspace structure

{{WORKSPACE_STRUCTURE}}

> Libraries do not get per-project setup files. When a library exposes an interesting
> pattern, ADR, or breaking change, add a `### library/<name>` entry to the
> **consuming application's `REGISTRY.md`** under "Services and utilities" — that's
> where library usage is documented.

When you work on a sub-project, read its local `AGENTS.md` (applications only)
for the stack, the commands and the registry that apply there.

## Quality Standards

Workspace-wide quality bar — applies to every sub-project unless its local `AGENTS.md` overrides:

- **Test coverage target:** {{QUALITY_COVERAGE_TARGET}}
- **Test (workspace):** `{{TEST_COMMAND}}`
- **Lint (workspace):** `{{LINT_COMMAND}}`
- **Type-check (workspace):** `{{TYPECHECK_COMMAND}}`

Per-sub-project commands live in each sub-project's `AGENTS.md` under its `Test and lint commands` section.

## Before implementing

When the task involves a library, framework, or external API, retrieve
up-to-date documentation before writing code. Training data lags behind the
versions this workspace pins.

**Preferred source — `ctx7` CLI** (if available in PATH):
```bash
ctx7 library <name> <query>      # resolve library ID (e.g. /facebook/react)
ctx7 docs <libraryId> <query>    # fetch docs
```
Detect with `command -v ctx7`. If missing, invoke via `npx ctx7@latest <command>`.

**Fallback — Context7 MCP**: use `mcp__context7__resolve-library-id` +
`mcp__context7__query-docs` only if this project registered the server. The setup
does not install it: `npx ctx7@latest` covers the case where the CLI is missing
from PATH.

Rationale: the CLI is faster, streams output, and costs no MCP tool definitions
in the context of every session.

## Language

| Context | Language |
|---|---|
| Source code | English |
| Variable, function, class names | English |
| Commit messages | English |
| Code comments | English |
| Technical documentation (md) | English |
| User-facing error messages | English |

## Available MCPs

| MCP | When to use |
|---|---|
| **ClickUp** | Read tasks, update status, retrieve briefs |
| **Figma** | Retrieve design tokens, components, specifications |
| **Context7** | Up-to-date documentation for libraries and frameworks. **Prefer the `ctx7` CLI if available in PATH** — use this MCP only as fallback |

> **About `.mcp.json`** — committed, team-shared. For personal/IDE-specific servers use `claude mcp add --scope local <name> <command>` (writes to `~/.claude.json` only, never to a project file); for machine-specific values inside committed entries use `${VAR}` env var expansion (Claude Code expands at load time). See the [Claude Code MCP docs](https://code.claude.com/docs/en/mcp) for the full scope model.

{{VCS_OPS_NOTE}}

## Available agents

Agents are isolated sub-processes with their own context. Commands launch them
automatically when needed — no need to invoke them manually.

| Agent | Role |
|---|---|
| **clickup** | All ClickUp operations (read, update, create, filter). Faithful passthrough — returns data in full without reprocessing. |
| **review** | Isolated code review against the project rules. Proposes REGISTRY updates; does not modify files directly. |

## Workflows

| Command | When to use |
|---|---|
| `/dev-setup:setup` | Re-run the setup: refresh the generated rules and files from the current plugin |
| `/dev-setup:sdd [TASK_ID]` | Interactive Spec-Driven Development: generates a technical spec, discusses it at each checkpoint, then develops |
| `/dev-setup:auto-sdd [TASK_ID]` | Autonomous Spec-Driven Development: a background workflow takes the task to a review-ready MR/PR — it stops on its own when the spec does not survive review |
| `/dev-setup:review` | Code review of the current branch; updates the sub-project's `REGISTRY.md` |

> `/dev-setup:sdd` drives the flow interactively, with supervision at each
> checkpoint — its steps (discovery, spec, approval, development, verify) are
> skills the orchestrator invokes, not commands: there is nothing to type for
> them. `/dev-setup:auto-sdd` runs unsupervised instead, as a workflow: the spec
> is written, then attacked by three reviewers with one objection each, and two
> objections stop the run and hand it back to you. Development happens in its
> own git worktree, so your checkout never moves, and the MR still waits for
> your confirmation.

## Where the rules live

| What | Where |
|---|---|
| Rules on the code (design, errors, git, security, per-language) | `.claude/rules/` at the workspace root — the ones named `dev-setup-*.md` are generated by the setup and regenerated by its UPDATE mode; anything else there is this team's own and is never touched |
| Rules a machine can check (function length, naming, `any`, coverage floors) | ESLint / the test runner config / branch protection — a failure there is the rule talking |
| What is already built in a sub-project | that sub-project's `REGISTRY.md` |

---
*Version: 2.0.0*
*Generated by: ai-base-setup*
