# Changelog

Tutte le modifiche rilevanti al template `dev-setup` sono documentate in questo file.

Il formato è basato su [Keep a Changelog](https://keepachangelog.com/it-IT/1.1.0/),
e questo progetto aderisce a [Semantic Versioning](https://semver.org/lang/it/).

## [2.0.0] - 2026-03-24

### Changed
- Merge branch 'feat/multi-template-architecture'
- remove root CONSTITUTION.md, make template the source of truth
- Implement a multi-domain templating system with manifest.json, restructure the repository for shared agents and skills, and update documentation and scripts accordingly.

## [1.6.0] - 2026-03-23

### Added
- Remove example MCP configuration, add commands to copy agent files, and refine .gitignore for local settings.
- remove `CLAUDE_COMPACT_RESPONSES` and `includeCoAuthoredBy` settings, and add agent file copy commands to local settings
- Introduce distinct TDD/BDD testing methodologies and examples in CONSTITUTION.md and add commands to copy Claude agent files to the template.
- Add BDD skill for frontend development, refine TDD skill for backend, and update associated documentation and skill models.
- add Claude Code hooks for auto-format, file protection, context re-injection, and quality gate
- add 3 sub-agents (clickup, review, validate-template)
- unify AGENT.md and AGENT.inject.md into single template
- integrate simplify and review steps into start-task workflow

### Changed
- update onboarding, workflow docs and fix template version
- migrate skills to directory/SKILL.md format
- bump dev-setup-template to v1.5.0
- remove static config files from template, generate at bootstrap
- bump dev-setup-template to v1.4.1
- Restructure REGISTRY.md to include pattern entries and simplify existing formats, updating associated agents and hooks.
- remove init.sh, inject.sh and generate-inject skill
- migrate setup.md distribution and update all references
- migrate all commands to skills with frontmatter

### Fixed
- add TEMPLATE_VERSION to .env.example for changelog validation
- sync CONSTITUTION.md with source
- add semantic-release deps and upgrade CI to Node 22

## [1.5.0] - 2026-03-23

### Added
- Remove example MCP configuration, add commands to copy agent files, and refine .gitignore for local settings.
- remove `CLAUDE_COMPACT_RESPONSES` and `includeCoAuthoredBy` settings, and add agent file copy commands to local settings
- Introduce distinct TDD/BDD testing methodologies and examples in CONSTITUTION.md and add commands to copy Claude agent files to the template.
- Add BDD skill for frontend development, refine TDD skill for backend, and update associated documentation and skill models.
- add Claude Code hooks for auto-format, file protection, context re-injection, and quality gate
- add 3 sub-agents (clickup, review, validate-template)
- unify AGENT.md and AGENT.inject.md into single template
- integrate simplify and review steps into start-task workflow
- add release script to post-setup commands and ignore local settings file.
- replace template repo with setup agent architecture

### Changed
- remove static config files from template, generate at bootstrap
- bump dev-setup-template to v1.4.1
- Restructure REGISTRY.md to include pattern entries and simplify existing formats, updating associated agents and hooks.
- remove init.sh, inject.sh and generate-inject skill
- migrate setup.md distribution and update all references
- migrate all commands to skills with frontmatter

### Fixed
- add TEMPLATE_VERSION to .env.example for changelog validation
- sync CONSTITUTION.md with source
- add semantic-release deps and upgrade CI to Node 22
- use gh api instead of curl for fetching resources from private repo

## [1.4.1] - 2026-03-23

### Added
- Remove example MCP configuration, add commands to copy agent files, and refine .gitignore for local settings.
- remove `CLAUDE_COMPACT_RESPONSES` and `includeCoAuthoredBy` settings, and add agent file copy commands to local settings
- Introduce distinct TDD/BDD testing methodologies and examples in CONSTITUTION.md and add commands to copy Claude agent files to the template.
- Add BDD skill for frontend development, refine TDD skill for backend, and update associated documentation and skill models.
- add Claude Code hooks for auto-format, file protection, context re-injection, and quality gate
- add 3 sub-agents (clickup, review, validate-template)
- unify AGENT.md and AGENT.inject.md into single template
- integrate simplify and review steps into start-task workflow
- add release script to post-setup commands and ignore local settings file.
- replace template repo with setup agent architecture
- introduce AI workflow injection mode with stack auto-detection and adaptive commands for existing projects.
- install ClickUp MCP with user scope
- accept optional task ID in start-task command

### Changed
- Restructure REGISTRY.md to include pattern entries and simplify existing formats, updating associated agents and hooks.
- remove init.sh, inject.sh and generate-inject skill
- migrate setup.md distribution and update all references
- migrate all commands to skills with frontmatter

### Fixed
- sync CONSTITUTION.md with source
- add semantic-release deps and upgrade CI to Node 22
- use gh api instead of curl for fetching resources from private repo

## [1.1.0] - 2026-03-21

### Added
- README.md per ogni profilo stack (web-frontend, backend-node, mobile)
- Supporto customId ClickUp nella convenzione branch naming (AGENT.md)

### Changed
- AGENT.md — aggiunto customId nella sezione branch naming
- CONSTITUTION.md — rigenerata copia esatta dal repo sorgente

## [1.0.0] - 2026-03-21

### Added
- CONSTITUTION.md — regole di governance tecnica (copia esatta dal repo sorgente)
- AGENT.md — istruzioni per Claude Code, versione sviluppatori
- init.sh — script bootstrap interattivo con selezione stack (web-frontend, backend-node, mobile, fullstack)
- mcp.json.example — template MCP per ClickUp, Figma, Context7
- .env.example — variabili d'ambiente richieste senza valori
- .claude/settings.json — permessi Claude Code per sviluppatori (più restrittivi)
- .claude/commands/tdd.md — workflow TDD guidato
- .claude/commands/review.md — code review automatizzata
- .claude/commands/sync-task.md — sincronizzazione task ClickUp
- .husky/pre-commit — hook ESLint + Prettier (via lint-staged)
- .husky/commit-msg — hook Commitlint (Conventional Commits)
- .commitlintrc.json — configurazione Conventional Commits
- .prettierrc.json — configurazione Prettier
- .eslintrc.base.json — configurazione ESLint base TypeScript
- profiles/web-frontend/ — ESLint, tsconfig, Jest per Next.js/Angular/React
- profiles/backend-node/ — ESLint, tsconfig, Jest per Node.js/NestJS
- profiles/mobile/ — analysis_options (Flutter) + ESLint (React Native)
- CHANGELOG.md — questo file
