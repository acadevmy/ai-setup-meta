# Changelog

## [1.5.0] - 2026-04-23

### Added
- introduce agent behavioral guidelines and update constitution to restrict premature abstractions and unrequested flexibility (#15)

## [Unreleased]

### Added
- CONSTITUTION §5: explicit rules against premature abstractions, unrequested flexibility and defensive code for impossible cases
- AGENTS.template.md and AGENTS.workspace-template.md: new "Agent behavior" section with four meta-principles (Think before coding, Simplicity first, Surgical changes, Goal-driven execution) to reduce LLM coding errors

### Changed
- CONSTITUTION §5 Boy Scout Rule scoped to trivial decay in files already being edited, resolving the tension with surgical-change behavior
- CONSTITUTION version bump 1.1.0 → 1.2.0
- AGENTS.template.md version bump 2.0.0 → 2.1.0
- AGENTS.workspace-template.md version bump 1.0.0 → 1.1.0

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
