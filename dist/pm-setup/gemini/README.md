# PM Setup — Guida installazione Gemini CLI

Guida per configurare il workflow AI-Native per Project Manager su **Gemini CLI**.

## Installazione rapida

```bash
gemini extensions install https://github.com/acadevmy/ai-setup-meta/dist/pm-setup/gemini
```

Oppure, da sorgente locale:

```bash
gemini extensions install ./dist/pm-setup/gemini
```

**Nessuna procedura di setup aggiuntiva.** Le istruzioni di sistema e le regole di qualita'
(PM-CONSTITUTION) sono bundled nell'estensione — niente file da scrivere nella directory del
progetto. Il plugin convive con `dev-setup` senza conflitti.

---

## Installazione manuale

Se preferisci installare manualmente invece di usare `gemini extensions install`:

### 1. Scarica i file

```bash
# Crea la directory dell'estensione
mkdir -p ~/.config/gemini/extensions/pm-setup/.gemini/commands/pm

# Scarica i file principali
curl -sL "https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini/gemini-extension.json" \
  -o ~/.config/gemini/extensions/pm-setup/gemini-extension.json
curl -sL "https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini/GEMINI.md" \
  -o ~/.config/gemini/extensions/pm-setup/GEMINI.md

# Scarica i comandi slash
for cmd in pm-flow pm-intake pm-transcript pm-figma pm-structure pm-refine pm-review pm-lint pm-publish; do
  curl -sL "https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini/commands/pm/$cmd.toml" \
    -o ~/.config/gemini/extensions/pm-setup/commands/pm/$cmd.toml
done
```

### 2. Configura i server MCP

I server MCP sono dichiarati in `gemini-extension.json` e attivati automaticamente.
Se non vengono caricati, aggiungili in `.gemini/settings.json` del tuo progetto:

```json
{
  "mcpServers": {
    "clickup": {
      "trust": true,
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.clickup.com/mcp"]
    }
  }
}
```

### 3. (Consigliato) Estensione Google Workspace

Per accedere alle trascrizioni dei meeting:

```bash
gemini extensions install https://github.com/gemini-cli-extensions/workspace
```

---

## Verifica installazione

```bash
gemini
/mcp
```

Dovresti vedere `clickup` nella lista dei server attivi.

## Comandi disponibili

| Comando | Descrizione |
|---|---|
| `/pm:pm-flow` | Flusso completo: documento → task ClickUp (lint automatico incluso) |
| `/pm:pm-intake <path>` | Analisi documento → Discovery Brief (con auto-detection stack) |
| `/pm:pm-transcript` | Analisi trascrizioni Google Meet da Drive |
| `/pm:pm-figma <URL>` | Analisi design Figma → task per riprodurre il layout |
| `/pm:pm-structure` | Brief → gerarchia Epic/Story/Task |
| `/pm:pm-refine` | Validazione INVEST + criteri di accettazione Gherkin |
| `/pm:pm-review` | Revisione e approvazione |
| `/pm:pm-lint` | Validazione formato rigido (hard-fail) pre-pubblicazione |
| `/pm:pm-publish` | Pubblicazione su ClickUp con delay deterministico |

## Aggiornamento

```bash
gemini extensions update pm-setup
```

---
*Generato da: ai-base-setup v2.0.0*
