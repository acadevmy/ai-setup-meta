---
description: "Runs the entire Spec-Driven Development (SDD) flow end-to-end in autonomous mode. Replaces every human checkpoint (discovery, spec/plan approval, methodology choice, final OK, MR opening) with AI agents. Invoking this skill means activating auto-mode — there are no flags."
---


# /project:start-task

Runs the entire Spec-Driven Development (SDD) flow for a ClickUp task in
**fully autonomous** mode: from task selection to opening the MR/PR, with no
`AskUserQuestion` directed at the human.

**Invoking `start-task` is equivalent to activating auto-mode**: it is not a flag, it is the
intrinsic behavior of the skill. Interactive mode remains available through the
`sdd` orchestrator (which is not modified).

**Usage**: `/project:start-task [TASK_ID]`
- With `TASK_ID` (e.g. `DE-123`): processes that task
- Without arguments: takes the next task in `SPRINT` from the `CLICKUP_SETUP_LIST_ID` list

## CRITICAL — Behavior in auto-mode

- **No `AskUserQuestion` may be invoked**: every decision goes through an agent
  (`sdd-discovery-responder`, `sdd-approver`, `sdd-methodology-picker`) or a documented
  deterministic rule
- **The silent Stop hook does not apply**: in auto-mode there is no human wait, so
  the "STOP after AskUserQuestion" pattern is not expected. If the Stop hook reports
  incomplete work, actually complete the work or perform the bail-out
- **Loop bounds**: every loop has a maximum number of iterations (see table below).
  Exceeding the bound without convergence → bail-out
- **SDD skills are not modifiable**: this skill orchestrates the `sdd-spec`, `sdd-dev`,
  `verify`, `simplify`, `review` skills but **cannot modify their internal behavior**.
  The interactive skills (`sdd-discovery`, `sdd-plan`) **must NOT be invoked**: their outputs
  are produced by the dedicated agents of this skill

| Loop | Maximum bound |
|---|---|
| Discovery questions (Q/A between interviewer and responder) | 12 |
| Spec review iterations (`sdd-approver` on `MODE: spec`) | 3 |
| Plan review iterations (`sdd-approver` on `MODE: plan`) | 3 |
| Re-entries from `verify` fail | 3 |

## Complete flow

### 1. Task selection

**If `$ARGUMENTS` contains a TASK_ID**:
- Launch the `clickup` agent with:
  - INTENT: `read`
  - PARAMS: `task_id: <TASK_ID>`
- If the agent returns STATUS: error → bail-out with reason

**If `$ARGUMENTS` is empty**:
- Read `CLICKUP_SETUP_LIST_ID` from the `.env` file in the project root
- If the variable is not configured → bail-out (`Configure CLICKUP_SETUP_LIST_ID in .env`)
- Launch the `clickup` agent with:
  - INTENT: `filter`
  - PARAMS: `list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`
- If the agent returns STATUS: error → bail-out with reason
- If the list is empty → clean stop ("No task in SPRINT")
- Sort the results by `priority` (1=urgent ... 4=low) and take the **first** one
- Launch the `clickup` agent with INTENT: `read` to retrieve the full content of the chosen task

From the output extract: `custom_id`, `name`, `description`, `priority`, `task_id`, `url`.

### 2. Branch creation

Determine the type from the task title/description:
- Feature → `feat/`
- Bug → `fix/`
- Maintenance → `chore/`

**Base branch**: use the repository default (in order: `main`, `master`, `develop` —
take the first that exists). No `AskUserQuestion`.

```bash
git checkout <base-branch>
git pull origin <base-branch>
git checkout -b <type>/<customId>-<short-description>
```

Example: `feat/DE-123-add-user-auth`.

If branch creation fails → bail-out.

### 3. Task status update

Launch the `clickup` agent with:
- INTENT: `update`
- PARAMS: `task_id: <task_id>, status: IN PROGRESS`

### 4. Autonomous two-agent discovery

Replaces the interactive interview of `sdd-discovery`. **Do not invoke `/project:sdd-discovery`**:
that skill opens `AskUserQuestion` and is incompatible with auto-mode.

Run a loop between **two roles internal to this skill**:

**Role A — Interviewer** (handled by the skill, not as a separate agent)
- Adopt the `sdd-discovery` framework: 4 phases `Core Value` → `Happy Path` → `Edge Cases` → `Constraints`
- For each phase, formulate one question at a time with 2-4 pre-formulated options (closed-first)
- At most 10-12 questions overall (loop bound)

**Role B — Responder** (delegated to the `sdd-discovery-responder` agent)
- For each question, launch the `sdd-discovery-responder` agent with:
  - `TASK_CONTEXT`: fields extracted at Step 1
  - `PHASE`: current phase
  - `QUESTION`: question formulated by the interviewer
  - `OPTIONS`: pre-formulated options (including "To be defined" when it makes sense)
  - `HISTORY`: all the Q/A already exchanged
- The agent returns a `---DISCOVERY-ANSWER---` block with `CHOICE`, `ANSWER`,
  `RATIONALE`, `GRAY_AREA`

**Convergence**:
- End when all 4 phases are covered with unambiguous answers **or**
  when the bound is reached (12 Q/A)
- If phases remain uncovered at the bound → bail-out

**Output**: rebuild the Discovery Summary in the format identical to that of
`sdd-discovery` (sections `Core Value`, `Happy Path`, `Edge Cases and Error Handling`,
`Constraints and Preferences`, `Existing Components to Reuse`, `Gray Areas`) and keep it
in context for the next step.

### 5. Spec generation

Invoke `/project:sdd-spec` passing: `TASK_CONTEXT` (custom_id, name, description, url,
branch) + the Discovery Summary produced at Step 4.

The `sdd-spec` skill is not interactive and produces `.specs/<customId>-<slug>.md` with
status `draft`.

### 6. Spec approval by agent (bounded loop)

Replaces `sdd-plan` (interactive, forbidden in auto-mode).

Initialize `ITERATION = 1`, `MAX_ITERATIONS = 3`.

Loop:
1. Launch the `sdd-approver` agent with:
   - `SPEC_PATH`: path of the generated spec
   - `MODE`: `spec`
   - `DISCOVERY_SUMMARY`: the summary produced at Step 4
   - `ITERATION`, `MAX_ITERATIONS`
2. If `STATUS: approved` → exit the loop, update the spec frontmatter:
   - `Status: draft` → `Status: approved`
   - `Approved: <YYYY-MM-DD>`
3. If `STATUS: changes-requested`:
   - Apply the `CHANGES_REQUESTED` directly to the spec file (Edit/Write)
   - `ITERATION += 1`
   - If `ITERATION > MAX_ITERATIONS` → bail-out with the list of remaining violations
   - Otherwise go back to point 1
4. If `STATUS: error` → bail-out

### 7. Plan approval by agent (bounded loop)

Same mechanism as Step 6 but with `MODE: plan`. Bound: 3 iterations.

At the end, the spec remains in `approved` status.

### 8. Methodology choice by agent

Launch the `sdd-methodology-picker` agent with:
- `SPEC_PATH`: path of the approved spec
- `TASK_CONTEXT`: task fields

The agent returns `METHODOLOGY` (`tdd` | `bdd` | `none`) and `RATIONALE`. Track the
choice in the skill log (do not modify the spec — the methodology is passed to `sdd-dev`).

### 9. Development

Invoke `/project:sdd-dev` passing:
- `SPEC_REF`: path of the approved spec
- `METHODOLOGY`: the methodology chosen by the agent at Step 8

`sdd-dev` executes the plan. It requires no human input in auto-mode (the skill already has
the explicit methodology and the approved spec).

### 10. Automatic quality gates

Run them in order:

1. **simplify** — invoke the `simplify` skill (if present). In auto-mode, automatically
   accept the proposed changes and commit them as
   `refactor(<scope>): simplify implementation`
2. **verify** — invoke `/project:verify`
   - If `STATUS: pass` → proceed
   - If `STATUS: pass-with-warnings` → proceed, logging the warnings
   - If `STATUS: fail` → re-enter at Step 9 (development) with the detail of the missing
     requirements. Bound: 3 total re-entries. Exceeding the bound → bail-out
3. **review** — invoke `/project:review`
   - If `STATUS: pass` or `pass-with-warnings` → proceed
   - If `STATUS: fail` with auto-resolvable violations (e.g. `any` replaceable with a
     concrete type evident from the spec) → apply them and re-invoke `review` (max 1 re-entry)
   - If `STATUS: fail` with non-auto-resolvable violations → bail-out

### 11. Push + opening the MR/PR

Push the branch:
```bash
git push -u origin <branch-name>
```

Invoke the active VCS-ops skill (`github-ops` for GitHub remotes, `gitlab-ops` for GitLab
remotes — self-identify). Title and body:

- **Title**: Conventional Commits with customId
  - e.g. `feat(auth): add refresh token rotation [DE-123]`
- **Body**: includes **What / Why / How to test** sections + link to the ClickUp task + link
  to the spec. On GitLab it follows the `.gitlab/merge_request_templates/Default.md` template
  when present (see `gitlab-ops`)

No `AskUserQuestion` before opening: authorization is implicit in the invocation of
`start-task`.

### 12. Closure

1. Launch the `clickup` agent with:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: CODE REVIEW`
   - Fallback: if `CODE REVIEW` does not exist in the list, use `IN REVIEW`
2. Update the spec frontmatter: `Status: approved` → `Status: implemented`

## Bail-out

Triggered when a step fails or a loop does not converge within the bound.

Procedure:
1. **Do not** delete the local branch (useful for human debugging)
2. Launch the `clickup` agent with:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: BLOCKED`
3. Launch the `clickup` agent with:
   - INTENT: `comment`
   - PARAMS: `task_id: <task_id>, text: "⛔ Pipeline start-task (auto-mode) bloccata.\n\n**Step fallito**: <numero>\n**Motivo**: <descrizione>\n**Branch locale**: <branch>\n\nAzioni suggerite:\n- <suggerimento>"`
4. Exit with an error reporting `task_id`, `custom_id`, branch, reason

Recovery (human side): once the blocker is resolved, move the task back to `SPRINT`. A new
invocation of `start-task` will pick the task up again.

## Expected output

- Branch created with the customId in the name
- Spec in `.specs/` with status `implemented`
- Code implemented following the approved spec
- Code optimized (simplify), verified against the spec (verify), CONSTITUTION-compliant (review)
- `REGISTRY.md` updated with the new entries
- ClickUp task: `SPRINT` → `IN PROGRESS` → `CODE REVIEW`
- MR/PR opened (GitHub or GitLab depending on the provider) with references to the task and spec
- No `AskUserQuestion` invoked during the entire flow

## Constraints — summary

- **DO NOT modify** the SDD skills (`sdd`, `sdd-discovery`, `sdd-spec`, `sdd-plan`,
  `sdd-dev`, `verify`, `simplify`, `review`, `tdd`, `bdd`)
- **DO NOT invoke** in auto-mode the interactive skills (`sdd-discovery`, `sdd-plan`):
  their outputs are produced respectively by the discovery loop of Step 4 and
  by the `sdd-approver` agent
- Auto-mode is the default and only behavior of `start-task`. Interactive mode
  is covered by `/project:sdd` (unchanged)

## Notes on the variants (Claude / Codex / Gemini)

The `sdd-discovery-responder`, `sdd-approver` and `sdd-methodology-picker` agents require
support for isolated sub-agents. **This skill works fully in Claude Code**, which
supports sub-agents natively.

For variants that do not support isolated sub-agents (e.g. Codex / Gemini at the time of
generation), the agents are run as structured prompts in the same context:
the output format `---DISCOVERY-ANSWER---`, `---APPROVAL-RESULT---`,
`---METHODOLOGY-CHOICE---` stays the same, and the dedicated builders (`build-codex.sh`,
`build-gemini.sh`) decide how to distribute these agents. Check the specific limits
in the variant README.
