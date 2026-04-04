---
name: pm-setup-agent
description: Domain agent for AI-Native setup of PM projects. Configures ClickUp MCP, installs PM governance and task creation workflows.
tools: Read, Grep, Glob, Bash
model: opus
permissionMode: dontAsk
---

# PM Setup Agent

Domain agent for configuring the AI-Native workflow for Project Managers.
Downloads resources from ai-setup-meta and applies them.

---

## Source configuration

```
SOURCE_REPO: acadevmy/ai-setup-meta
SOURCE_BRANCH: main
```

File fetching is done via `gh api` (GitHub CLI), which automatically handles
authentication and works with private repos as well. The PM must be authenticated
with `gh auth login`.

## Manifest-driven download

This agent reads `templates/pm-setup/manifest.json` from the source repo to know
which files to download. The manifest declares:

- `shared_agents` → downloaded from `shared/agents/<name>`
- `shared_skills` → downloaded from `shared/skills/<name>/SKILL.md`
- `template_skills` → downloaded from `templates/pm-setup/.claude/skills/<name>/SKILL.md`
- `required_files` → template files (PM-CONSTITUTION, AGENTS.template, etc.)

## Download strategy

Downloaded files are divided into two categories:

- **Verbatim**: downloaded directly to the final destination (skills, agents, settings).
  Conflict detection is performed before each download.
- **With transformation**: downloaded to a local staging area (`.claude/.setup-tmp/`),
  transformed, then written to the final destination.
  Applies to: AGENTS.template.md (minimal transformation).

---

## Complete procedure

Execute the following steps **in the order indicated**. Do not skip any step.

### Step 1 — Detect the mode

Analyze the current project to determine the operating mode:

1. **UPDATE** — If both `PM-CONSTITUTION.md` AND `AGENTS.md` already exist in the project root.
   Ask the PM: "Setup has already been executed. Do you want to update the files?"
   If they answer no, stop.

2. **FRESH** — In all other cases. Setup has not been executed yet.

Communicate the detected mode to the PM before proceeding.

---

### Step 2 — Download resources

Using the manifest, download all required files from the source repo.

#### 2.1 Create staging area

```bash
mkdir -p .claude/.setup-tmp
```

#### 2.2 Download required files

For each file in `required_files`:

```bash
gh api -H "Accept: application/vnd.github.raw+json" \
  /repos/acadevmy/ai-setup-meta/contents/templates/pm-setup/<file>?ref=main \
  > .claude/.setup-tmp/<file>
```

#### 2.3 Download shared skills

For each skill in `shared_skills`:

```bash
mkdir -p .claude/skills/<skill>
gh api -H "Accept: application/vnd.github.raw+json" \
  /repos/acadevmy/ai-setup-meta/contents/shared/skills/<skill>/SKILL.md?ref=main \
  > .claude/skills/<skill>/SKILL.md
```

#### 2.4 Download shared agents

For each agent in `shared_agents`:

```bash
mkdir -p .claude/agents
gh api -H "Accept: application/vnd.github.raw+json" \
  /repos/acadevmy/ai-setup-meta/contents/shared/agents/<agent>?ref=main \
  > .claude/agents/<agent>
```

#### 2.5 Download template skills

For each skill in `template_skills`:

```bash
mkdir -p .claude/skills/<skill>
gh api -H "Accept: application/vnd.github.raw+json" \
  /repos/acadevmy/ai-setup-meta/contents/templates/pm-setup/.claude/skills/<skill>/SKILL.md?ref=main \
  > .claude/skills/<skill>/SKILL.md
```

---

### Step 3 — Install resources

#### 3.1 PM-CONSTITUTION.md

Copy from staging to project root:
```bash
cp .claude/.setup-tmp/PM-CONSTITUTION.md ./PM-CONSTITUTION.md
```

#### 3.2 settings.json

Copy settings:
```bash
mkdir -p .claude
cp .claude/.setup-tmp/.claude/settings.json .claude/settings.json
```

#### 3.3 .gitignore

If `.gitignore` exists, merge (add missing lines only).
If not, copy from staging.

---

### Step 4 — Generate AGENTS.md

Read `.claude/.setup-tmp/AGENTS.template.md`.
Write directly as `AGENTS.md` (no placeholders to substitute for PM setup).

Create `CLAUDE.md` with content:
```
@AGENTS.md
```

---

### Step 5 — Configure MCP servers

#### 5.1 ClickUp (mandatory)

```bash
claude mcp add clickup --transport url https://mcp.clickup.com/mcp -s user
```

#### 5.2 Figma (optional)

Ask the PM if they want to configure Figma for design analysis.

If yes:
```bash
claude mcp add figma --transport http https://mcp.figma.com/mcp -s user
```

---

### Step 6 — Cleanup

```bash
rm -rf .claude/.setup-tmp
```

---

### Step 7 — Summary

Show a summary to the PM with installed files, configured MCPs, and available commands.

```
PM Setup completed!

Files installed:
- PM-CONSTITUTION.md
- AGENTS.md + CLAUDE.md
- .claude/settings.json
- .gitignore (updated)

MCPs configured:
- ClickUp: yes
- Figma: <yes/no>

Available commands:
- /project:pm-flow [PATH]   — full flow: document → ClickUp tasks
- /project:pm-intake [PATH] — parse document → Discovery Brief
- /project:pm-structure      — brief → Epic/Story/Task hierarchy
- /project:pm-refine         — INVEST validation + Acceptance Criteria
- /project:pm-review         — review and approval
- /project:pm-publish        — publish to ClickUp
```
