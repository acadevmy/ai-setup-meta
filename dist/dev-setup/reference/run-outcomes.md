# The three outcomes of an auto-sdd run

The `auto-sdd` workflow returns one object. Its `status` decides everything that
happens next; the rest of the object is what you report. Two skills launch that
workflow — `auto-sdd` for one task, `multi-sdd` for up to five — and both act on
an outcome exactly the way this file describes, one outcome at a time. The
ClickUp calls follow `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

## Index

- [needs-human — two lenses objected](#needs-human--two-lenses-objected)
- [Answering the objections](#answering-the-objections)
- [failed — the spec, the dev step or the commands](#failed--the-spec-the-dev-step-or-the-commands)
- [ready-for-mr — push and open it](#ready-for-mr--push-and-open-it)
- [The merge request](#the-merge-request)
- [What a run leaves behind](#what-a-run-leaves-behind)
- [When the run does not start](#when-the-run-does-not-start)

## needs-human — two lenses objected

`{ status: 'needs-human', taskId, objections[], overruled[], spec, openQuestions[] }`

Two of the three adversarial lenses refused the spec, so the run stopped before
writing any code. There is no branch, no worktree and no merge request.

1. Show each objection with its lens (`simpler`, `scope`, `testable`) and its
   reason, then the `openQuestions` the spec author had flagged.
2. Ask the developer, and read the next section for what their answer means.
3. Only if they do not want to deal with it now, move the task to `BLOCKED` with
   the bail-out call of the contract — one `update` carrying the status and the
   note. The note holds the objections verbatim.

Do not argue with the objections yourself and do not re-run the workflow hoping
for a different verdict. Two lenses out of three is the gate, it is in code, and
the only thing that moves it is a person.

## Answering the objections

An objection is either wrong or right, and the two have different fixes.

**The objection is wrong** — the developer explains why the lens missed
something. Name the lenses they cleared and resume the run:

```json
Workflow({
  "name": "dev-setup:auto-sdd",
  "args": { "…": "the same arguments as the launch",
            "resolved": ["simpler"], "guidance": "<their words>" },
  "resumeFromRunId": "<the runId the launch returned>"
})
```

`resolved` names lenses, and only a named lens comes off the count: `guidance`
alone leaves two objections standing and the run stops again. Both are read
after the Challenge phase and nowhere before it, so the spec and the three lens
verdicts come back from the journal cache and the run restarts at Dev. The
ruling travels into the dev prompt and into the merge request — an overrule is
recorded, never silent.

**The objection is right** — the spec was built on a decision the task never
made. Then there is nothing to resume: the spec is the first thing the run does,
so a new spec means a new run. Put the answer in the task description,
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
2. Move the task to `BLOCKED` with the same bail-out call, naming the stage, the
   reason and the branch.
3. Leave the branch and the worktree alone. They are the debugging material, and
   deleting them is the one thing that makes the failure unreadable.

A `verify` failure is the one worth resuming rather than relaunching: the spec,
the challenges and the whole implementation come back from the journal cache
once the cause is fixed, and only the commands run again.

## ready-for-mr — push and open it

`{ status: 'ready-for-mr', taskId, branch, baseBranch, worktreePath, spec, commits[], filesChanged[], output, objections[], overruled[] }`

The tests, the linter and the type checker ran green in the worktree, and the
spec is committed on the branch. Two things are left, and they are the two the
workflow deliberately does not do:

```bash
git push -u origin <branch>
```

Then invoke `vcs-ops`: it reads `origin` and loads its GitHub or GitLab
reference itself. Open the merge request **against the short name of
`baseBranch`** (`origin/next` → `next`) — never against a branch you picked.

The `ask` rule on `gh pr create` / `glab mr create` is what puts a person in
front of this. It is a permission rule, not something to work around: if the
developer declines, report that and leave everything in place.

Finally, `INTENT: update`, `PARAMS: task_id: <task_id>, status: CODE REVIEW`
(`IN REVIEW` when the list has no `CODE REVIEW`), and show the merge request
link, the branch, the spec path and the commit subjects.

## The merge request

Title: Conventional Commits with the id — `feat(auth): add refresh token
rotation [DE-123]`. Body as `vcs-ops` describes, plus what this flow owes a
reviewer who was not watching:

- **the real test output**, in a fenced block: the `output` field, as it came
  back. A reviewer has to see the suite passing without re-running it.
- **the lens that objected**, when `objections` holds one. One objection does
  not stop the run — the gate needs two — but it is exactly what the reviewer
  should look at first. Quote its lens and its reason.
- **the lens the developer overruled**, when `overruled` holds one, with the
  `guidance` they gave. A reviewer who disagrees with the overrule is the last
  checkpoint it has.

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
