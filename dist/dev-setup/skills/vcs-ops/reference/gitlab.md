# GitLab — what `glab` does differently

Only the `glab` invocations, plus the one thing GitLab genuinely does its own
way: MR templates. Branch recipe, commit format, MR body and tagging are in
`SKILL.md` and are the same on both hosts.

`glab` must be **1.40+** and authenticated (`glab auth login`) — 1.40 is where
`--template` landed; on an older build, read the template file yourself and pass
its content through `--description`. Install with `brew install glab` (macOS) or
`apt install glab` (Debian/Ubuntu). On self-hosted GitLab with an ambiguous
hostname, `glab auth status --hostname <host>` succeeding is what identifies this
as the right reference.

| Operation | Command |
|---|---|
| Open an MR | `glab mr create --source-branch "$(git branch --show-current)" --target-branch "$BASE" --title "…" --template Default` |
| Without a template | the same, with `--description "<body>"` instead |
| Add a label | `glab mr create … --label <name>` — `glab label list` shows what exists |
| MR state | `glab mr view <n> --output json` |
| Open MRs | `glab mr list --state opened` |
| Pipeline | `glab ci status` |
| Release | `glab release create v1.2.0 --name "v1.2.0" --notes-file notes.md` (GitLab 16.0+) |

## MR templates

Unlike the web UI, `glab mr create` does **not** apply
`.gitlab/merge_request_templates/` on its own — you have to name the template.
Pick it in this order:

1. `Default.md` exists → `--template Default` (the extension is optional).
2. No `Default.md` → match the branch prefix against the template names:
   `feat/` → the first matching `feature`; `fix/` or `hotfix/` → the first
   matching `bug` or `fix`; otherwise the first alphabetically.
3. No templates directory, or empty → drop `--template` and pass the `SKILL.md`
   body through `--description`.

`glab` reads the template out of the local checkout and fills the description
before opening the MR: nothing to paste by hand.
