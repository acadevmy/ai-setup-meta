# The three outcomes of an auto-sdd run

The `auto-sdd` workflow returns one object. Its `status` decides everything that
happens next; the rest of the object is what you report. Two skills launch that
workflow — `auto-sdd` for one task, `multi-sdd` for up to five — and both act on
an outcome exactly the way this file describes, one outcome at a time. The
ClickUp calls follow `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

## Index

- [needs-human — a decision only the business can make](#needs-human--a-decision-only-the-business-can-make)
- [Answering the question](#answering-the-question)
- [failed — the spec, the dev step or the commands](#failed--the-spec-the-dev-step-or-the-commands)
- [ready-for-mr — push and open it](#ready-for-mr--push-and-open-it)
- [The merge request](#the-merge-request)
- [What a run leaves behind](#what-a-run-leaves-behind)
- [When the run does not start](#when-the-run-does-not-start)

## needs-human — a decision only the business can make

`{ status: 'needs-human', taskId, objections[], residual[], addressed[], unchecked[], revisions, overruled[], spec, openQuestions[] }`

The lenses' objections do not stop a run: each one comes with a suggestion, the
spec is rewritten on it at most twice, and whatever still stands goes to the
merge request. The one thing that stops it is an objection of kind `decision` —
the task admits readings that lead to different behaviour and nothing in the
repository picks one. `objections` holds those; `residual` holds the fixable
ones still standing, which travel on once the run resumes. There is no branch,
no worktree and no merge request yet.

1. Show each `decision` objection with its lens and its reason, then the
   `openQuestions` the spec author flagged. That is the question to answer.
2. Ask the developer, and read the next section for what their answer means.
3. Only if they do not want to deal with it now, move the task to `BLOCKED` with
   the bail-out call of the contract — one `update` carrying the status and the
   note. The note holds the objections verbatim, and the clock's `COMMENT`
   (`--stop`) goes after it: the spec phase was work too.

Do not answer the question yourself and do not re-run the workflow hoping for a
different verdict. A business decision is the gate, it is in code, and the only
thing that moves it is a person.

## Answering the question

Whatever the developer answers — "read it this way", or "the lens is wrong,
there is no real choice here" — name the lenses they answered and resume the
run with their words:

```json
Workflow({
  "name": "dev-setup:auto-sdd",
  "args": { "…": "the same arguments as the launch",
            "resolved": ["scope"], "guidance": "<their answer, in their words>" },
  "resumeFromRunId": "<the runId the launch returned>"
})
```

`resolved` names lenses, and only a named lens comes off the count: `guidance`
alone leaves the question open and the run stops again. Both are read after the
Challenge phase and nowhere before it, so the spec, the verdicts and the
revisions come back from the journal cache. One agent then writes the answer
into the spec's `## Technical decisions`, and the run goes on to Dev. The
decision travels into the dev prompt and into the merge request — it is
recorded, never silent.

When the answer changes the task itself rather than choosing between readings
of it, there is nothing to resume: put it in the task description,
`BLOCKED → SPRINT`, and launch again.

Never fill `resolved` from your own reading of the objection. It exists to carry
a person's decision, and a run that clears its own gate is the auto-approval
this workflow was written to remove.

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

`{ status: 'ready-for-mr', taskId, branch, baseBranch, worktreePath, spec, commits[], filesChanged[], output, objections[], addressed[], unchecked[], revisions, overruled[], guidance }`

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
- **the decision**, when `overruled` holds one: the question each answered
  lens raised, and the `guidance` the developer gave, quoted. It is in the spec
  too, but a reviewer who disagrees with it is the last checkpoint it has, so it
  goes at the top.
- **the objections still standing**, when `objections` holds any: the lens,
  the reason and the suggestion the spec was not rewritten on after
  `revisions` rounds. They did not stop the run — they are exactly what the
  reviewer should look at first.
- **what the challenge settled**: one line with `revisions` and the number of
  `addressed` objections, so the reviewer knows the spec was argued over.
- **the lens that never answered**, when `unchecked` names one: its verifier
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

An interrupted run resumes from its journal the same way an answered one does —
`resumeFromRunId` with the arguments of the launch — so the agents that finished
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
