# Spec: Shorten sdd discovery and stop re-asking the stop point on resume [DE-17076]

> Status: implemented
> Task: https://app.clickup.com/t/869fb17et
> Branch: feat(sdd)/DE-17076_shorten-sdd-discovery-and-stop-re-asking
> Created: 2026-10-07
> Approved: 2026-10-07

## Context

Before any code, `sdd` costs about 13 exchanges: task selection, fork point +
stop point, ~10 discovery questions asked one at a time, spec approval. Most of
the discovery questions re-ask what the ClickUp task already says. spec-kit's
`clarify` caps at 5 questions ordered by impact, each with a Recommended
option; feature-dev asks its clarifying questions as one list. Claude Code's
own best practice: "don't ask obvious questions, dig into the hard parts".

The stop point (decision of 2026-10-02) stays a launch question, but nothing
records the answer, so every resume asks it again — `stop-point.md`: "Nothing
writes it down: a resumed run asks again". And `sdd/SKILL.md` promises "two
stops" while discovery alone is ten.

Discovery decisions (2026-10-07): the stop point is saved next to the task
clock; on resume it is reused silently and only an explicit `--stop` argument
changes it; the grouping rule is changed in the shared `turn-discipline.md`,
not as a discovery exception; the interview is one call plus at most one
follow-up, five questions in all.

## Requirements

- REQ-1: Discovery asks about the gaps only — what the task, `REGISTRY.md` and
  the code do not already answer — in one `AskUserQuestion` call of at most 4
  related questions, each with a Recommended option, plus at most one
  follow-up call. Hard cap: 5 questions in total.
- REQ-2: The first question of the first call carries the option
  "Requirements clear: go to spec", which ends the interview in one click.
- REQ-3: `turn-discipline.md` allows one call holding up to 4 related
  questions, which is still one stop. A list of questions in plain text stays
  forbidden.
- REQ-4: The stop point chosen at launch is persisted where it survives
  `/clear`, and a resumed run reads it back instead of asking.
- REQ-5: `/dev-setup:sdd <id> --stop <point>` replaces a saved stop point; with
  no saved value (a branch cut by an older version), the resume asks as today.
- REQ-6: `sdd/SKILL.md`, `docs/onboarding.md` and `docs/developer-guide.md`
  describe the real number of stops.
- REQ-7: The static checks pass: every `SKILL.md` within 500 words, check 16,
  checks 14–15 on the docs, shellcheck, `test-plugin-scripts.sh`.

## Technical decisions

- **`sdd-start.sh --stop <point>`, not a new script.** `sdd-start.sh` is
  already the call that tells a fresh run from a resume (`BRANCH_EXISTS`), so
  the same call returns the saved value as `STOP_POINT` — the resume needs no
  extra call. Values: `spec | development | review | commit | push |
  merge-request`; anything else exits 1 listing them. `--stop` without
  `--task` exits 1: the value is per task.
- **Written on `--create` only.** The report-only call stays read-only, as its
  contract says. `--create --stop X` writes on a new branch and on an existing
  one alike — the latter is the override of REQ-5.
- **Stored at `$(git rev-parse --git-common-dir)/dev-setup/stop-point/<TASK>`**,
  the clock's sibling: shared by a worktree and its checkout (the
  `--worktree` flow runs `--create` inside the worktree), outside the working
  tree so `git add -A` never commits it, untouched by `/clear`. The task id is
  already validated as a plain identifier, so it is safe as a file name.
- **A write failure dies**, like the clock: a stop point the developer chose
  and the script silently lost would surface as a question on resume — the
  exact defect being fixed.
- **Discovery pre-fills, then asks.** Before the call it drafts the Discovery
  Summary from the task, `REGISTRY.md` and the code, and asks only what the
  draft leaves blank or guesses. The four phases stay as the coverage
  checklist, no longer as an order of questions.
- **The real stop count of `sdd`** becomes: launch (fork point + stop point,
  one call; none on a resume with a saved stop point and an existing branch),
  discovery (one call, at most two), spec approval. Conditional: task
  selection when no id is given, the backlog gate.
- `multi-sdd`'s phase A keeps its own "one question at a time": it is stricter
  than the shared rule, which a local rule may be. Out of scope.

## Impact

- **Files to create**: none
- **Files to modify**:
  - `templates/dev-setup/.claude/scripts/sdd-start.sh` — `--stop`, `STOP_POINT`
  - `scripts/test-plugin-scripts.sh` — the `--stop` cases, doc asserts
  - `templates/dev-setup/.claude/reference/turn-discipline.md`
  - `templates/dev-setup/.claude/skills/sdd-discovery/SKILL.md`
  - `templates/dev-setup/.claude/skills/sdd-discovery/reference/question-bank.md`
  - `templates/dev-setup/.claude/skills/sdd/SKILL.md`
  - `templates/dev-setup/.claude/skills/sdd/reference/intake.md`
  - `templates/dev-setup/.claude/skills/sdd/reference/stop-point.md`
  - `docs/onboarding.md`, `docs/developer-guide.md`
  - `AGENTS.md` — the `sdd-start.sh` row, the DE-16480 stop count, version bump
  - `templates/dev-setup/CHANGELOG.md` if the template keeps one
  - `dist/dev-setup/**` — regenerated by `scripts/build-plugin.sh dev-setup`
- **Dependencies**: none

## Implementation plan

1. Tests first — in `test-plugin-scripts.sh`, the `sdd-start.sh` section:
   `--create --stop push` writes and a report-only call on the same task
   returns `STOP_POINT: push`; a task with nothing saved returns `""`; an
   invalid value exits 1; `--stop` without `--task` exits 1; `--create --stop
   commit` on the existing branch overwrites; the report-only call with
   `--stop` writes nothing; the file sits under the common git dir.
2. `sdd-start.sh` — parse `--stop`, validate, read `STOP_POINT`, write it on
   `--create`; update the header (usage, keys). Run the suite and shellcheck.
3. `turn-discipline.md` — "One question at a time" becomes "One call at a
   time": up to 4 related questions in one `AskUserQuestion` call, never a
   plain-text list.
4. `question-bank.md` — pre-fill first; the gap-only call; the "Requirements
   clear: go to spec" option; the 5-question cap and one follow-up replacing
   the 10–12 soft cap; a worked example of a grouped call; the four phases as
   a coverage checklist.
5. `sdd-discovery/SKILL.md` — step 4 and Expected output aligned to the new
   shape, within 500 words.
6. `sdd/reference/stop-point.md` and `intake.md` — the answer is saved through
   `--create --stop`; on resume `STOP_POINT` non-empty → no question, shown in
   the brief; `--stop` argument → passed through; empty → ask as today. Drop
   "Nothing writes it down".
7. `sdd/SKILL.md` — usage gains `--stop <point>`; the stops paragraph states
   the real count.
8. Docs — `onboarding.md` (the `sdd` paragraph), `developer-guide.md`
   (the stop point section and the resume line), `AGENTS.md`.
9. `bash scripts/build-plugin.sh dev-setup`, then `validate-plugin.sh
   --strict`, `test-plugin-scripts.sh`, shellcheck.

## Test strategy

- Test 1 (REQ-4): `--create --stop push` then a report-only call → `STOP_POINT`
  is `push`; the file exists under `git rev-parse --git-common-dir`.
- Test 2 (REQ-4): a task with nothing saved → `STOP_POINT` is `""`.
- Test 3 (REQ-5): `--create --stop commit` on the existing branch → `commit`.
- Test 4 (REQ-4): report-only with `--stop` → nothing written.
- Test 5 (REQ-4): an invalid value, and `--stop` without `--task` → exit 1.
- Test 6 (REQ-1, REQ-2): `question-bank.md` carries "Requirements clear: go to
  spec" and no longer "10–12"; `sdd-discovery/SKILL.md` no longer says "one
  question at a time".
- Test 7 (REQ-3): `turn-discipline.md` states the 4-question bound.
- Test 8 (REQ-6): `sdd/SKILL.md` no longer says "Two stops";
  `stop-point.md` no longer says "a resumed run asks again".
- Test 9 (REQ-7): `validate-plugin.sh --strict` and the CI jobs, locally.

The "≤3 exchanges on a well-written task" criterion is behavioural: it is
checked by running `sdd` on a task, and measured properly by the eval suite
(DE-17063).

## Notes

- Risk: fewer questions, more gaps. The safety nets stay the spec approval in
  `sdd-plan` and, for `auto-sdd`, the three reviewers.
- `sdd-start.sh` resolved `origin/main` as the base while HEAD sat exactly on
  `next` (this very run). A separate defect, worth its own ticket — not fixed
  here.
