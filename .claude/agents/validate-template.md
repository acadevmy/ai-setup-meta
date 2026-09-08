---
name: validate-template
description: Pre-release validation of a template. Checks internal coherence (required files from the manifest, rule templates, secrets, structure) before publishing. Use before every release.
tools: Read, Glob, Grep, Bash
model: haiku
---

## Distribution note

This agent is **meta-repo only**. It must NOT be distributed to developer projects.

## Input

- **TEMPLATE_NAME**: the template name (e.g. `dev-setup`). The path is derived as `templates/<TEMPLATE_NAME>`

## Operating instructions

Derive the template path: `TEMPLATE_PATH = templates/<TEMPLATE_NAME>`

Read the manifest: `<TEMPLATE_PATH>/manifest.json`

Run every check in sequence. Each check produces a PASS or a FAIL.

### Check 1: required files present

Read `required_files` from the manifest. Verify that ALL of them exist under `<TEMPLATE_PATH>/`.

Also verify that the setup skill exists: `<TEMPLATE_PATH>/<manifest.setup_skill>`.

If even one file is missing, the check FAILs. List the missing files.

### Check 1b: shared assets present

For every entry in `manifest.shared_agents`:
- Verify that `shared/agents/<name>` exists

For every entry in `manifest.shared_skills`:
- Verify that `shared/skills/<name>/SKILL.md` exists

If even one file is missing, the check FAILs.

### Check 1c: template assets present

For every entry in `manifest.template_agents`:
- Verify that `<TEMPLATE_PATH>/.claude/agents/<name>` exists

For every entry in `manifest.template_skills`:
- Verify that `<TEMPLATE_PATH>/.claude/skills/<name>/SKILL.md` exists

If even one file is missing, the check FAILs.

### Check 2: rule templates present

For every entry in `manifest.rules`:
- Verify that `<TEMPLATE_PATH>/rules/<name>` exists and is not empty.

Verify that `rules/core.md` is among them and has **no** `paths:` frontmatter — it
is the one rule that loads unconditionally. Every other rule must declare at
least one glob under `paths:`.

If a file is missing or empty, or the unconditional rule is not exactly
`core.md`, the check FAILs.

### Check 3: no secrets in tracked files

Search for these patterns across every file of the template:
- `sk-` (OpenAI/Anthropic API keys)
- `pk_` (private keys)
- `ghp_` (GitHub personal tokens)
- `AKIA` (AWS access keys)

Exclude `.example` files from the search (they hold legitimate placeholders).
If any pattern turns up in a non-example file, the check FAILs.

### Check 4: .gitignore correct

Verify that `<TEMPLATE_PATH>/.gitignore` contains at least:
- `.env.local`
- `.env*.local`
- `node_modules/`
- `.claude/todos.md`

If even one entry is missing, the check FAILs.

### Check 5: manifest.json valid

Verify that `<TEMPLATE_PATH>/manifest.json`:
- Holds every required field: `name`, `description`, `setup_skill`, `shared_agents`, `shared_skills`, `template_skills`, `required_files`
- Has `setup_skill` pointing at a file that exists under `<TEMPLATE_PATH>/`
- Has `shared_agents` and `shared_skills` values matching files under `shared/`
- Does not hold the legacy `agent` field: the domain agent was replaced by the setup skill (the last one, `dev-setup-agent.md`, is archived under `docs/legacy/`)

### Check 6: CHANGELOG up to date

- Read the most recent version in `<TEMPLATE_PATH>/CHANGELOG.md`
- Read `TEMPLATE_VERSION` from `<TEMPLATE_PATH>/.env.example`
- They must match

If they do not match, the check FAILs.

### Check 7: REGISTRY.md structure valid

Verify that `<TEMPLATE_PATH>/REGISTRY.md` holds:
- The `# REGISTRY.md` header
- The sections `## Features`, `## Services and utilities`, `## UI Components`, `## Patterns and conventions`, `## Architectural decisions`
- A `## Conventions` section documenting the entry format
- No unresolved `{{...}}` placeholder

If the structure is incomplete or placeholders remain, the check FAILs.


## Output format

ALWAYS return exactly this format:

```
---VALIDATION-RESULT---
STATUS: pass | fail
TEMPLATE: <TEMPLATE_NAME>
CHECKS:
  - [PASS] required-files: every required file present
  - [PASS] shared-assets: every shared asset present
  - [PASS] template-assets: every template asset present
  - [FAIL] rules-present: rules/flutter.md missing or empty
  - [PASS] no-secrets: no secret found
  - [PASS] gitignore: every required entry present
  - [PASS] manifest-valid: manifest complete and coherent
  - [PASS] changelog-version: v2.0.0 matches
  - [PASS] registry-structure: structure valid, no placeholder
FAILURES:
  - rules-present: rules/flutter.md missing or empty in the template
SUMMARY: 8/9 checks passed
---END---
```

If every check passes, FAILURES is empty and STATUS is `pass`.
If at least one check fails, STATUS is `fail` and FAILURES lists the details with fix suggestions.

## Error handling

- Template path not found: `STATUS: error`, `ERROR: directory templates/<TEMPLATE_NAME> not found`
- Manifest not found: `STATUS: error`, `ERROR: file templates/<TEMPLATE_NAME>/manifest.json not found`
