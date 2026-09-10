---
name: quick
description: Fast path from a small change to a merge request — branch, edit, commit behind the quality gate, merge request. Use when the work is a fix or chore touching at most three files and adding no new component, dependency or public interface. Anything larger goes through `sdd`.
effort: medium
user-invocable: true
disable-model-invocation: true
---

# Quick

Branch, change, commit, merge request. **No discovery, no spec, no registry
pass** — that ceremony costs more than a one-line fix is worth.

**Usage**: `/dev-setup:quick [TASK_ID | description] [--worktree]`. A task id
(e.g. `DE-123`) is read from the board; a plain description works without one.

## The bar

**At most three files**, and **no new component, dependency or public
interface**. Everything else is `sdd`, whose spec is what a reviewer reads the
diff against.

Check it against the task first, and against reality while you work. If the
change crosses the bar mid-flight, say what it grew into and let the developer
choose with `AskUserQuestion`, header `Route`: **Stay in quick** (finish here,
the merge request carries the reasoning) or **Switch to sdd** (keep the branch,
write the spec). End the turn on that call
(`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`). Never quietly build a
feature without a spec, and never abandon a nearly-done change.

## The flow

1. **The change.** With a task id, read it through the `clickup` agent
   (`INTENT: read`, per
   `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`) and move it to
   `IN PROGRESS`. Without one, `$ARGUMENTS` is the whole input — do not ask for
   a ticket.

2. **The branch.** With `--worktree`, the order matters: read `BASE_BRANCH`
   from `check-prerequisites.sh` **in the main checkout**, enter the worktree
   named after the task, and only then run the call below, adding
   `--base <that ref>`. `${CLAUDE_PLUGIN_ROOT}/reference/worktree.md` names the
   tool that enters it, and covers the dependency install and the port.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" \
     --type <fix|chore> --title "<what changes>" [--task <custom_id>] --create --json
   ```

   It resolves `BASE_BRANCH` itself — never a hard-coded `main` — so `--base`
   is for the worktree case only.

3. **The change itself.** The path-scoped rules load on the files you open.
   Run the project's test and lint commands on what you touched.

4. **Commit.** One Conventional Commit, with the custom id when there is one:
   `fix(auth): reject an expired refresh token [DE-123]`. The commit hook runs
   lint, type check and tests; a denial carries the real output. Fix and commit
   again — `--no-verify` is a deny rule.

5. **Merge request.** `git push -u origin <branch>`, then invoke `vcs-ops`
   against the short name of `BASE_BRANCH`. The `ask` rule on
   `gh pr create` / `glab mr create` is the checkpoint — do not ask for the same
   confirmation in chat first.

6. **The board.** With a task id: `INTENT: update`, status `CODE REVIEW`.

## Expected output

- a branch, one commit, one merge request linking the task when there is one;
- four turns for a one-line fix. Skip the preamble and the plan — that is the
  whole point of this command.
