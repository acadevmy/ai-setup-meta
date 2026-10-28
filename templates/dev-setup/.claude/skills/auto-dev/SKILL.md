---
name: auto-dev
description: Runs the autonomous SDD workflow for one task headless, inside `claude -p` on a disposable checkout — spec with a context pack, one reviewer, one-commit development, the project own quality commands — and writes result.json and pr-body.md for the runner. Use when a job runner, not a person, starts the work and pushes, opens the merge request and closes the task itself.
effort: low
argument-hint: "--args <path to args.json>"
user-invocable: true
disable-model-invocation: true
---

# Auto dev

The launcher of the `auto-dev-run` workflow (`workflows/auto-dev-run.js`), for a run
nobody watches. It asks nothing, pushes nothing and opens nothing: it starts
the work, runs the workflow and leaves files. The runner that started
`claude -p` pushes, opens the merge request and closes the task from them.

**Usage**: `/dev-setup:auto-dev --args /abs/path/args.json`. The args file's
shape is in `auto-dev-args.sh --help`. With a person at the keyboard, use
`auto-sdd` instead.

Four calls, in order. Between them, write nothing but the call.

## 1. The arguments

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/auto-dev-args.sh" --args "<the path in $ARGUMENTS>" --json
```

Exit 3 → print its JSON and stop: it already wrote `result.json`, and nothing
else runs — no board write, no workflow. Any other non-zero exit → print its
stderr and stop.

## 2. The board

Only when `TRACKER` is `clickup`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/auto-dev-clickup.sh" --task "<TASK_ID>" --start --json
```

It moves the task to `IN PROGRESS` and starts its work clock. A non-zero exit
skips step 3: write its output and stderr, as plain text, to
`<OUTPUT_DIR>/outcome.json` and go to step 4.

## 3. The run

```json
Workflow({ "name": "dev-setup:auto-dev-run", "args": <WORKFLOW_ARGS, parsed as JSON> })
```

Pass `WORKFLOW_ARGS` exactly as step 1 returned it, as a JSON object — not as a
string, and not retyped field by field. The task text is in `TASK_FILE`; the
workflow's agents read it there.

The run works in the background: wait for its notification, never poll. When
it ends, write its return value — the JSON object, exactly as it came, nothing
added and nothing left out — to `<OUTPUT_DIR>/outcome.json`. A run that came
back with no object: write what came back instead.

## 4. The report

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/auto-dev-report.sh" \
  --outcome "<OUTPUT_DIR>/outcome.json" --launch "<LAUNCH_FILE>" \
  --session "${CLAUDE_SESSION_ID}" --json
```

Always run it, whatever happened in steps 2 and 3: a missing or malformed
outcome is reported as a run that broke. Your final message is its JSON
output, and nothing else.

## What the runner does next

From `<OUTPUT_DIR>/result.json`: on `ready-for-mr`, push `branch` and open the
merge request against the short name of `baseBranch` with `mr.title`,
`mr.labels` and `pr-body.md`; on `failed`, push the branch when there is one.
Then close the task:

```bash
bash "<plugin>/scripts/auto-dev-clickup.sh" --task <taskId> --finish \
  --result <OUTPUT_DIR>/result.json [--mr-url <url>] [--pushed true|false]
```

After `claude -p --output-format json` exits, the exact token counts:

```bash
bash "<plugin>/scripts/auto-dev-report.sh" --finalize \
  --result <OUTPUT_DIR>/result.json --claude-result <claude's JSON output>
```
