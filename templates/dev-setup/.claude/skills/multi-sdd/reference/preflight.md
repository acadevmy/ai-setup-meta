# Phase A — the pre-flight

Everything a person has to decide, decided before any run starts. One task at a
time, in the order they were given: all of task A's questions, then all of task
B's. Every question here follows
`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md` — after you ask, the turn
ends.

## Index

- [The intake](#the-intake)
- [Triage — is this even a fan-out task?](#triage--is-this-even-a-fan-out-task)
- [The only questions worth asking](#the-only-questions-worth-asking)
- [Where the answers go](#where-the-answers-go)
- [The overlap warning](#the-overlap-warning)
- [The board](#the-board)

## The intake

**Ids on the command line.** Read each one through the `clickup` agent —
`INTENT: read`, `PARAMS: task_id: <id>`, per
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`. Keep `custom_id`, `name`,
`description` **verbatim**, `url` and `task_id`.

**`--from-sprint <n>`.** Resolve the list id as the contract describes, then
`INTENT: filter`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`.
Sort by `priority` ascending — `1` is urgent — and take the first `n`. Then run
the gate again with the ids you got, one quoted `--task` each:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/multi-preflight.sh" --json --task "DE-1" --task "DE-2"
```

Nothing in `SPRINT` means zero ids, which that call refuses: say so and stop. No
run, no board write. This is why the intake goes back through the gate rather
than trusting the count — the board decides how many there really were.

## Triage — is this even a fan-out task?

For each task, estimate the files it will touch — you need that estimate anyway,
both for the overlap check and to judge the bar — and say which side of `quick`
it falls on:

- **at most three files, no new component, dependency or public interface** →
  it is a `quick` task. A whole autonomous run for a one-line fix costs a spec,
  three verifiers and a worktree to save four turns.
- **anything larger** → it belongs in the fan-out.

Propose, then let the developer decide with `AskUserQuestion`, header `Route`:
**Fan it out** or **Drop it — I will `quick` it**. Never reroute silently in
either direction: the command they typed is the decision, and this is only the
chance to revise it before five runs start.

## The only questions worth asking

Ask about the decisions **no agent can invent**: which of two behaviours the
product wants, what a limit or a default should be, whether existing records are
migrated, who is allowed to do the thing. These are business calls, and inventing
one produces a merge request built on a guess nobody made.

Do not ask about anything the codebase, the rules or the spec can settle — which
pattern, how to structure it, what to name it, which library is already there.
The spec agent decides those and the three adversarial lenses attack them; asking
here just spends the developer's attention twice.

One question at a time, and end the turn on it. A task with nothing genuinely
open is the normal case: say so in one line and move to the next task.

## Where the answers go

An answer nobody carries is a question nobody should have asked. Append what the
developer said to the `description` you pass that task's run, marked for what it
is:

```
<the description, verbatim>

## Answered at pre-flight
- <the question> → <their answer, their words>
```

The spec agent reads that block as part of the task, so the decision lands in the
spec instead of in `openQuestions`, and the `scope` lens can check the spec
against it. Never edit the task on the board to record this.

## The overlap warning

Once every task has passed triage, one call compares them — the estimates from
the triage, and the worktrees already in flight, in the same comparison:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-info.sh" --json \
  --impact "DE-1=src/auth/token.service.ts,src/app.module.ts" \
  --impact "DE-2=src/billing/plan.service.ts,src/app.module.ts"
```

`OVERLAP_COUNT` greater than zero means `OVERLAPS` names files more than one
declarer claims, with the tasks or branches that claim them:

```
src/app.module.ts	DE-1,DE-2
```

Show every line and ask with `AskUserQuestion`, header `Overlap`: **Start them
all** — the rebase is expected rather than discovered — or **Drop one** and name
which. In a single interactive flow this is only a warning; here it earns a stop,
because dropping a task now costs nothing, and two autonomous branches that
rewrote the same file cost a reviewer twice.

## The board

Phase A writes nothing to it. A task the developer drops has to come out of the
pre-flight exactly as it went in, so the `SPRINT → IN PROGRESS` move happens at
launch, per task, in `fan-out.md`.
