# GitHub — what `gh` does differently

Only the `gh` invocations. Branch recipe, commit format, PR body and tagging are
in `SKILL.md` and are the same on both hosts.

`gh` must be authenticated (`gh auth login`). On GitHub Enterprise with an
ambiguous hostname, `gh auth status --hostname <host>` succeeding is what
identifies this as the right reference.

| Operation | Command |
|---|---|
| Open a PR | `gh pr create --base "$BASE" --head "$(git branch --show-current)" --title "…" --body-file body.md` |
| Add a label | `gh pr create … --label <name>` — `gh label list` shows what exists |
| PR state | `gh pr view <n> --json state,statusCheckRollup,reviewDecision` |
| Open PRs | `gh pr list --state open` |
| CI runs | `gh pr checks <n>` |
| Release | `gh release create v1.2.0 --title "v1.2.0" --notes-file notes.md` |

Three things that bite:

- **`--body-file`, not `--body`.** An inline body loses its newlines as soon as
  it contains a backtick or a `$`, and the PR arrives as one paragraph.
- **`gh` does not apply `.github/PULL_REQUEST_TEMPLATE.md`** when a body is
  passed — it inserts the template only into the editor it opens interactively.
  So read that file yourself, fill it as `merge-request.md` describes, and write
  the result to the file you pass with `--body-file`.
- **A label that does not exist fails the whole call**, so the PR is never
  created. Check `gh label list` before passing `--label`.
