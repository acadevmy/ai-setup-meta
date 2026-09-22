# GitLab — what `glab` does differently

Only the `glab` invocations, plus the one thing GitLab genuinely does its own
way: MR templates. Branch recipe, commit format, MR body and tagging are in
`SKILL.md` and are the same on both hosts.

`glab` must be authenticated (`glab auth login`). Install it with
`brew install glab` (macOS) or `apt install glab` (Debian/Ubuntu). On
self-hosted GitLab with an ambiguous hostname, `glab auth status --hostname
<host>` succeeding is what identifies this as the right reference.

| Operation | Command |
|---|---|
| Open an MR | `glab mr create --source-branch "$(git branch --show-current)" --target-branch "$BASE" --title "…" --description-file body.md` |
| Short body, no file | the same, with `--description "<body>"` instead |
| Add a label | `glab mr create … --label <name>` — `glab label list` shows what exists |
| MR state | `glab mr view <n> --output json` |
| Open MRs | `glab mr list --state opened` |
| Pipeline | `glab ci status` |
| Release | `glab release create v1.2.0 --name "v1.2.0" --notes-file notes.md` (GitLab 16.0+) |

## MR templates

GitLab reads MR templates only from `.gitlab/merge_request_templates/`, and
`glab mr create` does not apply one on its own. `--template <name>` would
insert it **unfilled** — the description would arrive as the empty form — so
the template is read, filled and passed back as a file:

1. `Default.md` exists → fill that one.
2. No `Default.md` → match the branch prefix against the template names:
   `feat/` → the first matching `feature`; `fix/` or `hotfix/` → the first
   matching `bug` or `fix`; otherwise the first alphabetically.
3. No templates directory, or empty → the fallback body in `merge-request.md`.

```bash
glab mr create … --description-file body.md   # "-" reads it from stdin
```

A build without `--description-file` (`glab mr create --help` says) takes
`--description "$(cat body.md)"` instead. `--template` stays useful for one
thing only: seeing what the form looks like before filling it.
