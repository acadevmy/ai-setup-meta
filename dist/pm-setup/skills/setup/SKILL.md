---
name: setup
description: Bundle carrier per PM-CONSTITUTION.md e file di governance. Non richiede esecuzione — il plugin pm-setup e' self-contained.
model: sonnet
user-invocable: false
disable-model-invocation: true
allowed-tools: Read, Bash
---

# pm-setup e' self-contained — nessun setup necessario

Il plugin pm-setup non richiede una procedura di installazione nel progetto.
Le skill, gli agent e la governance (PM-CONSTITUTION.md) sono bundled nel plugin.

## MCP servers

I server MCP sono dichiarati in `.mcp.json` del plugin e vengono attivati automaticamente
al primo utilizzo. Se un server non risulta disponibile, configuralo manualmente:

**ClickUp** (obbligatorio):
```bash
claude mcp add clickup --transport url https://mcp.clickup.com/mcp -s user
```

**Google Drive** (consigliato per pm-transcript):
```bash
claude mcp add gdrive -e GOOGLE_DRIVE_OAUTH_CREDENTIALS=/path/to/gcp-oauth.keys.json -- npx @piotr-agier/google-drive-mcp -s user
```

**Figma** (opzionale per pm-figma):
```bash
claude mcp add figma --transport http https://mcp.figma.com/mcp -s user
```

## Comandi disponibili

Usa queste skill direttamente — non serve eseguire setup:

- `/pm-setup:pm-flow [PATH]`   — flusso completo: documento → task ClickUp
- `/pm-setup:pm-intake [PATH]` — analisi documento → Discovery Brief
- `/pm-setup:pm-transcript`    — analisi trascrizioni Google Meet
- `/pm-setup:pm-figma <URL>`   — analisi design Figma → task
- `/pm-setup:pm-structure`     — brief → gerarchia Epic/Story/Task
- `/pm-setup:pm-refine`        — validazione INVEST + Acceptance Criteria Gherkin
- `/pm-setup:pm-review`        — revisione e approvazione con il PM
- `/pm-setup:pm-lint`          — validazione formato rigido (pre-publish)
- `/pm-setup:pm-publish`       — pubblicazione su ClickUp
