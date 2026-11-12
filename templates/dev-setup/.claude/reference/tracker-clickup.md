# Tracker adapter: ClickUp

How the `tracker` agent carries out the contract
(`${CLAUDE_PLUGIN_ROOT}/reference/tracker-contract.md`) on ClickUp. Only the
agent reads this file; a skill that needs something from here needs a new
intent instead.

## Index

- [Server](#server)
- [Tools](#tools)
- [Status map](#status-map)
- [Key format](#key-format)
- [Capabilities](#capabilities)
- [Intents](#intents)
- [Headless backend](#headless-backend)

## Server

- registered by the setup as `clickup`, over OAuth, user scope:
  `claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`
- each developer authenticates with their own ClickUp account (guest accounts
  work)
- a developer who reaches ClickUp through the claude.ai connector has the same
  tools under the `mcp__claude_ai_ClickUp__` prefix: use whichever prefix is
  available
- `list_id` is a ClickUp list id (`app.clickup.com/.../li/<ID>`); there is no
  global `TEAM_ID`

## Tools

| Operation | Tool (`mcp__clickup__` or `mcp__claude_ai_ClickUp__` prefix) |
|---|---|
| Read task | `clickup_get_task` |
| Update task | `clickup_update_task` |
| Create task | `clickup_create_task` |
| Filter tasks | `clickup_filter_tasks` |
| Task comment | `clickup_create_task_comment` |
| Read comments | `clickup_get_task_comments` |

Always the full name, prefix included: an abbreviated name fails.

## Status map

The default the setup proposes; the project's `.claude/tracker.json` wins.
ClickUp matches status names case-insensitively.

| Canonical | ClickUp default |
|---|---|
| `BACKLOG` | `BACKLOG` |
| `READY` | `SPRINT` |
| `IN PROGRESS` | `IN PROGRESS` |
| `IN REVIEW` | `CODE REVIEW`, then `IN REVIEW` — two lists use different names for the same stage |
| `DONE` | `DONE` |
| `BLOCKED` | `BLOCKED` |

Reading a task, map the board's status back to the canonical one by the same
table, case-insensitively; a status the map does not hold is reported as
`board_status` with an empty canonical `status`.

## Key format

The key is the task's `custom_id` (`DE-123`). A task without one has an empty
`key`, and `task_id` is ClickUp's internal id.

## Capabilities

| Capability | Supported |
|---|---|
| `comments` | yes |
| `time_tracking` | yes — the headless backend logs the clock there |

## Intents

- **`read`** — `clickup_get_task` with `task_id` (a `custom_id` is accepted);
  not found → `STATUS: error`, `ERROR: Task <id> not found`. Every field in
  the result, the description in full.
- **`update`** — validate the canonical transition, map the target to the
  board's name (each candidate in order, until ClickUp accepts one), call
  `clickup_update_task`; with a `comment`, `clickup_create_task_comment`.
- **`create`** — `clickup_create_task` with `list_id`, `name`, `description`
  (markdown) and the optional fields; `priority` is ClickUp's own scale
  (1 urgent … 4 low).
- **`filter`** — `clickup_filter_tasks` with `list_id` and, for a `status`, the
  board's name for it. Every result, untruncated.
- **`next-task`** — `filter` on `READY`, sorted by priority, the first one; none
  → `STATUS: error`, `ERROR: No tasks in READY in list <list_id>`.

MCP missing → `STATUS: error`, `ERROR: ClickUp MCP not configured. Run: claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`.

## Headless backend

`${CLAUDE_PLUGIN_ROOT}/scripts/tracker-clickup.sh`, sourced by
`auto-dev-tracker.sh`. It talks to the REST API with a personal token from
`CLICKUP_API_TOKEN` (`pk_…`), and needs `CLICKUP_TEAM_ID` to resolve a custom id.
`CLICKUP_API_BASE` points it elsewhere (the tests). Network: `api.clickup.com`.
