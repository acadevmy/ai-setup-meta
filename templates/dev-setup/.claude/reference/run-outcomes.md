# The two outcomes of an auto-sdd run

The `auto-sdd` workflow returns one object. Its `status` decides everything that
happens next; the rest of the object is what you report. Two skills launch that
workflow — `auto-sdd` for one task, `multi-sdd` for up to five — and both act on
an outcome exactly the way this file describes, one outcome at a time. The
ClickUp calls follow `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

## Index

- [Nothing waits for a person](#nothing-waits-for-a-person)
- [failed — the spec, the dev step or the commands](#failed--the-spec-the-dev-step-or-the-commands)
- [ready-for-mr — push and open it](#ready-for-mr--push-and-open-it)
- [The merge request](#the-merge-request)
- [What a run leaves behind](#what-a-run-leaves-behind)
- [When the run does not start](#when-the-run-does-not-start)

## Nothing waits for a person

There is no outcome that asks a question. The Challenge phase improves the spec
and cannot stop the run: three reviewers propose changes grounded in the
project's architectural choices, the spec author integrates them or declines
them on the project's grounds, at most twice, and a contradiction between the
task and the project is settled by one precedence — the project's ADRs, rules
and libraries, then what the task promises its users, then how the task says to
build it.

Whatever that left behind travels to the merge request, where the reviewer is
the checkpoint: the proposals still open (`openPoints`), the places the spec
departed from the task text (`deviations`) and the readings it chose where the
task admitted two (`toConfirm`). Do not turn any of them into a question in
chat, and do not re-run the workflow hoping for a cleaner spec.

When the reviewer disagrees with a reading the spec took, that is review
feedback on the merge request, handled like any other.

## failed — the spec, the dev step or the commands

`{ status: 'failed', stage, reason, output?, branch?, worktreePath? }`

`stage` says where: `intake` (the launcher passed bad arguments — that is a bug
in the launch call, fix it), `spec`, `dev`, or `verify` (the project lint,
typecheck or test command came back red).

1. Show `reason` and, when `verify` failed, the `output` as it came — that is the
   real command output, not a summary of it.
2. Stop the clock, then move the task to `BLOCKED` with the same bail-out call:
   one `update` naming the stage, the reason and the branch, with the clock's
   `COMMENT` after the note.
3. Leave the branch and the worktree alone. They are the debugging material, and
   deleting them is the one thing that makes the failure unreadable.

A `verify` failure is the one worth resuming rather than relaunching: the spec,
the challenges and the whole implementation come back from the journal cache
once the cause is fixed, and only the commands run again.

## ready-for-mr — push and open it

`{ status: 'ready-for-mr', taskId, branch, baseBranch, worktreePath, spec, commits[], filesChanged[], output, openPoints[], settled[], deviations[], toConfirm[], unchecked[], revisions }`

The tests, the linter and the type checker ran green in the worktree, and the
spec is committed on the branch. Two things are left, and they are the two the
workflow deliberately does not do:

```bash
git push -u origin "<branch>"
```

Then invoke `vcs-ops`: it reads `origin` and loads its GitHub or GitLab
reference itself. Open the merge request **against the short name of
`baseBranch`** (`origin/next` → `next`) — never against a branch you picked.

The `ask` rule on `gh pr create` / `glab mr create` is what puts a person in
front of this. It is a permission rule, not something to work around: if the
developer declines, report that and leave everything in place.

Finally, stop the clock and let the move carry what the task took:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" --task <taskId> --stop --json
```

`INTENT: update`, `PARAMS: task_id: <task_id>, status: CODE REVIEW, comment:
"<COMMENT>"` (`IN REVIEW` when the list has no `CODE REVIEW`) — `COMMENT`
verbatim, or no comment at all when the clock has nothing (`REASON` says why).
Never write a duration of your own: the work clock section of
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md` is the rule. Then show
the merge request link, the branch, the spec path and the commit subjects.

## The merge request

Title, language and labels from `mr-meta.sh`, as `vcs-ops` describes —
`Feat: <what was done, in LANGUAGE> [DE-123]`, with the task's priority as
`--priority`. Body as `vcs-ops` describes — the template, filled in and short —
plus what this flow owes a reviewer who was not watching:

- **the real test output**, in a fenced block: the `output` field, as it came
  back. A reviewer has to see the suite passing without re-running it.
- **to confirm**, at the top, when `toConfirm` or `deviations` holds anything:
  each reading the spec took where the task admitted two, and each place it
  departed from the task text with what overruled it. Nobody was asked about
  them, so the reviewer is the first person to see them — they go first.
- **the open points**, when `openPoints` holds any: the reviewer's focus, the
  reason and the suggestion still standing after `revisions` rounds. They did
  not stop the run — they are what the reviewer should look at next.
- **what the challenge settled**: one line with `revisions` and the number of
  `settled` proposals, so the reviewer knows the spec was argued over.
- **the focus that never answered**, when `unchecked` names one: its reviewer
  died twice, so the spec was not checked through it. Say so plainly.

Link the task and the spec (`spec.path`, committed on the branch).

## What a run leaves behind

The dev agent worked in a worktree the harness created, so the developer
checkout never moved. The worktree stays as long as it holds changes: that is
what makes a failed run inspectable, and what makes a second run on the same
task refuse the branch it already created. Both are cleaned the git way:

```bash
git worktree list
git worktree remove <path>
```

An interrupted run resumes from its journal — `resumeFromRunId` with the
arguments of the launch — so the agents that finished
come back from cache and only the unfinished ones run again. Resume rather than
launching again: a fresh run redoes the spec and the three challenges from
scratch, at the same cost as the first time. Resume is same-session only; once
the session is gone, so is the journal.

## When the run does not start

Two failures happen before any phase does, and neither is a task problem:

- **`Workflow "dev-setup:auto-sdd" not found`** — the loaded plugin has no such
  workflow. The usual cause is a stale install shadowing a newer build: check
  that `${CLAUDE_PLUGIN_ROOT}/workflows/auto-sdd.js` exists, and if it does not,
  reinstall or rebuild the plugin. The same script can be launched by path with
  `scriptPath` while that is being fixed.
- **`status: 'failed', stage: 'intake'`** — the launcher passed bad arguments:
  a missing `taskId`, `pluginRoot` or `baseBranch`, or a task id that is not a
  plain identifier. The `reason` names which. Fix the launch call, not the
  workflow.
