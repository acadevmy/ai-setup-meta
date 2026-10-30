# The section in the merge request description

The distill reaches the reviewer inside the merge request description, where it
is read before the diff. It **adds** to the description, it never stands in for
it: the repository's template, filled by `vcs-ops`, stays the body, and the
distill is one more section at its end, between two hidden markers. Only that
section is beowulf's — the filled template and whatever a person added are
never rewritten, reordered or trimmed. The local document is not visible to
reviewers, so the section stands on its own.

```markdown
<!-- beowulf:start -->
## Distill

<In short, 3–5 lines>

**High risk**
- <point>: <why it matters> ([code](<permalink>))

**Try by hand**
- [ ] <item>

<sub>Updated at <short sha>. Medium and low risk, decisions and the full map are in the local document of whoever generated it.</sub>
<!-- beowulf:end -->
```

In `LANGUAGE`, headings included. No high-risk point → `**High risk**: none`, in
one line. **Try by hand** holds only what the template's test section does not
already list; when it lists everything, the block is left out. The section obeys
the brevity rule of `vcs-ops`: a description longer than the diff is not read.

## Writing it

1. Read the current description (table below) and write it to `body.md` in the
   scratchpad. Read it right before writing: a person may have edited it since.
2. Markers present → replace everything from `<!-- beowulf:start -->` to
   `<!-- beowulf:end -->`, both included, with the new section. Markers absent →
   append the section at the end, after a blank line. Nothing else in the file
   changes.
3. Write `body.md` back.

Every `gh` / `glab` call follows `vcs-ops`: values as single-quoted literals, no
`$(…)`, no pipe, no redirect, no `cd &&` — read each call's output and carry the
value into the next call yourself.

| Step | GitHub | GitLab |
|---|---|---|
| Number | `gh pr view --json number --jq .number` | `glab mr view --output json` → `iid` |
| Description | `gh api 'repos/{owner}/{repo}/pulls/<n>' --jq .body` | `glab mr view --output json` → `description` |
| Write it | `gh api -X PATCH 'repos/{owner}/{repo}/pulls/<n>' -F 'body=@body.md'` | `glab api -X PUT 'projects/:id/merge_requests/<iid>' -F 'description=@body.md'` |

The write call falls under the `ask` rule: the developer confirms it.

## When the merge request is not open yet

Nothing is written to the forge. Hand the section to `vcs-ops` with the merge
request it is about to open: it goes at the end of the filled template, markers
included, so the next run finds it and replaces it.
