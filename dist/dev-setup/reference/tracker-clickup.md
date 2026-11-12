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
| Dependency | `clickup_add_task_dependency` |
| Link | `clickup_add_task_link` |
| Search | `clickup_search` |
| Create doc | `clickup_create_document` |
| Create doc page | `clickup_create_document_page` |
| Update doc page | `clickup_update_document_page` |

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
| `task_types`, `parent`, `tags`, `relations`, `search` | yes |
| `docs` | yes — ClickUp Docs |

## Intents

- **`read`** — `clickup_get_task` with `task_id` (a `custom_id` is accepted)
  and `include: ["description", "subtasks", "dependencies"]`; not found →
  `STATUS: error`, `ERROR: Task <id> not found`. Every field in the result,
  the description in full.
- **`update`** — with a `status`: validate the canonical transition, map the
  target to the board's name (each candidate in order, until ClickUp accepts
  one). Call `clickup_update_task` with the status and, when given,
  `markdown_description` set to the whole `description`; with a description,
  read the task once more and check it is exactly the one you wrote, else
  `STATUS: error` with the url. With a `comment`, `clickup_create_task_comment`.
- **`create`** — ClickUp applies the list's task-type template **after**
  creation, asynchronously: a description sent with the create call can be
  overwritten, or get the template's empty skeleton appended, and the template
  can reset the priority. So a create is four calls, never one:
  1. `clickup_create_task` with `list_id`, `name` and, when given, `task_type`
     (by name — `Epic`, `User Story`), `parent` (a subtask), `tags`,
     `assignees`, `due_date`. **No description, no priority.**
  2. Read it back with `clickup_get_task`, up to 10 times, until the template
     has landed: the description is not empty any more, or the custom fields are
     populated. If it never lands, go on and record `WARNING: template not
     detected`.
  3. `clickup_update_task` with `markdown_description` set to the
     `description` received — the whole text, replacing whatever the template
     wrote — and `priority` when given, by name: 1 `urgent`, 2 `high`,
     3 `normal`, 4 `low`.
  4. Read it once more and compare the description: if it is not exactly
     yours, wait a moment and repeat step 3, then read again — at most twice.
     Still different → `WARNING: description still carries the template` with
     the url.
  Every requested tag missing from the task goes in `TAGS_MISSING`. A
  `task_type` ClickUp refuses is `STATUS: error` — never the default type in
  silence. Step 3 failing after step 1: retry once, then `STATUS: error` **with
  the task's `task_id` and `url`**.
- **`relate`** — `blocked_by`: `clickup_add_task_dependency` with `task_id`,
  `depends_on: <target_id>`, `type: waiting_on`. `related`:
  `clickup_add_task_link` with `task_id` and `links_to: <target_id>`.
- **`search`** — `clickup_search` with `keywords` and `filters: {asset_types:
  ["task"], location: {subcategories: [<list_id>]}}`, every page; one compact
  block per task (`task_id`, `key`, `name`, `status`, `task_type`, `url`), no
  description.
- **`create-doc`** — `clickup_create_document` with `name`, `visibility`,
  `create_page: false` and `parent: {id: <parent_id>, type: <4 space, 5
  folder, 6 list>}`; return `doc_id` and `url`.
- **`create-page`** — `clickup_create_document_page` with `document_id`,
  `name`, `content` as received and `content_format: text/md`.
- **`update-page`** — `clickup_update_document_page` with `document_id`,
  `page_id`, `content`, `content_format: text/md` and `content_edit_mode:
  replace`.
- **`filter`** — `clickup_filter_tasks` with `list_ids: [<list_id>]`, the
  board's name for a `status`, `tag` in `tags`; while the response says
  `has_more`, call again with the next `page`. Every result, untruncated.
- **`next-task`** — `filter` on `READY`, sorted by priority, the first one; none
  → `STATUS: error`, `ERROR: No tasks in READY in list <list_id>`.

MCP missing → `STATUS: error`, `ERROR: ClickUp MCP not configured. Run: claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`.

## Headless backend

`${CLAUDE_PLUGIN_ROOT}/scripts/auto-dev-clickup.sh` — `auto-dev-tracker.sh
--provider clickup` hands the call to it unchanged. It talks to the REST API with a personal token from
`CLICKUP_API_TOKEN` (`pk_…`), and needs `CLICKUP_TEAM_ID` to resolve a custom id.
`CLICKUP_API_BASE` points it elsewhere (the tests). Network: `api.clickup.com`.
