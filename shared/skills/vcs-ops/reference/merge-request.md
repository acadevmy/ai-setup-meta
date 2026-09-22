# The merge request: title, body, test steps

Same on both hosts. The CLI invocations are in `github.md` and `gitlab.md`.

## Index

- [The title](#the-title)
- [The body is the repository's template](#the-body-is-the-repositorys-template)
- [The test section](#the-test-section)
- [When the repository has no template](#when-the-repository-has-no-template)

## The title

```
<Type>: <what was done> <TASK-ID>
```

- `Feat: Add refresh token rotation DE-123`
- `Fix: Reject an expired refresh token DE-456`
- `Chore: Update the Flutter toolchain`

`<Type>` is one word, capitalised, followed by a colon: `Feat`, `Fix`, `Chore`,
`Perf`, `Docs`, `Refactor`. What follows says what the branch did. The task id
closes the title and is dropped when the work has no ticket.

**The commits keep Conventional Commits** (`feat(auth): add refresh token
rotation [DE-123]`) — commitlint checks them and semantic-release reads them.
The two conventions do not collide, one naming the merge request and the other
the commits, with one exception: on a repository that **squash-merges** into a
semantic-release branch, the squash subject *is* a commit. Put the conventional
form there, or the release computation skips the change.

## The body is the repository's template

| Host | Template |
|---|---|
| GitHub | `.github/PULL_REQUEST_TEMPLATE.md` |
| GitLab | `.gitlab/merge_request_templates/Default.md` |

Read the file, fill it, pass the filled body — `--body-file` on `gh`,
`--description-file` on `glab`. Neither CLI fills a template for you:
`gh pr create` applies it only when it opens an editor, and
`glab mr create --template` inserts it **unfilled**. A merge request that
arrives with the template's own placeholders still in it is the failure this
page exists to prevent.

Filling it means:

- every heading answered, in the language the template is written in — that
  language governs the title too;
- the HTML comments left where they are (they are instructions to the author and
  do not render); the placeholder lines replaced;
- a checklist item ticked only when it is true. An unticked box is information;
  a box ticked because it was there is a claim a reviewer will act on;
- a section with nothing to say gets one line saying so — `No screenshot: no UI
  change` — never silence.

## The test section

The one section that is not a summary of the diff. It is the procedure a
reviewer follows to see the change work, written for someone who has not read
the branch.

- **The commands**, in the order they run: install, migrate, start, and the
  exact test invocation for what changed (`npm test -- src/auth/login.spec.ts`),
  not a bare `npm test`.
- **The route**, spelled out: the URL or deep link to open
  (`http://localhost:3000/auth/login`), what to type or click there, and what
  must appear. A change with no UI names the endpoint and the call that reaches
  it (`curl -X POST localhost:3000/auth/refresh -d '{"token":"…"}'`).
- **The cases**, one checkbox each, the one that used to fail included.

Anything a reviewer would otherwise have to guess — a seeded user, a feature
flag, a build that has to run first — is one of the steps, not an assumption.

## When the repository has no template

No forge, or a project the setup never wrote one into. Use this body:

```markdown
## What changed
<description of changes>

## Why
<motivation>

## How to test
- [ ] <command or route, and the expected result>

## Checklist
- [ ] No secrets or API keys included
- [ ] CHANGELOG updated
- [ ] project rules respected

## Task
- [DE-XXX](link to task)
```

The test section's rules hold here too: this body is shorter, not vaguer.
