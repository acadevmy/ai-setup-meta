# The fork point

The question every flow that cuts a branch asks, in one shape wherever it is
asked: **the repository resolves a default, the developer decides.** It is worth
a stop because the mistake is not small and not visible — a branch cut from the
wrong long-lived ref carries the whole delta between two of them into its diff,
its verify, its review and its merge request, and the first person to notice is
the reviewer.

## Resolving the default

Never hard-code `main`. Two calls answer it, depending on who is asking:

- **`sdd-start.sh` without `--create`** — the flows that cut the branch
  themselves. `BASE_BRANCH` is the ref HEAD forked from most recently.
- **`check-prerequisites.sh --json`** — the launchers, whose branch is cut later
  by the workflow. `TASK_ID` empty means the session sits on a long-lived branch
  and `BRANCH` is the base; `TASK_ID` present means it sits on a task branch
  already and `BASE_BRANCH` is.

## The question

```json
AskUserQuestion({
  "questions": [{
    "question": "Which branch should <what is being cut> fork from?",
    "header": "Base branch",
    "options": [
      { "label": "<the resolved ref> (Recommended)",
        "description": "Resolved from the repository: the ref HEAD forked from most recently" },
      { "label": "<candidate>",
        "description": "Any of develop / next / main that exists and is not the default" }
    ],
    "multiSelect": false
  }]
})
```

The resolved ref is the first option; after it, whichever of `develop`, `next`
and `main` exist in the repository and are not the default. Any other ref
arrives through "Other". **End the turn on the tool call** —
`turn-discipline.md` is the rule, and this question is no exception for being a
short one.

## What the answer binds

The answer is the ref, used verbatim and once: `--base <ref>` on the
`sdd-start.sh --create` call, or `baseBranch` in the `Workflow` arguments.
Nothing downstream resolves it a second time — a second resolution that
disagreed would send the branch off a fork point nobody chose, which is the
defect this question exists to prevent.

## When it is not asked

- **The branch already exists** (`BRANCH_EXISTS: true`): the fork point was
  decided when the branch was born, and asking again would offer a choice that
  no longer has an effect. Say the task is being resumed instead.
- **`quick`**: it resolves and goes. Ceremony proportional to the change is what
  that command is for, and a fix of at most three files is not where a wrong
  base hides.
- **Inside a fan-out**: `multi-sdd` asks once for the whole set, in phase A. The
  fork point is a project fact, its overlap warning only means anything while
  the tasks share one base, and a question per run would put the human parts
  back in the middle of the fan-out.

## In a worktree

Resolve and confirm **in the main checkout**, then enter the worktree and pass
the answer as `--base`. A fresh worktree forks from the remote default, so its
own HEAD is not a fork point worth resolving — that is exactly how a project
whose work targets `next` ends up with a branch cut from `main`.
