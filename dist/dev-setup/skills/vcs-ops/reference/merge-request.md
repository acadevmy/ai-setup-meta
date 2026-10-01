# The merge request: title, body, labels, test steps

Same on both hosts. The CLI invocations are in `github.md` and `gitlab.md`.

## Index

- [Where the shape comes from](#where-the-shape-comes-from)
- [The title](#the-title)
- [The body is the repository's template](#the-body-is-the-repositorys-template)
- [Short, not exhaustive](#short-not-exhaustive)
- [The test section](#the-test-section)
- [The labels](#the-labels)
- [When the repository has no template](#when-the-repository-has-no-template)

## Where the shape comes from

`.claude/merge-request.json` is the project's: the setup writes it once (the
language the team reviews in, and its labels) and the developers edit it.
`mr-meta.sh` reads it together with the branch name, so the language, the title
and the labels are the same whichever flow opens the merge request:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/mr-meta.sh" --summary "<what was done>" \
  [--breaking] [--priority <urgent|high|normal|low>] --json
```

Pass `--priority` when the work comes from a task (its priority, as the board
gives it) and `--breaking` when the change breaks a contract. `META_FILE` empty
means the project has no metadata yet: write in the template's language, pass
no labels, and say in the report that the setup's UPDATE writes the file.

## The title

```
<Type>: <what was done, in LANGUAGE> [<TASK-ID>]
```

- `Feat: Aggiunta rotazione del refresh token [DE-123]` — `LANGUAGE` is `it`
- `Fix: Reject an expired refresh token [DE-456]` — `LANGUAGE` is `en`
- `Chore: Aggiornamento della toolchain Flutter` — no ticket, no brackets

`<Type>` is the branch type, capitalised, followed by a colon — `TITLE_TYPE`.
It stays as it is in either language; what follows is written in `LANGUAGE`.
The task id closes the title in square brackets. `mr-meta.sh --summary` composes
it as `TITLE`: use that, do not assemble it by hand.

**The commits keep Conventional Commits** (`feat(auth): add refresh token
rotation [DE-123]`, always in English) — commitlint checks them and
semantic-release reads them. The two conventions do not collide, one naming the
merge request and the other the commits, with one exception: on a repository
that **squash-merges** into a semantic-release branch, the squash subject *is* a
commit. Put the conventional form there, or the release computation skips the
change.

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

`TEMPLATE` from `mr-meta.sh` is the path it found, the host's own folder first.

Filling it means:

- every heading answered, in `LANGUAGE` (the template's own language when there
  is no metadata file);
- the HTML comments left where they are (they are instructions to the author and
  do not render); the placeholder lines replaced;
- a checklist item ticked only when it is true. An unticked box is information;
  a box ticked because it was there is a claim a reviewer will act on;
- a section with nothing to say gets one line saying so — `No screenshot: no UI
  change` — never silence.

## Short, not exhaustive

A reviewer reads the description before the diff, and a description longer than
the diff is not read at all. Keep the body to what the diff cannot say:

- **the description** — two to four sentences: the problem, the decision, the
  task link. Not a file-by-file tour; the diff is the tour.
- **lists over prose**, one line per item; no restating the title, no
  repeating the spec — link it.
- **sections that do not apply are deleted** when the template says so, and
  otherwise get one line (`No screenshot: no UI change`).
- the whole body fits on one screen. When it does not, cut the narrative, never
  the test steps.

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

## The labels

`LABELS` is the list to pass, comma-separated, in the order the metadata gives:
the branch type's (`by_type`), `breaking` with `--breaking`, the task's priority
(`by_priority`), and `on_open`. Pass it as one `--label "<LABELS>"`. The setup
created the catalogue on the forge; if the host still refuses one, drop that
label, open the merge request with the rest, and name the missing one in the
report — a label is never a reason to leave the merge request unopened, and
never one to invent a replacement. Labels outside the mappings (`Work: *`,
`State: Approved`) are the reviewers' to set.

## When the repository has no template

No forge, or a project the setup never wrote one into. Use this body, with
the headings in `LANGUAGE`:

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
