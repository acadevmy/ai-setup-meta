---
name: start-task
description: Takes a ClickUp task and starts the complete development flow (branch, TDD, review, PR)
model: opus
user-invocable: true
disable-model-invocation: true
---

# /project:start-task

Takes a specific task or the next task from the ClickUp list and starts the development flow.

**Usage**: `/project:start-task [TASK_ID]`
- With `TASK_ID` (e.g. `DE-123`): retrieves that task directly from ClickUp
- Without arguments: looks for the next task in the ClickUp list

## Complete flow

### 1. Retrieve the task via ClickUp Agent

**If a TASK_ID was provided** (argument `$ARGUMENTS`):
- Launch the `clickup` agent with:
  - INTENT: `read`
  - PARAMS: `task_id: <provided TASK_ID>`
- If the agent returns STATUS: error, inform the developer and stop

**If a TASK_ID was NOT provided**:
- Read `CLICKUP_SETUP_LIST_ID` from the `.env` file in the project root
- If the variable is not configured, inform the developer to fill in `.env` and stop
- Launch the `clickup` agent with:
  - INTENT: `next-task`
  - PARAMS: `list_id: <CLICKUP_SETUP_LIST_ID>`
- If the agent returns STATUS: error (no tasks in SPRINT), inform the developer and stop

From the agent output, extract:
- `custom_id` (e.g. DE-123)
- `name` (title)
- `description` (description/brief — reported in full by the agent)
- `priority`
- `task_id` (for subsequent updates)

### 2. Create the working branch
Determine the branch type from the task title/description:
- Feature → `feat/`
- Bug → `fix/`
- Maintenance → `chore/`

Create the branch with the customId:
```bash
git checkout main
git pull origin main
git checkout -b <type>/<customId>-<short-description>
```

Example: `feat/DE-123-add-user-auth`

### 3. Update the task status

Launch the `clickup` agent with:
- INTENT: `update`
- PARAMS: `task_id: <task_id>, status: IN PROGRESS`

### 4. Show the brief to the developer
Present a summary:
```
Task:     DE-123 — Task title
Priority: High
Branch:   feat/DE-123-add-user-auth
Status:   IN PROGRESS

Description:
<task description content — as returned by the agent>
```

### 5. Start development
Proceed with the TDD flow (Constitution rule 9):
1. Analyze requirements from the brief
2. Write tests describing the expected behavior
3. Verify they fail (red)
4. Implement the minimum code to make them pass (green)
5. Refactoring (refactor)

### 6. On completion — Quality, review and PR
When development is completed:

1. **Commit** with Conventional Commits (include the customId):
   ```
   feat(auth): add refresh token rotation [DE-123]
   ```

2. **Simplify** — Run the `simplify` skill to review the modified code:
   - Look for opportunities to reuse existing code
   - Improve quality and efficiency
   - Fix any issues found
   - If there are changes, commit them: `refactor(<scope>): simplify implementation`

3. **Review** — Run `/project:review` to:
   - Verify CONSTITUTION.md compliance (via the Review Agent)
   - Verify code quality
   - Automatically update `REGISTRY.md` with new entries

4. **Push** the branch:
   ```bash
   git push -u origin <branch-name>
   ```

5. **Open PR** with `gh pr create`:
   - Title: follows Conventional Commits with customId
   - Body: includes What / Why / How to test sections + link to ClickUp task

6. **Update status** — Launch the `clickup` agent with:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: IN REVIEW`

## Expected output
- Branch created with customId in the name
- Code optimized (simplify) and CONSTITUTION-compliant (review)
- `REGISTRY.md` updated with new entries
- Task moved: SPRINT → IN PROGRESS → IN REVIEW
- PR opened on GitHub with reference to the ClickUp task
