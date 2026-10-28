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
and cannot stop the run: three reviewers look at it once and propose changes
grounded in the project's architectural choices, the spec author applies them
or declines them on the project's grounds in a single revision, and a
contradiction between the task and the project is settled by one precedence —
the project's ADRs, rules and libraries, then what the task promises its users,
then how the task says to build it.

Whatever that left behind travels to the merge request, where the reviewer is
the checkpoint: the proposals the author declined or left unanswered, each with
its answer (`openPoints`), the places the spec departed from the task text
(`deviations`) and the readings it chose where the task admitted two
(`toConfirm`). Do not turn any of them into a question in chat, and do not
re-run the workflow hoping for a cleaner spec.

When the reviewer disagrees with a reading the spec took, that is review
feedback on the merge request, handled like any other.

## failed — the spec, the dev step or the commands

`{ status: 'failed', stage, reason, output?, notes?, branch?, baseBranch?, worktreePath?, commits?, spec?, openPoints?, deviations?, toConfirm?, unverified? }`

`stage` says where: `intake` (the launcher passed bad arguments, or three empty
quality commands — a bug in the launch call, fix it), `spec`, `dev`, or `verify`
(the project lint, typecheck or test command came back red).

**A run that broke** — the workflow came back with neither outcome, or with
none at all — is handled as a `failed` at stage `broken`: the raw result is its
`reason`, and in a cloud session step 3 still saves whatever branch carries the
task.

1. Show `reason`, the dev agent's `notes` when there are any, and, when `verify`
   failed, the `output` as it came — that is the real command output, not a
   summary of it. Read `notes` before `reason`: on DE-17159 the dev agent
   stopped at a gate the spec set — the backend contract did not exist yet —
   and Verify then failed on a worktree nobody had installed. `reason` said the
   commands were red; `notes` said why.
2. Write the report — the note the board gets, and in a cloud session the body
   of the commit that saves the work — so whoever picks the task up can work
   from the board and the remote alone:
   - **why it failed** — the stage and `reason`, in one line;
   - **what is missing** — what stands between the branch and a merge request,
     read from `notes` and `output`: the blocker and who has to remove it, the
     failing command and its error, the steps of the spec's plan with no commit
     yet. Nothing the outcome does not say: a cause you infer is marked as
     inferred;
   - **the failing output** — its tail, as it came, when `verify` failed, or
     the raw result when the run broke;
   - **to resume** — fix the cause, check the branch out, and run
     `/dev-setup:sdd <taskId>`: it starts from the spec and the commits on it.
3. **In an ephemeral session, save the work and push it.** `CLAUDE_CODE_REMOTE`
   is `true` in a cloud session — a scheduled routine among them — and its disk
   goes when it ends: a branch left there is a branch lost, as it was on
   DE-17472 and DE-17159. Whatever the stage, write the report to a file
   outside the worktree, then:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/save-failed-run.sh" --task <taskId> \
     --stage <stage> --reason-file <report file> --json \
     [--dir "<worktreePath>"]
   ```

   `--dir` when the outcome carries a `worktreePath`; without it the script
   finds the worktree or the branch that carries the task id. When the outcome
   carries `spec.markdown` and no `branch` — the dev agent never made one —
   write it to a file too and add
   `--spec-file <that file> --spec-path "<spec.path>" --base "<baseBranch>" --title "<the task title, in English>" --type <branchType>`:
   the spec and its Challenge are most of what the run paid for.

   The script commits everything the worktree holds — an empty commit when it
   holds nothing, so the branch itself says why — with the report as the
   message body, and pushes the branch as it is, past the project's commit and
   push hooks: they are red, which is why the run failed. It is the one way
   past the gates, and it keeps that narrow itself: it refuses outside a cloud
   session and on a branch that does not carry the task id, never forces a
   push, and its message says the hooks were skipped. Never skip them any other
   way — no `--no-verify`, no `HUSKY=0`: the `deny` rules and the commit gate
   still refuse those. Its exit goes into the board note: `0` pushed, `4` saved
   but not pushed (`PUSH_ERROR` says why), `3` nothing to save (`REASON`), `1`
   a broken call (its stderr).

   Open no merge request: the task is the report, not a review request.
   Locally nothing changes: no commit, no push — the worktree survives on disk.
4. Stop the clock, then move the task to `BLOCKED` with the same bail-out call:
   one `update` whose note is the report, plus what step 3 did — the branch on
   `origin` with the commit that saved it, or why it is not there. The clock's
   `COMMENT` goes after the note.
5. Leave the branch and the worktree alone. They are the debugging material, and
   deleting them is the one thing that makes the failure unreadable.
6. End the report on one `Next:` line, the exact command for where it failed:
   - `verify` → `Next: cd "<worktreePath>" && <the command that failed>` — the
     red command, run where the code is;
   - `dev` → `Next: cd "<worktreePath>"` — the implementation as it stopped;
   - `spec` → `Next: /dev-setup:sdd <taskId>` — the interactive flow writes the
     spec with the developer;
   - `intake` → `Next: /dev-setup:auto-sdd <taskId>` — once the launch call is
     fixed.

A `verify` failure is the one worth resuming rather than relaunching: the spec,
the Challenge and the whole implementation come back from the journal cache
once the cause is fixed, and only the commands run again.

## ready-for-mr — push and open it

`{ status: 'ready-for-mr', taskId, branch, baseBranch, worktreePath, spec, commits[], filesChanged[], output, openPoints[], applied[], deviations[], toConfirm[], unchecked[], unverified[] }`

Every quality command this environment could run ran green in the worktree,
and the spec is committed on the branch. `unverified` lists the ones it could
not — `{ kind, command, reason }`: declared by the project, but their program,
service or runtime is not here (the launcher's `UNAVAILABLE`, or a command that
exited 126/127 at Verify). A missing toolchain does not stop a run: it goes to
the end, and the merge request says which checks nobody ran. When every
command is unverified, `output` is empty and nothing at all was checked. Two things are left, and they are the two the
workflow deliberately does not do:

```bash
git push -u origin "<branch>"
```

Then invoke `vcs-ops`: it reads `origin` and loads its GitHub or GitLab
reference itself. Open the merge request **against the short name of
`baseBranch`** (`origin/next` → `next`) — never against a branch you picked.

The `ask` rule on `gh pr create` / `glab mr create` is what puts a person in
front of this. It is a permission rule, not something to work around: if the
developer declines, report that, leave everything in place, and end on `Next:`
and the host reference's open command, filled in for this branch and base.

Finally, stop the clock and let the move carry what the task took:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" --task <taskId> --stop --json
```

`INTENT: update`, `PARAMS: task_id: <task_id>, status: CODE REVIEW, comment:
"<COMMENT>"` (`IN REVIEW` when the list has no `CODE REVIEW`) — `COMMENT`
verbatim, or no comment at all when the clock has nothing (`REASON` says why).
Never write a duration of your own: the work clock section of
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md` is the rule. Then show
the merge request link, the branch, the spec path and the commit subjects, and
end on one line: `Next:` and the follow-its-CI command from the host reference
`vcs-ops` loaded, filled in with the merge request's number or branch — this
checkout is not on that branch, so name it. It is not a question: the developer
runs it, or asks you to.

## The merge request

Title, language and labels from `mr-meta.sh`, as `vcs-ops` describes —
`Feat: <what was done, in LANGUAGE> [DE-123]`, with the task's priority as
`--priority`. Body as `vcs-ops` describes — the template, filled in and short —
plus what this flow owes a reviewer who was not watching:

- **not verified**, first of all, when `unverified` holds anything: one line
  per entry — the kind, the command, the reason — and that the run did not
  prove it. Whoever merges runs those commands, or waits for the CI that
  does: a green merge request that hides an unrun suite is the defect this
  section exists to prevent.
- **the real test output**, in a fenced block: the `output` field, as it came
  back. A reviewer has to see the suite passing without re-running it.
- **to confirm**, at the top, when `toConfirm` or `deviations` holds anything:
  each reading the spec took where the task admitted two, and each place it
  departed from the task text with what overruled it. Nobody was asked about
  them, so the reviewer is the first person to see them — they go first.
- **the open points**, when `openPoints` holds any: the reviewer's focus, the
  reason, the suggestion and the grounds, then the author's `answer` — what
  backs keeping the spec as it was, or *no answer* when it is empty. Nobody
  argued them a second time: the person reviewing the merge request is the one
  who reads both sides. They did not stop the run — they are what the reviewer
  should look at next.
- **what the challenge applied**: one line with the number of `applied`
  proposals, so the reviewer knows the spec was argued over.
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
launching again: a fresh run redoes the spec and the three reviews from
scratch, at the same cost as the first time. Resume is same-session only; once
the session is gone, so is the journal.

## When the run does not start

Three failures happen before any phase does, and none is a task problem:

- **`quality-preflight.sh` refuses** (exit 3) — the project does not say how
  to check its work: no `.claude/quality-commands.json`, a rejected one, or
  every command declared absent. A program not installed or a red declared
  preflight is not a refusal: with `--allow-unavailable` those commands come
  back in `UNAVAILABLE`, the run starts, and its merge request lists them as
  not verified. `REASON` says which, `OUTPUT` carries what failed. Nothing has
  started — no fork-point question, no `IN PROGRESS`, no clock, no `Workflow` —
  and what happens to the task depends on where it was read:
  - read in `SPRINT` (`auto-sdd`) → one bail-out call, `SPRINT → BLOCKED`, its
    note `REASON` and `OUTPUT`: the board says why the task cannot run here;
  - read in `BACKLOG` (`auto-sdd`) → left as found, and `REASON` and `OUTPUT`
    shown in chat. The backlog gate never moves a task on the flow's
    initiative, and the board has no `BACKLOG → BLOCKED` move;
  - `multi-sdd` → no task is read or touched: the check runs once, before the
    first read. Print `REASON` and `OUTPUT` and stop, as on `multi-preflight.sh`
    exit 3.

  The fix belongs to the project, not the task: `/dev-setup:setup` writes or
  repairs the declaration (step 3b), then launch again. Any other non-zero exit
  is a broken script — show its stderr and stop, with no board write.
- **`Workflow "dev-setup:auto-sdd-run" not found`** — the loaded plugin has no such
  workflow. The usual cause is a stale install shadowing a newer build: check
  that `${CLAUDE_PLUGIN_ROOT}/workflows/auto-sdd-run.js` exists, and if it does not,
  reinstall or rebuild the plugin. The same script can be launched by path with
  `scriptPath` while that is being fixed.
- **`status: 'failed', stage: 'intake'`** — the launcher passed bad arguments:
  a missing `taskId`, `pluginRoot` or `baseBranch`, a task id that is not a
  plain identifier, or a `stack` whose three commands are all empty — which the
  check above refuses first, so seeing it means that check was skipped. A
  `stack` whose commands are all `unavailable` is not this: it runs, unverified. The
  `reason` names which, and no agent ran. Fix the launch call, not the
  workflow.
