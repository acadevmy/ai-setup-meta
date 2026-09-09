# The autonomous flow, step by step

Every step of `auto-sdd`, and the bail-out that ends a run that cannot finish.
The ClickUp calls follow
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

## Index

- [1. Task selection](#1-task-selection)
- [2. Branch creation](#2-branch-creation)
- [3. Task status](#3-task-status)
- [4. Two-agent discovery](#4-two-agent-discovery)
- [5. Spec generation](#5-spec-generation)
- [6. Spec approval](#6-spec-approval)
- [7. Plan approval](#7-plan-approval)
- [8. Methodology](#8-methodology)
- [9. Development](#9-development)
- [10. The quality gates](#10-the-quality-gates)
- [11. Push and merge request](#11-push-and-merge-request)
- [12. Closure](#12-closure)
- [Bail-out](#bail-out)

## 1. Task selection

**With a task id in `$ARGUMENTS`**: read it (`INTENT: read`,
`PARAMS: task_id: <TASK_ID>`). On `STATUS: error` → bail out with the reason.

**Without one**: resolve `CLICKUP_SETUP_LIST_ID` as the contract describes. If it
is not configured → bail out (`Configure CLICKUP_SETUP_LIST_ID`). Then
`INTENT: filter`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`; an
error → bail out; an empty list → clean stop ("No task in SPRINT"). Sort the
results by `priority` (1 = urgent … 4 = low), take the **first**, and read it in
full (`INTENT: read`).

From the output extract `custom_id`, `name`, `description`, `priority`,
`task_id`, `url`.

## 2. Branch creation

Determine the type from the task title and description: feature → `feat/`, bug
→ `fix/`, maintenance → `chore/`.

**Base branch**: use the repository default (in order: `main`, `master`,
`develop` — take the first that exists). No `AskUserQuestion`.

```bash
git checkout <base-branch>
git pull origin <base-branch>
git checkout -b <type>/<customId>-<short-description>
```

For example `feat/DE-123-add-user-auth`. If branch creation fails → bail out.

## 3. Task status

`INTENT: update`, `PARAMS: task_id: <task_id>, status: IN PROGRESS`.

## 4. Two-agent discovery

Replaces the interactive interview of `sdd-discovery`. **Do not invoke that
skill**: it opens `AskUserQuestion` and is incompatible with auto-mode.

Run a loop between two roles:

**Role A — Interviewer** (handled by this skill, not a separate agent)

- adopt the `sdd-discovery` framework: the four phases `Core Value` →
  `Happy Path` → `Edge Cases` → `Constraints`;
- for each phase, formulate one question at a time with 2–4 pre-compiled options
  (closed-first);
- at most 10–12 questions overall (the loop bound).

**Role B — Responder** (the `sdd-discovery-responder` agent)

For each question, launch the agent with:

- `TASK_CONTEXT`: the fields extracted at step 1
- `PHASE`: the current phase
- `QUESTION`: the interviewer's question
- `OPTIONS`: the pre-compiled options, including "To be defined" where it makes
  sense
- `HISTORY`: every question and answer so far

The agent returns a `---DISCOVERY-ANSWER---` block with `CHOICE`, `ANSWER`,
`RATIONALE` and `GRAY_AREA`.

**Convergence**: end when all four phases are covered with unambiguous answers,
or when the bound is reached (12 questions). Phases still uncovered at the bound
→ bail out.

**Output**: rebuild the Discovery Summary in the exact format `sdd-discovery`
produces (`Core Value`, `Happy Path`, `Edge Cases and Error Handling`,
`Constraints and Preferences`, `Existing Components to Reuse`, `Gray Areas`) and
keep it in context for the next step.

## 5. Spec generation

Invoke `sdd-spec` with `TASK_CONTEXT` (custom_id, name, description, url,
branch) and the Discovery Summary from step 4. It is not interactive, and it
produces `.specs/<customId>-<slug>.md` with status `draft`.

## 6. Spec approval

Replaces `sdd-plan` (interactive, forbidden here). Initialize `ITERATION = 1`,
`MAX_ITERATIONS = 3`, and loop:

1. launch the `sdd-approver` agent with `SPEC_PATH`, `MODE: spec`,
   `DISCOVERY_SUMMARY` (the step-4 output), `ITERATION` and `MAX_ITERATIONS`;
2. `STATUS: approved` → leave the loop and update the spec frontmatter:
   `Status: draft` → `Status: approved`, `Approved: <YYYY-MM-DD>`;
3. `STATUS: changes-requested` → apply the `CHANGES_REQUESTED` to the spec file
   directly (Edit/Write), increment `ITERATION`, and go back to point 1. Past
   `MAX_ITERATIONS` → bail out with the violations that are still standing;
4. `STATUS: error` → bail out.

## 7. Plan approval

The same mechanism with `MODE: plan`, bound 3 iterations. At the end the spec
stays in `approved` status.

## 8. Methodology

Launch the `sdd-methodology-picker` agent with `SPEC_PATH` (the approved spec)
and `TASK_CONTEXT`. It returns `METHODOLOGY` (`tdd` | `bdd` | `none`) and
`RATIONALE`. Record the choice in the run log — do not modify the spec: the
methodology is passed to `sdd-dev`.

## 9. Development

Invoke `sdd-dev` with `SPEC_REF` (the approved spec) and `METHODOLOGY` (the
choice from step 8). It needs no human input here: the methodology is explicit
and the spec is approved.

## 10. The quality gates

In order:

1. **simplify** — invoke the `simplify` skill, if present. Accept the proposed
   changes automatically and commit them as
   `refactor(<scope>): simplify implementation`.
2. **verify** — invoke the `verify` skill.
   - `pass` → carry on
   - `pass-with-warnings` → carry on, logging the warnings
   - `fail` → back to step 9 with the missing requirements spelled out. Bound: 3
     re-entries in total; past that → bail out.
3. **review** — invoke the `review` skill.
   - `pass` or `pass-with-warnings` → carry on
   - `fail` with auto-resolvable violations (an `any` replaceable with a
     concrete type the spec makes evident) → apply them and re-invoke `review`
     (at most one re-entry)
   - `fail` with violations that are not auto-resolvable → bail out.

## 11. Push and merge request

```bash
git push -u origin <branch-name>
```

Then invoke `vcs-ops`; it reads `origin` and loads the right host reference
itself.

- **Title** — Conventional Commits with the custom id, e.g.
  `feat(auth): add refresh token rotation [DE-123]`.
- **Body** — What / Why / How to test, plus the link to the ClickUp task and to
  the spec. On GitLab it follows `.gitlab/merge_request_templates/Default.md`
  when the repository has one.

No `AskUserQuestion` before opening it: authorization is implicit in the
invocation of `auto-sdd`. The project's `ask` rule on `gh pr create` /
`glab mr create` still applies — it is a permission rule, and it is the one
checkpoint this flow does not remove.

## 12. Closure

1. `INTENT: update`, `PARAMS: task_id: <task_id>, status: CODE REVIEW` — falling
   back to `IN REVIEW` when the list does not have it.
2. Update the spec frontmatter: `Status: approved` → `Status: implemented`.

## Bail-out

Fires when a step fails or a loop does not converge inside its bound.

1. **Do not** delete the local branch — it is the debugging material.
2. One `update` call carrying both the status and the note (the agent exposes no
   standalone comment intent):

   ```
   INTENT: update
   PARAMS: task_id: <task_id>, status: BLOCKED, comment: "Pipeline auto-sdd blocked.\n\n**Failed step**: <number>\n**Reason**: <description>\n**Local branch**: <branch>\n\nSuggested actions:\n- <suggestion>"
   ```

3. Exit with an error naming the `task_id`, the `custom_id`, the branch and the
   reason.

The bail-out can fire from step 1 onward, so the source status is `SPRINT`
(before step 3) or `IN PROGRESS` (after it) — both transitions to `BLOCKED` are
in the agent's transition table. Recovery is a human moving the task back to
`SPRINT` (`BLOCKED → SPRINT`, also valid); the next invocation of `auto-sdd`
picks it up again.
