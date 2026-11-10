---
name: setup
description: Grafts the AI-native workflow onto a project — path-scoped rules, AGENTS.md, MCP servers, Bash sandbox, branch protection. Use when a project must be configured for AI agents for the first time, or when one the plugin already configured must be updated to the current template.
user-invocable: true
disable-model-invocation: true
disallowed-tools: Agent, WebFetch, WebSearch
allowed-tools: mcp__clickup__clickup_list_document_pages, mcp__clickup__clickup_get_document_pages, mcp__claude_ai_Google_Drive__search_files, mcp__claude_ai_Google_Drive__read_file_content
---

# Dev Setup

Everything is bundled. Two roots matter:

- `${CLAUDE_SKILL_DIR}/templates/` — the files installed into the project.
- `${CLAUDE_PLUGIN_ROOT}/scripts/` — the deterministic work. `--json` prints a
  flat object with `UPPER_SNAKE` keys; a missing value is the empty string.

Skills and agents are **not** installed: the plugin provides them.

## Step 1 — Check the client, detect the mode

First run `instruction-files.sh --json`. On `VERSION_OK=false`, **stop before
any write**, naming `CLAUDE_VERSION` and `MIN_CLAUDE_VERSION`: with no
`CLAUDE.md`, an older client reads no project instructions. An empty
`VERSION_OK` goes on; Step 5b reports it.

- **UPDATE** — `.claude/settings.json` exists *and* the project has
  `.claude/rules/dev-setup-core.md` or a legacy `CONSTITUTION.md`. Ask "Setup
  has already run. Update the files from the plugin?" and stop on a no.
- **GREENFIELD** — no `package.json`, `pyproject.toml`, `requirements.txt`,
  `go.mod`, `pubspec.yaml` or `Cargo.toml`, and no source file outside config.
- **EXISTING** — every other case.

Report the mode first.

## The procedure

Run the steps **in this order**, reading only the reference each one names.

| Step | What | Mode | Reference |
|---|---|---|---|
| 2 | Stack detection (`detect-stack.sh --json`) | EXISTING, UPDATE | `existing.md` |
| 2b | Stack selection — ask the developer | GREENFIELD | `greenfield.md` |
| 2c | VCS detection — the host of `origin` | all | `install.md` |
| 3 | Install the plugin's resources (3.1–3.9) | all | `install.md` |
| 3b | Declare and verify the quality commands | all (GREENFIELD: after 8) | `quality-commands.md` |
| 4 | Render the path-scoped rules | all | `rules-generation.md` |
| 5, 5b | Generate AGENTS.md; check the instruction files | all | `agents-generation.md` |
| 6, 7 | MCP servers and `.env.example` | all | `mcp-env.md` |
| 7b | Protect the reference branch | github, gitlab | `mcp-env.md` |
| 7c | `worktree.baseRef` | all | `mcp-env.md` |
| 7d | `.claude/auto-dev.json` | all | `mcp-env.md` |
| 7e | `product.md` | all | `product-context.md` |
| 8 | Scaffold the project | GREENFIELD | `greenfield.md` |
| 9 | Summary — the steps' one-line reports | all | the mode's |

`existing.md` and `greenfield.md` are mutually exclusive: never read both.

## Two rules that hold everywhere

- **Never write `.env` — and no setup step reads it.** Step 3.2 denies writes;
  every step works on `.env.example`. A step that appears to need the real
  file is wrong — report it.
- **Ask before overwriting.** Conflict detection runs before every write. Two
  exceptions: `.claude/rules/dev-setup-*.md` in UPDATE mode (the prefix
  contract is in `rules-generation.md`), and a `CLAUDE.md` holding only
  `@AGENTS.md`, which Step 5b removes in every mode.
