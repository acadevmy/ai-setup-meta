# Changelog

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
