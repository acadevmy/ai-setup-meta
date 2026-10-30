# The merge request comment

One comment per merge request: created on the first run, updated on the next
ones. It is recognised by the hidden marker on its first line, which is never
removed. The local document is not visible to reviewers, so the comment stands
on its own.

```markdown
<!-- beowulf -->
## Distill: <title>

<In short, 3–5 lines>

**High risk**
- <point>: <why it matters> ([code](<permalink>))

**Try by hand**
- [ ] <item>

<sub>Updated at <short sha>. Medium and low risk, decisions and the full map are in the local document of whoever generated it.</sub>
```

Write the body to a file first (`comment.md` in the scratchpad). Every `gh` /
`glab` call follows `vcs-ops`: values as single-quoted literals, no `$(…)`, no
pipe, no redirect, no `cd &&` — read each call's output and carry the value
into the next call yourself.

## GitHub

| Step | Command |
|---|---|
| PR number | `gh pr view --json number --jq .number` |
| Existing comment | `gh api 'repos/{owner}/{repo}/issues/<n>/comments' --paginate --jq '.[] \| select(.body \| startswith("<!-- beowulf -->")) \| .id'` |
| Update it | `gh api -X PATCH 'repos/{owner}/{repo}/issues/comments/<id>' -F 'body=@comment.md'` |
| Or create it | `gh api -X POST 'repos/{owner}/{repo}/issues/<n>/comments' -F 'body=@comment.md'` |

## GitLab

| Step | Command |
|---|---|
| MR iid | `glab mr view --output json` → `iid` |
| Existing comment | `glab api 'projects/:id/merge_requests/<iid>/notes?per_page=100&sort=desc' --paginate` → the note whose `body` starts with `<!-- beowulf -->` |
| Update it | `glab api -X PUT 'projects/:id/merge_requests/<iid>/notes/<id>' -F 'body=@comment.md'` |
| Or create it | `glab api -X POST 'projects/:id/merge_requests/<iid>/notes' -F 'body=@comment.md'` |

The write calls fall under the `ask` rule: the developer confirms each one.
With no merge request open, nothing is created — say so.
