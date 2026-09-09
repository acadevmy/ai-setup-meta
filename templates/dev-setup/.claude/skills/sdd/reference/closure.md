# Closure — gates, one commit, merge request

Step 9 of the flow: from finished code to an open merge request and a task in
review. The ClickUp calls follow
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

The order matters and it is not the obvious one: **the gates run before the
commit, and there is one commit.** Two reasons. The commit hook is the gate that
runs `LINT_CMD`, `TYPECHECK_CMD` and `TEST_CMD`, and it skips when nothing is
staged — so staging first is what makes it fire at all. And a task that ends in
one commit is a task whose diff a reviewer can read: the three bookkeeping
commits this flow used to mandate (`refactor: simplify`, `docs(registry)`,
`docs(spec): track review outcome`) carried process, not work.

## Index

- [1. Stage](#1-stage)
- [2. Simplify](#2-simplify)
- [3. Verify](#3-verify)
- [4. Review](#4-review)
- [5. Summary](#5-summary)
- [6. Commit](#6-commit)
- [7. Push](#7-push)
- [8. Open the merge request](#8-open-the-merge-request)
- [9. Move the task](#9-move-the-task)

## 1. Stage

```bash
git add -A
```

Stage the branch's own work, the spec included. New files have to be in the
index or the next three steps cannot see them: an untracked file has no diff
against the fork point.

## 2. Simplify

Run the `simplify` skill over the staged change: reuse what exists, improve
quality and efficiency, fix what it finds. **This is the only place `simplify`
runs in the flow** — `sdd-dev` no longer calls it. Whatever it changes is part
of the change, not a commit of its own.

## 3. Verify

Invoke the `verify` skill — it checks the change against the spec: every `REQ-N`
implemented, every planned test present, the Impact list respected, the
technical decisions followed.

- **fail** → show what is missing and go back to development;
- **pass-with-warnings** → show the warnings and ask the developer to confirm;
- **pass** → go on to review.

## 4. Review

Invoke the `review` skill: rule compliance through the review agent, code
quality, and the `REGISTRY.md` entries the change earns. It writes those entries
into the working tree and commits nothing — they ride the commit below.

## 5. Summary

```
Implementation summary: DE-123 — Task title

Spec: .specs/DE-123-<slug>.md
Files created: <list>
Files modified: <list>
Tests: <passing/failing>
Verify: <pass/pass-with-warnings/fail>
Review: <result>
REGISTRY: <updated/unchanged>
```

## 6. Commit

Set the spec's status from `approved` to `implemented` in
`.specs/<customId>-<slug>.md`, re-stage (`git add -A` — steps 2 and 4 changed
files), and commit once. Conventional Commits, with the custom id:

```
feat(auth): add refresh token rotation [DE-123]
```

The commit hook runs the project's lint, type check and test commands here, or
delegates to the project's own hook manager when it has one. A denial is the
gate working: read the output it returns, fix what failed, commit again. Never
`--no-verify` — it is a deny rule, not a suggestion.

## 7. Push

```bash
git push -u origin <branch-name>
```

## 8. Open the merge request

Invoke the `vcs-ops` skill. It reads `origin` itself and loads its GitHub or
GitLab reference accordingly, so there is nothing to pick here. Target the
**short name of the base branch** reported at intake (`origin/next` → `next`).

- **Title** — Conventional Commits with the custom id, e.g.
  `feat(auth): add refresh token rotation [DE-123]`.
- **Body** — What / Why / How to test, plus the link to the task and the link to
  the spec. On GitLab the body comes from
  `.gitlab/merge_request_templates/Default.md` when the repository has one; the
  skill's GitLab reference explains when and how.

The `ask` rule on `gh pr create` / `glab mr create` is the developer's last
checkpoint, and it is a permission rule — do not ask for the same confirmation
in chat first, and do not work around a refusal. Declined means declined: report
it and leave the branch pushed.

## 9. Move the task

`INTENT: update`, `PARAMS: task_id: <task_id>, status: CODE REVIEW` — and
`IN REVIEW` if the list does not have `CODE REVIEW`.
