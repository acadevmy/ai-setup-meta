---
name: quick
description: Fast path from a small change to a merge request — branch, edit, commit behind the quality gate, merge request. Use when the work is a fix or chore touching at most three files and adding no new component, dependency or public interface. Anything larger goes through `sdd`.
effort: medium
user-invocable: true
disable-model-invocation: true
allowed-tools: AskUserQuestion
---

# Quick

Branch, change, commit, merge request. **No discovery, no spec, no registry
pass**: the ceremony of `sdd` costs more than a one-line fix is worth.

**Usage**: `/dev-setup:quick [TASK_ID | description] [--worktree]`. A task id
(e.g. `DE-123`) is read from the board; a plain description works without one.

## The bar

**At most three files**, and **no new component, dependency or public
interface**. Everything else is `sdd`, whose spec is what a reviewer reads the
diff against.

Check it against the task before you start, and against reality while you work.
If the change crosses the bar mid-flight, let the developer choose — do not
quietly build a feature without a spec, and do not abandon a nearly-done change:

```json
AskUserQuestion({
  "questions": [{
    "question": "This is now <N> files and adds <what>. How do you want to proceed?",
    "header": "Route",
    "options": [
      { "label": "Stay in quick", "description": "Finish here; the merge request carries the reasoning." },
      { "label": "Switch to sdd", "description": "Keep the branch, write the spec, run the full flow." }
    ],
    "multiSelect": false
  }]
})
```

End the turn on that call —
`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md` is the rule.

## The flow

1. **The change.** With a task id, read it through the `clickup` agent
   (`INTENT: read`) per
   `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`, and move it to
   `IN PROGRESS`. Without one, the description in `$ARGUMENTS` is the whole
   input — do not ask for a ticket.

2. **The branch.**

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" \
     --type <fix|chore> --title "<what changes>" [--task <custom_id>] --create --json
   ```

   It resolves `BASE_BRANCH` from the repository — never a hard-coded `main`.
   With `--worktree`, force the fork point with `--base <ref>`
   (`${CLAUDE_PLUGIN_ROOT}/reference/worktree.md`).

3. **The change itself.** The path-scoped rules load on the files you open.
   Run the project's test and lint commands on what you touched.

4. **Commit.** One Conventional Commit, with the custom id when there is one:
   `fix(auth): reject an expired refresh token [DE-123]`. The commit hook runs
   lint, type check and tests, and a denial carries the real output. Fix, commit
   again; `--no-verify` is a deny rule.

5. **Merge request.** `git push -u origin <branch>`, then invoke `vcs-ops`
   against the short name of `BASE_BRANCH`. The `ask` rule on
   `gh pr create` / `glab mr create` is the checkpoint: do not ask for the same
   confirmation in chat first.

6. **The board.** With a task id: `INTENT: update`, status `CODE REVIEW`.

## Expected output

- a branch, one commit, one merge request linking the task when there is one;
- four turns for a one-line fix: branch, change, commit, merge request. Skip the
  preamble and the plan — that is the whole point of this command.
