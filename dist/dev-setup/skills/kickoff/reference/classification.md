# Classifying the work

Two independent questions, and one check before them. A fix can be large and
a feature small. There are no thresholds: the skill proposes, with the reason,
and the developer decides.

## 1. Type — what changes

| Type | When | Signals |
|---|---|---|
| **fix** | existing behaviour is wrong and goes back to what was expected | "does not work", "should", a reproducible bug |
| **feat** | the system does something it did not do before | a new screen, endpoint or business rule |
| **chore** | nothing a user sees changes | dependencies, refactoring, tooling, CI, docs |

A fix that needs new behaviour is a feat when the user notices the difference.
The type is `sdd-start.sh`'s `--type`: `docs`, `refactor`, `perf` and `test`
are also accepted when they fit better than `chore`.

## One branch, or a story first

Kickoff opens **one** piece of work: one branch, one merge request. When the
discovery shows several pieces — ones that would leave the product
inconsistent on their own, migrations to coordinate, changes that break
compatibility between apps or services, several people or agents on one goal,
a discovery that does not close in two calls — it is an epic, and writing an
epic is `story`'s job. Say so in two lines, then stop on
`Next: /dev-setup:story <the idea>`: the epic and its stories land on the
board, and each story is built with `sdd`, or with `multi-sdd` when several
can run at once — each in a worktree `/dev-setup:parallel` prepares, with its
own ports and `.env`. Nothing is created here — no branch, no spec, no task.

**When the stories have to ship together** — a release branch, reviewed piece
by piece — say it in the same answer: the project cuts that branch by hand and
each story's run takes it as its fork point. It reaches the development branch
only through its own promotion merge request, after the project's acceptance,
merged by a person; the agent never merges it.

## 2. Destination — where it lands

| Destination | When | Fork point |
|---|---|---|
| **development** | the normal case | the resolved default |
| **hotfix** | a production problem that cannot wait for the next release | the production ref — offer it first in the fork-point question |

A hotfix is always a fix. Remind the developer that it has to reach the
development branch after the merge, when the project works that way.

## The question

One `AskUserQuestion` call holds this question and the fork point. Options:
the proposal first, marked "(Recommended)", then at most two plausible
alternatives. Each description states the reason in one line.

```
Classification: feat · development
  — adds date filtering, which does not exist; one merge request, nothing to coordinate
```
