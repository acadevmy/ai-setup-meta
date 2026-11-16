# Tracker adapter: Linear

How the `tracker` agent carries out the contract
(`${CLAUDE_PLUGIN_ROOT}/reference/tracker-contract.md`) on Linear. Only the
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

- registered by the setup as `linear`, over OAuth, user scope:
  `claude mcp add linear -t http -s user https://mcp.linear.app/mcp`
- each developer authenticates with their own Linear account
- a developer who reaches Linear through the claude.ai connector has the same
  tools under the `mcp__claude_ai_Linear__` prefix: use whichever is available
- `list_id` is a Linear **team key** (`ENG`); a task belongs to exactly one team

## Tools

The agent is granted the whole server (`mcp__linear`, `mcp__claude_ai_Linear`)
and uses only these. Their names are the Linear server's own; when a call fails
on a name, list the server's tools and use the one that does the same operation.

| Operation | Tool |
|---|---|
| Read issue | `get_issue` |
| List / filter issues | `list_issues` |
| Create issue | `create_issue` |
| Update issue | `update_issue` |
| Comment | `create_comment` |
| The team's workflow states | `list_issue_statuses` |

Never delete, archive or move an issue to another team: status updates and
comments only, as on every tracker.

## Status map

Linear groups a team's workflow states by **type**: `backlog`, `unstarted`,
`started`, `completed`, `canceled`. The map names states, not types, because a
team has several states of one type (`In Progress` and `In Review` are both
`started`). The default the setup proposes; `.claude/tracker.json` wins.

| Canonical | Linear default |
|---|---|
| `BACKLOG` | `Backlog` |
| `READY` | `Todo` |
| `IN PROGRESS` | `In Progress` |
| `IN REVIEW` | `In Review` |
| `DONE` | `Done` |
| `BLOCKED` | `Blocked` — not one of Linear's default states: the team has to add it, or map `blocked` to a state it has |

To move an issue, resolve the state's id from `list_issue_statuses` for the
issue's team, by name, case-insensitively, then `update_issue` with that id. A
name the team does not have → `STATUS: error`, `ERROR: Linear team <key> has no
state named <name>; set status.<canonical> in .claude/tracker.json`.

## Key format

The issue identifier (`ENG-42`) is the key. Every Linear issue has one.

## Capabilities

| Capability | Supported |
|---|---|
| `comments` | yes |
| `time_tracking` | no — the work clock's line travels in the closing comment |
| `parent` | yes — a sub-issue (`parentId`) |
| `tags` | yes — Linear labels, which must exist on the team |
| `task_types` | as a label of the same name (`Epic`, `User Story`), when the team has it; otherwise `TAGS_MISSING` names it |
| `relations` | yes — `blocks` / `related` issue relations |
| `search` | yes |
| `docs` | no — `create-doc`, `create-page` and `update-page` answer `STATUS: unsupported`, `CAPABILITY: docs` |

## Intents

- **`read`** — `get_issue` with the identifier. Every field; `description` is
  markdown, in full.
- **`update`** — validate the canonical transition, resolve the state (above),
  `update_issue`; with a `comment`, `create_comment`.
- **`create`** — `create_issue` in the team `list_id`, with `title` = `name`
  and `description`, `parentId` for a `parent`, and the labels named by `tags`
  and `task_type`. `priority` maps one to one: Linear's `1` urgent … `4` low
  is the contract's scale. Read it back and compare the description.
- **`update`** with a `description` — `update_issue` with the whole text, read
  back to check.
- **`relate`** — `blocked_by`: a `blocks` relation from `target_id` to
  `task_id`; `related`: a `related` relation.
- **`search`** — `list_issues` for the team with the keywords as the query;
  compact blocks, no description.
- **`filter`** — `list_issues` for the team, with the state's name for a
  `status` and the assignee. Every result, untruncated.
- **`next-task`** — `filter` on `READY`, sorted by priority (`0` means none:
  last), the first one; none → `STATUS: error`, `ERROR: No issues in READY in
  team <key>`.

MCP missing → `STATUS: error`, `ERROR: Linear MCP not configured. Run: claude mcp add linear -t http -s user https://mcp.linear.app/mcp`.

## Headless backend

`${CLAUDE_PLUGIN_ROOT}/scripts/tracker-linear.sh`, sourced by
`auto-dev-tracker.sh`. It talks to the GraphQL API with a personal API key from
`LINEAR_API_KEY` (`lin_api_…`). `LINEAR_API_URL` points it elsewhere (the
tests). Network: `api.linear.app`.
