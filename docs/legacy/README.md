# docs/legacy — archived material

What lives here is **no longer part of the product**: it is declared in no
`manifest.json`, it never reaches `dist/`, no skill loads it and CI does not
validate it. It stays in the repo purely as a historical reference, to show what
the setup looked like before the current architecture.

Do not edit it to "keep it current": if some content is still needed, it gets
rewritten in its present home (a skill, a profile or a rule) and the copy here
stays as it is.

| File | What it was | Why it is here |
|---|---|---|
| `dev-setup-agent.md` | Bootstrap agent for the `dev-setup` domain (1005 lines) that downloaded the template files through `gh api` | Replaced by the setup skill (`templates/dev-setup/setup-skill.md`): it was declared in the manifest but no builder ever shipped it to `dist/`. Archived with PR 2 of the revision chain (DE-16472) |
| `CONSTITUTION.md` | Single governance document (629 lines, ~6–7k tokens) copied whole into every project and read "in full" at every session | Dismantled into the path-scoped rules under `templates/dev-setup/rules/`, which the harness injects only when the model touches a matching file, plus the rules that moved into the tooling (ESLint, coverage thresholds, branch protection). Archived with PR 7 of the revision chain (DE-16477) |
