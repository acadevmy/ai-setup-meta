# Changelog

## [1.0.1] - 2026-03-21

- Aggiornamento automatico via release-template.sh
- Vedi GitHub Release per dettaglio modifiche

Tutte le modifiche rilevanti al `dev-setup-template` sono documentate in questo file.

Il formato è basato su [Keep a Changelog](https://keepachangelog.com/it-IT/1.1.0/),
e questo progetto aderisce a [Semantic Versioning](https://semver.org/lang/it/).

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
