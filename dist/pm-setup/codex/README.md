# PM Setup — Guida installazione OpenAI Codex CLI

Guida per configurare il workflow AI-Native per Project Manager su **OpenAI Codex CLI**.

## Prerequisiti

- [OpenAI Codex CLI](https://github.com/openai/codex) installato
- [Node.js](https://nodejs.org/) 18+ (per i server MCP)
- Account ClickUp con accesso al workspace del team

## Installazione

pm-setup e' distribuito come plugin Codex. Installazione tramite marketplace:

```
/plugin install pm-setup@acadevmy
```

Oppure, da sorgente locale (per sviluppo/testing):

```bash
codex --plugin-dir ./dist/pm-setup/codex
```

**Nessuna procedura di setup aggiuntiva.** Le skill, le istruzioni e le regole di qualita'
(PM-CONSTITUTION) sono bundled nel plugin — niente file da scrivere nella directory del progetto.

## Configurazione MCP servers

I server MCP necessari sono dichiarati nel plugin. Se non vengono attivati automaticamente,
aggiungili manualmente in `~/.codex/config.toml`:

```toml
# ClickUp — gestione task (obbligatorio)
[mcp_servers.clickup]
command = "npx"
args = ["-y", "mcp-remote", "https://mcp.clickup.com/mcp"]

# Google Drive — analisi trascrizioni meeting (consigliato)
[mcp_servers.gdrive]
command = "npx"
args = ["@piotr-agier/google-drive-mcp"]

[mcp_servers.gdrive.env]
GOOGLE_DRIVE_OAUTH_CREDENTIALS = "${GOOGLE_DRIVE_OAUTH_CREDENTIALS}"

# Figma — analisi design (opzionale)
[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
bearer_token_env_var = "FIGMA_OAUTH_TOKEN"
```

Al primo utilizzo di ClickUp, Codex ti chiedera' di autorizzare l'accesso al tuo workspace.

## Skill disponibili

| Skill | Descrizione |
|---|---|
| `pm-flow` | Flusso completo: documento → task ClickUp (lint automatico incluso) |
| `pm-intake` | Analisi documento → Discovery Brief (con auto-detection stack) |
| `pm-transcript` | Analisi trascrizioni Google Meet da Drive |
| `pm-figma` | Analisi design Figma → task per riprodurre il layout |
| `pm-structure` | Brief → gerarchia Epic/Story/Task |
| `pm-refine` | Validazione INVEST + criteri di accettazione Gherkin |
| `pm-review` | Revisione e approvazione |
| `pm-lint` | Validazione formato rigido (hard-fail) pre-pubblicazione |
| `pm-publish` | Pubblicazione su ClickUp con delay deterministico |

## Come iniziare

### Da un documento di requisiti

```
Esegui la skill pm-flow con il file requisiti.md
```

### Da una trascrizione di meeting

```
Esegui la skill pm-transcript
```

### Da un design Figma

```
Esegui la skill pm-figma con URL https://www.figma.com/design/abc123/My-Project?node-id=1-2
```

## Co-installazione con dev-setup

pm-setup puo' convivere con il plugin `dev-setup` nello stesso progetto senza conflitti.
Non scrive file nella directory del progetto — e' completamente self-contained.

---
*Generato da: ai-base-setup v2.0.0*
