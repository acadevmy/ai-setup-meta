# The three outcomes of an auto-sdd run

The workflow returns one object. Its `status` decides everything that happens
next; the rest of the object is what you report. The ClickUp calls follow
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

## Index

- [needs-human — two lenses objected](#needs-human--two-lenses-objected)
- [failed — the spec, the dev step or the commands](#failed--the-spec-the-dev-step-or-the-commands)
- [ready-for-mr — push and open it](#ready-for-mr--push-and-open-it)
- [The merge request](#the-merge-request)
- [What a run leaves behind](#what-a-run-leaves-behind)

## needs-human — two lenses objected

`{ status: 'needs-human', taskId, objections[], spec, openQuestions[] }`

Two of the three adversarial lenses refused the spec, so the run stopped before
writing any code. There is no branch, no worktree and no merge request.

1. Show each objection with its lens (`simpler`, `scope`, `testable`) and its
   reason, then the `openQuestions` the spec author had flagged.
2. Move the task to `BLOCKED` with the bail-out call of the contract — one
   `update` carrying the status and the note. The note holds the objections
   verbatim: they are the work a human has to do.
3. Say what unblocks it: answer the objections in the task description, then
   `BLOCKED → SPRINT` and run this skill again.

Do not argue with the objections and do not re-run the workflow hoping for a
different verdict. Two lenses out of three is the gate, and it is in code.

## failed — the spec, the dev step or the commands

`{ status: 'failed', stage, reason, output?, branch?, worktreePath? }`

`stage` says where: `intake` (the launcher passed bad arguments — that is a bug
in step 3 of the skill, fix the call), `spec`, `dev`, or `verify` (the project
lint, typecheck or test command came back red).

1. Show `reason` and, when `verify` failed, the `output` as it came — that is the
   real command output, not a summary of it.
2. Move the task to `BLOCKED` with the same bail-out call, naming the stage, the
   reason and the branch.
3. Leave the branch and the worktree alone. They are the debugging material, and
   deleting them is the one thing that makes the failure unreadable.

## ready-for-mr — push and open it

`{ status: 'ready-for-mr', taskId, branch, baseBranch, worktreePath, spec, commits[], filesChanged[], output, objections[] }`

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
rotation [DE-123]`. Body as `vcs-ops` describes, plus two things this flow owes
a reviewer who was not watching:

- **the real test output**, in a fenced block: the `output` field, as it came
  back. A reviewer has to see the suite passing without re-running it.
- **the lens that objected**, when `objections` holds one. One objection does
  not stop the run — the gate needs two — but it is exactly what the reviewer
  should look at first. Quote its lens and its reason.

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

An interrupted run resumes from its journal, so the agents that finished come
back from cache and only the unfinished ones run again:

```json
Workflow({
  "name": "dev-setup:auto-sdd",
  "args": { "…": "the same arguments as the launch" },
  "resumeFromRunId": "<the runId the launch returned>"
})
```

Resume it rather than launching again: a fresh run redoes the spec and the three
challenges from scratch, at the same cost as the first time.
