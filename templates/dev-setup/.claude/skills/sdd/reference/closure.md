# Closure — commit, gates, MR, status

Step 10 of the flow: from finished code to an open merge request and a task in
review. The ClickUp calls follow
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`.

## Index

- [1. Commit](#1-commit)
- [2. Simplify](#2-simplify)
- [3. Verify](#3-verify)
- [4. Review](#4-review)
- [5. Summary](#5-summary)
- [6. Wait for the OK](#6-wait-for-the-ok)
- [7. Push](#7-push)
- [8. Open the merge request](#8-open-the-merge-request)
- [9. Move the task](#9-move-the-task)
- [10. Close the spec](#10-close-the-spec)

## 1. Commit

Conventional Commits, with the custom id:

```
feat(auth): add refresh token rotation [DE-123]
```

## 2. Simplify

Run the `simplify` skill over the modified code: reuse what exists, improve
quality and efficiency, fix what it finds. If it changed anything, commit it as
`refactor(<scope>): simplify implementation`.

## 3. Verify

Invoke the `verify` skill — it checks the diff against the spec: every `REQ-N`
implemented, every planned test present, the Impact list respected, the
technical decisions followed.

- **fail** → show what is missing and go back to development;
- **pass-with-warnings** → show the warnings and ask the developer to confirm;
- **pass** → go on to review.

## 4. Review

Invoke the `review` skill: rule compliance through the review agent, code
quality, and the `REGISTRY.md` entries the change earns.

## 5. Summary

```
Implementation summary: DE-123 — Task title

Spec: .specs/DE-123-<slug>.md
Methodology: <tdd/bdd/none>
Files created: <list>
Files modified: <list>
Tests: <passing/failing>
Verify: <pass/pass-with-warnings/fail>
Review: <result>
REGISTRY: <updated/unchanged>
```

## 6. Wait for the OK

The developer confirms the solution is complete and correct. If they ask for
changes, apply them and come back to step 1 of this file — a re-run of the gates
is cheaper than a review comment.

## 7. Push

```bash
git push -u origin <branch-name>
```

## 8. Open the merge request

Invoke the `vcs-ops` skill. It reads `origin` itself and loads its GitHub or
GitLab reference accordingly, so there is nothing to pick here.

- **Title** — Conventional Commits with the custom id, e.g.
  `feat(auth): add refresh token rotation [DE-123]`.
- **Body** — What / Why / How to test, plus the link to the task and the link to
  the spec. On GitLab the body comes from
  `.gitlab/merge_request_templates/Default.md` when the repository has one; the
  skill's GitLab reference explains when and how.

## 9. Move the task

`INTENT: update`, `PARAMS: task_id: <task_id>, status: CODE REVIEW` — and
`IN REVIEW` if the list does not have `CODE REVIEW`.

## 10. Close the spec

Change the spec's status from `approved` to `implemented` in
`.specs/<customId>-<slug>.md`.
