---
name: clickup
description: Reference documentation for ClickUp operations via MCP (statuses, workflow, task CRUD)
user-invocable: false
disable-model-invocation: false
---

# Skill: ClickUp Operations

ClickUp operations via MCP. Use for reading tasks, updating statuses,
and creating team notifications.

## Prerequisites
- ClickUp MCP configured via OAuth: `claude mcp add clickup https://mcp.clickup.com/mcp`
- Each developer authenticates with their own ClickUp account (guest accounts supported)
- Each operation works on a specific `list_id` — no global `TEAM_ID` required

## Workflow statuses

```
SPRINT  →  IN PROGRESS  →  IN REVIEW / CODE REVIEW  →  DONE
```

| Status | Meaning |
|---|---|
| SPRINT | Task planned in the current sprint, ready to be picked up |
| IN PROGRESS | Development in progress |
| IN REVIEW / CODE REVIEW | PR opened, awaiting review |
| DONE | Completed and merged |

## Available operations

### Get the next task to work on
```
Use the ClickUp MCP to retrieve tasks with:
  - Status filter: SPRINT
  - Sort by: priority (1 = urgent, 2 = high, 3 = normal, 4 = low)
  - Pick the first task with the highest priority

The returned task contains the `custom_id` field (e.g. DE-123) which should
be used in the branch name.
```

### Read a task
```
Use the ClickUp MCP to retrieve task details given its ID.
Output: title, description, status, assignees, custom fields, custom_id
```

### Update task status
```
Use the ClickUp MCP to update the status.
Input: task ID, new status

Valid transitions:
  SPRINT       → IN PROGRESS        (when starting work)
  IN PROGRESS  → IN REVIEW          (when the PR is opened)
  IN PROGRESS  → CODE REVIEW        (alternative to IN REVIEW)
  IN REVIEW    → DONE               (after merge)
  CODE REVIEW  → DONE               (after merge)
```

### Create a task
```
Use the ClickUp MCP to create a new task.
Required fields:
  - list_id: destination list ID
  - name: task title
  - description: description (markdown supported)
Optional fields:
  - assignees: list of user IDs
  - priority: 1 (urgent) / 2 (high) / 3 (normal) / 4 (low)
  - due_date: Unix timestamp
```

## Typical use cases in the meta-repo

**Release notification**: after `/project:release`, create a task for each
developer with update instructions.

**Setup tracking**: track the adoption of the new template by the team.
