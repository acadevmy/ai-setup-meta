---
name: setup
description: Grafts the AI-native workflow onto a project — path-scoped rules, AGENTS.md, MCP servers, Bash sandbox, branch protection. Use when a project must be configured for AI agents for the first time, or when one the plugin already configured must be updated to the current template.
model: opus
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Dev Setup

Everything is bundled in the plugin — nothing is downloaded. Two roots matter:

- `${CLAUDE_SKILL_DIR}/templates/` — the files installed into the project; the
  references name each one where they use it.
- `${CLAUDE_PLUGIN_ROOT}/scripts/` — the deterministic work, done by scripts
  instead of re-derived from prose. One contract: `--json` prints a flat object
  with `UPPER_SNAKE` keys, a missing value is the empty string, diagnostics go
  to stderr.

Skills and agents are **not** installed: the plugin provides them.

## Step 1 — Detect the mode

- **UPDATE** — `.claude/settings.json` exists *and* the project has
  `.claude/rules/dev-setup-core.md` or a legacy `CONSTITUTION.md`. Ask "Setup
  has already run. Update the files from the plugin?" and stop on a no.
- **GREENFIELD** — no `package.json`, `pyproject.toml`, `requirements.txt`,
  `go.mod`, `pubspec.yaml` or `Cargo.toml`, and no source file outside config.
- **EXISTING** — every other case.

Report the mode before proceeding.

## The procedure

Run the steps **in this order**, reading only the reference each one names.

| Step | What | Mode | Reference |
|---|---|---|---|
| 2 | Stack detection (`detect-stack.sh --json`) | EXISTING, UPDATE | `existing.md` |
| 2b | Stack selection — ask the developer | GREENFIELD | `greenfield.md` |
| 2c | VCS detection — which host `origin` belongs to | all | `install.md` |
| 3 | Install the plugin's resources (3.1–3.6) | all | `install.md` |
| 4 | Render the path-scoped rules | all | `rules-generation.md` |
| 5, 5b | Generate AGENTS.md and CLAUDE.md | all | `agents-generation.md` |
| 6, 7 | MCP servers and `.env.example` | all | `mcp-env.md` |
| 7b | Branch protection on the reference branch | github, gitlab | `mcp-env.md` |
| 8 | Scaffold the project | GREENFIELD | `greenfield.md` |
| 9 | Summary — collects the one-line reports of the steps above | all | the mode's |

Each reference is one hop from here. `existing.md` and `greenfield.md` are the
two mode branches: they are mutually exclusive, and reading both is the cost
this split removes.

## Two rules that hold everywhere

- **Never read or write `.env`.** Step 3.2 denies it to the file tools and to
  sandboxed commands. No step needs it: a step that appears to require it is
  wrong — report it, do not work around the deny.
- **Ask before overwriting.** Conflict detection runs before every write. The
  one exception is `.claude/rules/dev-setup-*.md` in UPDATE mode: those are
  generated artefacts, and `rules-generation.md` holds the prefix contract that
  makes overwriting them safe.
