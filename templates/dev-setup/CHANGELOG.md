# Changelog

<!--
release-please gestisce questo file dal release v1.7.0 in avanti.
Le sezioni `[X.Y.Z]` vengono generate dai conventional commits dall'ultimo tag.
Non modificare manualmente le sezioni datate — saranno sovrascritte al prossimo run.
-->

## [1.13.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.12.0...dev-setup-v1.13.0) (2026-05-13)


### Features

* **auto-maintain:** Migrate scheduler from launchd to Claude Code Routines ([#52](https://github.com/acadevmy/ai-setup-meta/issues/52)) ([13f6fb2](https://github.com/acadevmy/ai-setup-meta/commit/13f6fb2ebe9fcb61c7fde29f11da613eceaa3112))
* Implement timeout logic for auto-maintain runner and exclude state file from tracking ([#46](https://github.com/acadevmy/ai-setup-meta/issues/46)) ([100277b](https://github.com/acadevmy/ai-setup-meta/commit/100277b4951678aea6dfce15ee6033aa7e71aed6))


### Bug Fixes

* **runner:** Sync sandbox to main before run and harden process kill ([#48](https://github.com/acadevmy/ai-setup-meta/issues/48)) ([c13cff1](https://github.com/acadevmy/ai-setup-meta/commit/c13cff12505fc33655b8da05614c27d2ad5cb176))
* **runner:** Use detached HEAD in sandbox to avoid worktree branch conflict ([#50](https://github.com/acadevmy/ai-setup-meta/issues/50)) ([3688eda](https://github.com/acadevmy/ai-setup-meta/commit/3688eda07988aee9edd9ce90664e028d3da7dab2))

## [1.12.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.11.0...dev-setup-v1.12.0) (2026-05-08)


### Features

* **auto-maintain:** Add retry loop and resumable pipeline via state file ([#43](https://github.com/acadevmy/ai-setup-meta/issues/43)) ([83f709c](https://github.com/acadevmy/ai-setup-meta/commit/83f709cbfc5a44f052a57a9811351fc91e6da667))

## [1.11.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.10.0...dev-setup-v1.11.0) (2026-05-08)


### Features

* **setup:** Tighten allowlist to detected package manager ([#41](https://github.com/acadevmy/ai-setup-meta/issues/41)) ([eacb6d5](https://github.com/acadevmy/ai-setup-meta/commit/eacb6d5d085af0aef18be7982c678ff1cac2d318))
* **template:** Add Project Identity, Infrastructure, Quality Standards, Boundaries ([#40](https://github.com/acadevmy/ai-setup-meta/issues/40)) ([970e6bd](https://github.com/acadevmy/ai-setup-meta/commit/970e6bd060f1241b31f769e6a6b4270d2b2cbf22))


### Bug Fixes

* **settings:** Tighten deny list and document MCP scopes ([#39](https://github.com/acadevmy/ai-setup-meta/issues/39)) ([fd4f93a](https://github.com/acadevmy/ai-setup-meta/commit/fd4f93a7d2c75aea835774a68524a487574c8eeb))

## [1.10.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.9.1...dev-setup-v1.10.0) (2026-04-30)


### Features

* **setup:** Skip per-library file generation + auto-cite consumed libraries ([#36](https://github.com/acadevmy/ai-setup-meta/issues/36)) ([5985098](https://github.com/acadevmy/ai-setup-meta/commit/5985098029504eccca30c68d670498f562af0c58))

## [1.9.1](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.9.0...dev-setup-v1.9.1) (2026-04-30)


### Bug Fixes

* **settings:** Use space syntax in Bash allow rules ([#34](https://github.com/acadevmy/ai-setup-meta/issues/34)) ([c54afdb](https://github.com/acadevmy/ai-setup-meta/commit/c54afdbbe1ff348087f316c9d2cc0b34b0d4365c))

## [1.9.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.8.2...dev-setup-v1.9.0) (2026-04-29)


### Features

* **setup:** Detect Next.js + verify framework AGENTS.md conventions online ([#29](https://github.com/acadevmy/ai-setup-meta/issues/29)) ([5d06ed6](https://github.com/acadevmy/ai-setup-meta/commit/5d06ed69f2d4a4d8e13737111ff11533ebdd3317))

## [1.8.2](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.8.1...dev-setup-v1.8.2) (2026-04-29)


### Bug Fixes

* **settings:** Allow glab, yarn, pnpm, jq in baseline allowlist ([#27](https://github.com/acadevmy/ai-setup-meta/issues/27)) ([87018ad](https://github.com/acadevmy/ai-setup-meta/commit/87018ade62674a6a1e6237bb11be916fb1d32aa9))

## [1.8.1](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.8.0...dev-setup-v1.8.1) (2026-04-28)


### Bug Fixes

* **setup:** Enumerate Nx-inferred workspaces from package.json and pnpm-workspace.yaml ([#25](https://github.com/acadevmy/ai-setup-meta/issues/25)) ([bb12df3](https://github.com/acadevmy/ai-setup-meta/commit/bb12df3b31d0e2d0e1178ec04c82fefcd681d18d))

## [1.8.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.7.0...dev-setup-v1.8.0) (2026-04-27)


### Features

* **setup:** Add Terraform profile and CONSTITUTION §X ([#20](https://github.com/acadevmy/ai-setup-meta/issues/20)) ([1349af7](https://github.com/acadevmy/ai-setup-meta/commit/1349af711e55cf8882c54a7dee97229f7ec5190e))

## [1.7.0](https://github.com/acadevmy/ai-setup-meta/compare/dev-setup-v1.6.0...dev-setup-v1.7.0) (2026-04-27)


### Features

* **release:** Automate build and release via GitHub Actions ([#21](https://github.com/acadevmy/ai-setup-meta/issues/21)) ([881a912](https://github.com/acadevmy/ai-setup-meta/commit/881a9128c24d866f531753f68059794519a650df))


### Bug Fixes

* **ci:** Correct release-please tag separator to avoid double-v ([#23](https://github.com/acadevmy/ai-setup-meta/issues/23)) ([0a3ded8](https://github.com/acadevmy/ai-setup-meta/commit/0a3ded8bc5065a27e672e2f477dd658a61beff13))

## [1.6.0] - 2026-04-24

### Added
- detect VCS and emit provider-aware greenfield files
- add gitlab-ops and symmetric self-identify in github-ops

### Changed
- Merge pull request #17 from acadevmy/feat/gitlab-support
- bump versions and generalize Constitution §16
- add GitLab variants, update CHANGELOG, rebuild dist

## [1.5.2] - 2026-04-24

### Fixed
- use opus instead of sonnet

## [1.5.1] - 2026-04-23

### Changed
- prefer ctx7 CLI over Context7 MCP for docs lookups (#16)

## [1.5.0] - 2026-04-23

### Added
- introduce agent behavioral guidelines and update constitution to restrict premature abstractions and unrequested flexibility (#15)

## [1.4.0] - 2026-04-20

### Added
- add Nuxt 3 support and extract greenfield boilerplate (#14)
- add support for Cursor plugin integration and enhance README with installation instructions (#13)
- declare allowed-tools AskUserQuestion in skill frontmatter
- add PM template for AI-assisted ClickUp task creation (#10)

### Changed
- bump dev-setup plugin version to 1.3.6 and update environment template examples
- enforce closed-question interaction, add dynamic base branch selection, and introduce a verify step in development workflows
- bump dev-setup to v1.3.5
- bump dev-setup to v1.3.4
- bump dev-setup to v1.3.2
- bump dev-setup to v1.3.0
- bump dev-setup to v1.0.6
- bump dev-setup to v1.0.5
- require Context7 documentation lookups for external APIs in agent templates
- update environment variable templates to include missing configuration keys
- Feat/translation (#9)
- Feat/flutter constitution best practices (#8)
- enhance mobile setup documentation for Flutter (#7)
- update environment variable templates with new configuration keys

### Fixed
- add concrete AskUserQuestion examples to all interactive skills
- stop generating filler text after interview questions (#11)

## [Unreleased]

### Added
- add Nuxt 3 / Vue 3 stack profile (`web-frontend-nuxt.md`)
- extend setup-agent auto-detect to distinguish Nuxt from other frontend frameworks
- add Nuxt option to greenfield stack selection (Step 2b) and to full-stack frontend variant
- add Section VII to CONSTITUTION with Nuxt/Vue rules (24-27: Composition API, useFetch/useAsyncData, Pinia, SSR/auto-imports) — applied also to existing Nuxt projects via Step 4 Rule A
- extend Step 4 Rule A with framework-based removal (keeps Section VI or VII depending on detected/selected framework)

### Changed
- renumber CONSTITUTION sections: Mobile VII → VIII, AI Agent VIII → IX (rules 24-34 shifted to 28-38, rules 35-37 shifted to 39-41)
- extract greenfield config boilerplate (commitlint, prettier, semantic-release, base ESLint, release workflow, gitignore) from dev-setup-agent.md into `templates/dev-setup/boilerplate/`; setup-agent now downloads them verbatim via `gh api` (Step 8.4/8.6/8.7 simplified, ~140 lines removed from the agent)
- add `boilerplate_files` field to manifest.json; validate-setup-urls.sh and build-claude.sh extended to enumerate it

## [1.3.5] - 2026-04-10

### Added
- declare allowed-tools AskUserQuestion in skill frontmatter

## [1.3.4] - 2026-04-10

### Added
- add PM template for AI-assisted ClickUp task creation (#10)
- implement multi-project support with workspace and project-specific AGENTS.md templates and detection logic

### Changed
- bump dev-setup to v1.3.2
- bump dev-setup to v1.3.0
- bump dev-setup to v1.0.6
- bump dev-setup to v1.0.5
- require Context7 documentation lookups for external APIs in agent templates
- update environment variable templates to include missing configuration keys
- Feat/translation (#9)
- Feat/flutter constitution best practices (#8)
- enhance mobile setup documentation for Flutter (#7)
- update environment variable templates with new configuration keys
- remove legacy changelog entries prior to version 1.0.0
- update environment variable templates to include missing configuration keys
- update Figma MCP configuration to use OAuth URL instead of manual access tokens
- update environment variable templates with new configuration keys
- remove render-template skill and add project/workspace AGENTS templates
- remove sync-task skill and update documentation and setup templates accordingly

### Fixed
- add concrete AskUserQuestion examples to all interactive skills
- stop generating filler text after interview questions (#11)

## [1.3.2] - 2026-04-10

### Added
- add PM template for AI-assisted ClickUp task creation (#10)
- implement multi-project support with workspace and project-specific AGENTS.md templates and detection logic
- add sdd-discovery skill for structured interview before spec generation (#5)
- Introduce `CLAUDE.md` as the Claude Code entry point and standardize AI agent instructions to `AGENTS.md`.

### Changed
- bump dev-setup to v1.3.0
- bump dev-setup to v1.0.6
- bump dev-setup to v1.0.5
- require Context7 documentation lookups for external APIs in agent templates
- update environment variable templates to include missing configuration keys
- Feat/translation (#9)
- Feat/flutter constitution best practices (#8)
- enhance mobile setup documentation for Flutter (#7)
- update environment variable templates with new configuration keys
- remove legacy changelog entries prior to version 1.0.0
- update environment variable templates to include missing configuration keys
- update Figma MCP configuration to use OAuth URL instead of manual access tokens
- update environment variable templates with new configuration keys
- remove render-template skill and add project/workspace AGENTS templates
- remove sync-task skill and update documentation and setup templates accordingly

### Fixed
- stop generating filler text after interview questions (#11)

## [1.0.6] - 2026-04-09

### Changed
- Aggiornamento plugin

## [1.0.5] - 2026-04-09

### Added
- implement multi-project support with workspace and project-specific AGENTS.md templates and detection logic
- add sdd-discovery skill for structured interview before spec generation (#5)
- Introduce `CLAUDE.md` as the Claude Code entry point and standardize AI agent instructions to `AGENTS.md`.
- migrate to Claude Code Plugin + Marketplace distribution
- Implement Spec-Driven Development (SDD) workflow by adding four new skills and updating the manifest and agent templates.

### Changed
- require Context7 documentation lookups for external APIs in agent templates
- update environment variable templates to include missing configuration keys
- Feat/translation (#9)
- Feat/flutter constitution best practices (#8)
- enhance mobile setup documentation for Flutter (#7)
- update environment variable templates with new configuration keys
- remove legacy changelog entries prior to version 1.0.0
- update environment variable templates to include missing configuration keys
- update Figma MCP configuration to use OAuth URL instead of manual access tokens
- update environment variable templates with new configuration keys
- remove render-template skill and add project/workspace AGENTS templates
- remove sync-task skill and update documentation and setup templates accordingly
- bump dev-setup to v2.0.0
- Merge branch 'feat/multi-template-architecture'

### Fixed
- stop generating filler text after interview questions (#11)
