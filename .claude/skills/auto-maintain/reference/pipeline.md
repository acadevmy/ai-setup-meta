# The pipeline, step by step

Steps 0 to 9 of `auto-maintain`, with the state-file bookkeeping that makes a
run resumable. Every step prints `[STEP n START]` and `[STEP n END]` so an
interrupted run is readable from the log alone.

## Index

- [Step 0 — Resume detection + preflight](#step-0--resume-detection--preflight)
- [Step 1 — Task selection](#step-1--task-selection)
- [Step 2 — Lock the task](#step-2--lock-the-task)
- [Step 3 — Branch](#step-3--branch)
- [Step 4 — Classify the task intent](#step-4--classify-the-task-intent)
- [Step 5 — Apply the changes](#step-5--apply-the-changes)
- [Step 6 — Validate](#step-6--validate)
- [Step 7 — Commit](#step-7--commit)
- [Step 8 — Push + PR](#step-8--push--pr)
- [Step 9 — Move the task](#step-9--move-the-task)

## Step 0 — Resume detection + preflight

**First of all**, check whether a state file from a previous run exists:

```bash
STATE_FILE=".automaint-state.json"
if [[ -f "$STATE_FILE" ]]; then
  NEXT_STEP=$(jq -r '.next_step' "$STATE_FILE")
  TASK_ID=$(jq -r '.task_id // ""' "$STATE_FILE")
  CUSTOM_ID=$(jq -r '.custom_id // ""' "$STATE_FILE")
  BRANCH=$(jq -r '.branch // ""' "$STATE_FILE")
  TASK_NAME=$(jq -r '.task_name // ""' "$STATE_FILE")
  TASK_DESC=$(jq -r '.task_desc // ""' "$STATE_FILE")
  TASK_URL=$(jq -r '.task_url // ""' "$STATE_FILE")
  INTENT_TYPE=$(jq -r '.intent_type // ""' "$STATE_FILE")
  echo "[RESUME] Resuming from Step $NEXT_STEP — task $CUSTOM_ID branch $BRANCH"
else
  NEXT_STEP=1
  echo "[START] Starting the pipeline from Step 1"
fi
```

If `NEXT_STEP > 1`: skip every completed step (the branch exists, the task is
already IN PROGRESS, and so on) and go straight to the step indicated.

**Preflight** (always, resume or not):

1. **Do not load `.env.local`.** `source .env.local` exports *every* secret in
   the file into the environment of the process and all its children, to use two
   of them. The variables come from the environment (the Routine in the cloud,
   the shell locally); if something is missing, the pipeline exits rather than
   going looking for it.
2. Check `CLICKUP_MAINTENANCE_LIST_ID`: if empty or absent, print
   "`CLICKUP_MAINTENANCE_LIST_ID` is not configured." and exit successfully
   (no-op).
3. **Only if `NEXT_STEP == 1`**: check that `git status --porcelain` is clean. If
   it is dirty, exit with "Working tree not clean, aborting." On a resume
   (`NEXT_STEP > 1`) the working tree may hold the previous run's changes: that
   is expected, carry on.
4. Check GitHub authentication — the CLI resolves `GH_TOKEN` or the credential
   store on its own, without the value passing through here:

   ```bash
   gh auth status
   ```

   If it fails: exit with "`gh` is not authenticated: set `GH_TOKEN` in the
   Routine environment or run `gh auth login`."
5. Configure the credential helper for the push, so the token never ends up in a
   URL:

   ```bash
   gh auth setup-git
   ```

## Step 1 — Task selection

*(Skip if `NEXT_STEP > 1` — the variables are already restored from the state
file.)*

1. Fetch the `SPRINT` tasks from the list:

   ```
   mcp__clickup__clickup_filter_tasks(list_id: CLICKUP_MAINTENANCE_LIST_ID, statuses: ["SPRINT"])
   ```

2. Sort by priority (lower is more urgent: 1 = urgent, 4 = low) and take the
   first.
3. If the list is empty: print "No task in SPRINT, exiting." and exit
   successfully.
4. Extract `TASK_ID`, `CUSTOM_ID`, `TASK_NAME`, `TASK_DESC`, `TASK_PRIORITY`,
   `TASK_URL`.
5. Write the state file:

   ```bash
   jq -n \
     --arg task_id "$TASK_ID" --arg custom_id "$CUSTOM_ID" \
     --arg task_name "$TASK_NAME" --arg task_desc "$TASK_DESC" \
     --arg task_url "$TASK_URL" --arg started_at "$(date -Iseconds)" \
     '{next_step: 2, task_id: $task_id, custom_id: $custom_id, branch: "",
       task_name: $task_name, task_desc: $task_desc,
       task_url: $task_url, started_at: $started_at}' > .automaint-state.json
   ```

## Step 2 — Lock the task

*(Skip if `NEXT_STEP > 2`.)* `SPRINT → IN PROGRESS`.

1. ```
   mcp__clickup__clickup_update_task(task_id: TASK_ID, status: "IN PROGRESS")
   ```
2. ```
   mcp__clickup__clickup_create_task_comment(task_id: TASK_ID, comment_text: "🤖 Starting automated processing by the auto-maintain pipeline.")
   ```
3. On an MCP error: exit with `STATUS: error` — no tagged bail-out, the task is
   still in SPRINT.
4. `jq '.next_step = 3' .automaint-state.json > .tmp && mv .tmp .automaint-state.json`

## Step 3 — Branch

*(Skip if `NEXT_STEP > 3` — the branch already exists.)*

1. Make sure you are on an up-to-date `main`. In the cloud the repo is already
   cloned on the default branch — run `git pull --ff-only origin main` if you
   are not on the latest revision. Locally:
   `git checkout main && git pull --ff-only origin main`.
2. Derive `slug` from the task `name`: lowercase, kebab-case, at most 50
   characters, `[a-z0-9-]` only.
3. `git checkout -b chore/<custom_id>-<slug>` (e.g.
   `chore/AI-42-add-mcp-helper-skill`).
4. ```bash
   jq --arg branch "$BRANCH" '.next_step = 4 | .branch = $branch' .automaint-state.json > .tmp && mv .tmp .automaint-state.json
   ```

## Step 4 — Classify the task intent

*(Skip if `NEXT_STEP > 4`.)* Read `TASK_DESC` and work out the kind of change:

| Type | Indicators | Typical target files |
|---|---|---|
| `skill-update` | "skill", "/project: command" | `templates/<dom>/.claude/skills/`, `shared/skills/` |
| `mcp-update` | "MCP", "context server", "claude mcp add" | `templates/<dom>/.mcp.json`, related docs |
| `profile-update` | "profile", "stack", "Next.js/Angular/Flutter" | `templates/<dom>/profiles/` |
| `agent-update` | "agent", "subagent" | `templates/<dom>/.claude/agents/`, `shared/agents/` |
| `rules-update` | "rule", "constraint", "governance", "constitution" | `templates/<dom>/rules/` |
| `manifest-update` | "manifest", "shared_agents", "required_files" | `templates/<dom>/manifest.json` |
| `docs-update` | "AGENTS.md", "README", "documentation" | `AGENTS.md`, `README.md`, `docs/` |

If no type can be inferred with reasonable confidence: **bail out**.

```bash
jq --arg intent "$INTENT_TYPE" '.next_step = 5 | .intent_type = $intent' .automaint-state.json > .tmp && mv .tmp .automaint-state.json
```

## Step 5 — Apply the changes

*(On a resume at step 5 the working tree may hold partial changes from the
previous run — re-read the files and apply the changes idempotently, do not
duplicate what is already there.)*

1. Apply the changes `TASK_DESC` asks for, with Edit/Write.
2. For every file, follow the meta-repo conventions:
   - English everywhere — code, comments and `.md` files
   - skill frontmatter: `name`, `description`, `user-invocable` where
     appropriate
   - agent frontmatter: `name`, `description`, `tools`, `model`. **Do not add
     `permissionMode`**: an agent that picks its own permission level bypasses
     the project's `ask` rules, which are the human checkpoints.
   - no secrets, no tokens, no API keys in plain text
3. If the task needs coherent updates across several files (a new shared agent
   plus its manifest reference, say), include them in the same logical commit.
4. If an ambiguity comes up that `TASK_DESC` cannot resolve: **bail out**.
5. `jq '.next_step = 6' .automaint-state.json > .tmp && mv .tmp .automaint-state.json`

## Step 6 — Validate

*(Skip if `NEXT_STEP > 6`.)*

1. Run `/project:validate`.
2. If it fails: **bail out** with the details.
3. If any `.sh` script was touched, run `bash -n <file>` as a syntax check.
4. `jq '.next_step = 7' .automaint-state.json > .tmp && mv .tmp .automaint-state.json`
5. Run `bash scripts/build-plugin.sh <domain>` to regenerate `dist/`.

## Step 7 — Commit

*(Skip if `NEXT_STEP > 7`.)*

1. Stage only the files you actually changed: `git add <path1> <path2> …` —
   never `git add -A`.
2. Conventional Commits, in English:

   ```
   <type>(<scope>): <imperative description>

   Refs: <custom_id>
   ```

3. `jq '.next_step = 8' .automaint-state.json > .tmp && mv .tmp .automaint-state.json`

## Step 8 — Push + PR

*(Skip if `NEXT_STEP > 8`.)*

1. Push the branch. The credential helper configured in the preflight
   (`gh auth setup-git`) supplies the credentials to git: **no token in the URL,
   so no token in `ps aux` or in the run log.**

   ```bash
   git push -u origin "HEAD:refs/heads/$BRANCH"
   ```

2. Write the PR body to a file instead of passing it as an argument: it is
   multi-line, and a file avoids both the escaping problems and a huge command
   line in the log.

   ```bash
   printf '%s' "$PR_BODY" > .automaint-pr-body.md
   ```

   Title format (Conventional Commits):

   ```
   <type>(<scope>): <description> [<custom_id>]
   ```

   Body, fixed structure:

   ```markdown
   ## 🤖 Automatically generated PR

   **ClickUp task**: [<custom_id>](<task_url>)
   **Change type**: <type inferred at Step 4>
   **Task priority**: <priority>

   ### What changes
   <bullet list of what was concretely modified>

   ### Why
   <the rationale from TASK_DESC, paraphrased concisely>

   ### How to test
   <concrete verification steps, e.g.:
    - run `/project:validate`
    - inspect the files at <path>
    - rebuild the plugin with `bash scripts/build-plugin.sh <domain>`>

   ### Files touched
   - <path1>
   - <path2>

   ---
   ⚠️ This PR was generated by an autonomous agent. Review it carefully before merging.
   ```

3. Open the PR with the label already applied (one of `skill`, `profile`,
   `constitution`, `template`, `release`), and clean up the body file:

   ```bash
   PR_URL=$(gh pr create \
     --base main \
     --head "$BRANCH" \
     --title "$PR_TITLE" \
     --body-file .automaint-pr-body.md \
     --label "$LABEL")
   rm -f .automaint-pr-body.md
   ```

   If the command fails or `PR_URL` is empty: **bail out** with `gh`'s stderr as
   the detail (remove `.automaint-pr-body.md` either way).

4. `jq '.next_step = 9' .automaint-state.json > .tmp && mv .tmp .automaint-state.json`

## Step 9 — Move the task

`IN PROGRESS → CODE REVIEW`.

1. ```
   mcp__clickup__clickup_update_task(task_id: TASK_ID, status: "CODE REVIEW")
   ```
2. ```
   mcp__clickup__clickup_create_task_comment(task_id: TASK_ID, comment_text: "🤖 PR opened: <PR_URL>")
   ```
3. Delete the state file — the pipeline is done: `rm -f .automaint-state.json`
4. Print the final summary: `custom_id`, branch, `pr_url`, then
   `[STEP 9 END] DONE`.
