# Profile — Next.js

Profile that captures the **`AGENTS.md` bundled-docs convention** introduced by Next.js 16.2 (March 2026), plus the companion tooling shipped in the same release. The setup skill consumes this profile when it detects `next` in a project's `package.json`.

## The convention in one paragraph

Next.js 16.2 ships its own documentation as plain Markdown inside the `next` npm package at `node_modules/next/dist/docs/`. A short `AGENTS.md` at the project root tells AI coding agents to read those docs before writing code, redirecting them away from stale training data. Vercel's [evals](https://nextjs.org/blog/next-16-2-ai) report 100% pass-rate with bundled-docs vs ~79% with on-demand skill-based retrieval — the insight being that always-available context beats lookup-on-suspicion, because agents often don't realize when they should search.

## Canonical files

**`AGENTS.md`** — the directive:

```md
<!-- BEGIN:nextjs-agent-rules -->

# Next.js: ALWAYS read docs before coding

Before any Next.js work, find and read the relevant doc in `node_modules/next/dist/docs/`. Your training data is outdated — the docs are the source of truth.

<!-- END:nextjs-agent-rules -->
```

**`CLAUDE.md`** — the import shim for Claude Code:

```md
@AGENTS.md
```

## The `BEGIN/END` markers are load-bearing

The `<!-- BEGIN:nextjs-agent-rules -->` … `<!-- END:nextjs-agent-rules -->` comments delimit a **Next.js-managed section**. `next upgrade` (and any future Vercel tooling) rewrites the content **inside** the markers but preserves anything **outside** them.

This means:

- The dev-setup plugin's own `AGENTS.md` content (Identity, Agent behavior, Test/Lint commands, etc.) lives **outside and below** the END marker so `next upgrade` never touches it.
- Conversely, the plugin's regeneration logic must **never** edit content inside the markers — that's Vercel's territory. If the user later runs `next upgrade`, anything we wrote there gets blown away.

## Version requirements

| Next.js version              | Bundled docs path                 | Recommended action                                                                                            |
| ---------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `≥ 16.2.0`                   | `node_modules/next/dist/docs/` (shipped in npm package) | Add the canonical block as-is. `next upgrade` keeps the inside fresh.                                          |
| `16.0.0` – `16.1.x`          | not bundled                       | Run `npx @next/codemod@latest agents-md`. The codemod exports the docs to `.next-docs/` and adjusts the path. |
| Pre-`16.x`                   | n/a                               | Upgrade to 16.2+ first if AGENTS.md alignment matters; otherwise skip the block (agents fall back to training data with no path correction). |

The `--no-agents-md` flag on `create-next-app` opts out of the file generation entirely on greenfield projects.

## Setup behaviour expected from this plugin

When `setup-skill.md` detects Next.js (via `dependencies.next` or `devDependencies.next` in `package.json`):

1. Read the version constraint, parse semver to identify the major.minor.
2. Generate `AGENTS.md` with the canonical `BEGIN/END` block at the very top.
3. Place all of the plugin's standard `AGENTS.md` content (Identity, Agent behavior, Project stack, etc.) **below** the END marker.
4. In the setup summary, instruct the developer:
   - For `≥ 16.2`: "run `npx next upgrade@canary` periodically — it keeps the block content current."
   - For `< 16.2`: "run `npx @next/codemod@latest agents-md` — it generates `.next-docs/` and adjusts the path."

For brownfield repos where `AGENTS.md` already contains a `BEGIN:nextjs-agent-rules` block (typically from a prior `next upgrade` or `create-next-app`), preserve that block verbatim and append plugin content below the END marker — do **not** regenerate the inside.

## Companion tooling shipped alongside (Next.js 16.2)

These features are listed in the release blog and worth knowing about, even if not auto-installed by this plugin:

- **Browser log forwarding** — `next.config.ts` `logging.browserToTerminal` setting forwards client-side errors to the dev server terminal. Useful when the agent operates entirely from the terminal.
- **Dev server lock file** — `.next/dev/lock` records the running dev server's PID. A second `next dev` attempt prints the existing PID + an actionable error so the agent doesn't get stuck on a port collision.
- **`@vercel/next-browser`** (experimental) — `npx skills add vercel-labs/next-browser` adds a CLI skill that exposes React DevTools, PPR shells, and network activity as text-mode commands an agent can call. Pairs naturally with this profile.

## References

- [Guides: AI Coding Agents](https://nextjs.org/docs/app/guides/ai-agents) — the authoritative setup guide for users
- [Next.js 16.2: AI Improvements](https://nextjs.org/blog/next-16-2-ai) — release blog with the eval results
- [Discussion #92197](https://github.com/vercel/next.js/discussions/92197) — open thread tracking how `next upgrade` should manage `AGENTS.md` over time
- [Building Next.js for an agentic future](https://nextjs.org/blog/agentic-future) — Vercel's positioning blog on agent-friendly tooling
