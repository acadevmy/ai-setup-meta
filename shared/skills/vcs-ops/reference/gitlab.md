# GitLab — what `glab` does differently

Only the `glab` invocations, plus the one thing GitLab genuinely does its own
way: MR templates. Branch recipe, commit format, MR body and tagging are in
`SKILL.md` and are the same on both hosts.

`glab` must be authenticated (`glab auth login`). Install it with
`brew install glab` (macOS) or `apt install glab` (Debian/Ubuntu). On
self-hosted GitLab with an ambiguous hostname, `glab auth status --hostname
<host>` succeeding is what identifies this as the right reference.

Each `<PLACEHOLDER>` is a value an earlier step returned, written out as a
literal: `BASE_BRANCH` from `sdd-start.sh` / `check-prerequisites.sh`, `BRANCH`,
`TITLE` and `LABELS` from `mr-meta.sh`. Keep the single quotes, and write a `'`
inside a value as `'\''` (`dell'API` → `'dell'\''API'`).

| Operation | Command |
|---|---|
| Open an MR | `glab mr create --source-branch '<BRANCH>' --target-branch '<BASE_BRANCH>' --title '<TITLE>' --description-file body.md` |
| Short body, no file | the same, with `--description '<body>'` instead |
| Add the labels | `glab mr create … --label '<LABELS>'` — comma-separated, as `mr-meta.sh` returns them |
| MR state | `glab mr view <n> --output json` |
| Open MRs | `glab mr list --state opened` |
| Pipeline | `glab ci status` |
| Release | `glab release create v1.2.0 --name "v1.2.0" --notes-file notes.md` (GitLab 16.0+) |

## MR templates

GitLab reads MR templates only from `.gitlab/merge_request_templates/`, and
`glab mr create` does not apply one on its own. `--template <name>` would
insert it **unfilled** — the description would arrive as the empty form — so
the template is read, filled and passed back as a file:

1. `Default.md` exists → fill that one (`mr-meta.sh` returns it as `TEMPLATE`).
2. No `Default.md` → match the branch prefix against the template names:
   `feat/` → the first matching `feature`; `fix/` or `hotfix/` → the first
   matching `bug` or `fix`; otherwise the first alphabetically.
3. No templates directory, or empty → the fallback body in `merge-request.md`.

```bash
glab mr create … --description-file body.md   # "-" reads it from stdin
```

A build without `--description-file` (`glab mr create --help` says) takes the
filled body inline instead, as `--description '<body>'` with the same `'\''`
rule. `--template` stays useful for one thing only: seeing what the form looks
like before filling it.

**`glab` alone on the command line.** It runs outside the Bash sandbox only
when the whole call matches `glab *`: a pipe, a `cd … &&`, a redirect to a file
or a `$(…)` keeps it sandboxed, where on macOS it fails TLS verification. No
form above needs any of them: every value is a single-quoted literal, and
inside double quotes a `$` or a backtick in a filled title or body would be a
substitution.
