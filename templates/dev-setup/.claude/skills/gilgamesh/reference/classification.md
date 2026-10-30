# Classifying the work

Three independent questions. A fix can be large and a feature small; a release
is a way of packaging work, not "a complex feature". There are no thresholds:
the skill proposes, with the reason, and the developer decides.

## 1. Type — what changes

| Type | When | Signals |
|---|---|---|
| **fix** | existing behaviour is wrong and goes back to what was expected | "does not work", "should", a reproducible bug |
| **feat** | the system does something it did not do before | a new screen, endpoint or business rule |
| **chore** | nothing a user sees changes | dependencies, refactoring, tooling, CI, docs |

A fix that needs new behaviour is a feat when the user notices the difference.
The type is `sdd-start.sh`'s `--type`: `docs`, `refactor`, `perf` and `test`
are also accepted when they fit better than `chore`.

## 2. Packaging — how many branches

| Packaging | When |
|---|---|
| **single branch** | the work can be reviewed and released in one go |
| **release branch** | several pieces that ship together but are reviewed apart: each gets its own branch, with its merge request into the release branch |

Signals of a release: pieces that would leave the product inconsistent on
their own, migrations to coordinate, changes that break compatibility between
apps or services, several people or agents on one goal, a discovery that does
not close in two calls.

## 3. Destination — where it lands

| Destination | When | Fork point |
|---|---|---|
| **development** | the normal case | the resolved default |
| **hotfix** | a production problem that cannot wait for the next release | the production ref — offer it first in the fork-point question |

A hotfix is always a fix on a single branch. Remind the developer that it has
to reach the development branch after the merge, when the project works that
way.

## The question

One `AskUserQuestion` call holds this question and the fork point. Options:
the proposal first, marked "(Recommended)", then at most two plausible
alternatives. Each description states the reason in one line.

```
Classification: feat · single branch · development
  — adds date filtering, which does not exist; one merge request, nothing to coordinate
```

## A release's pieces

A release spec adds this section after `## Implementation plan`:

```markdown
## Pieces
| # | Piece | Branch | Depends on |
|---|---|---|---|
| 1 | <what it delivers> | <type>/<slug>, cut from the release branch | — |
```

After the hand-off, the developer can open the first piece without dependencies
— a new run of `gilgamesh`, with the release spec as context, so its discovery
starts from what the release already decided.
