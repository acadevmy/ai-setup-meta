# PM Setup — Guida installazione OpenAI Codex CLI

Guida per configurare il workflow AI-Native per Project Manager su **OpenAI Codex CLI**.

## Prerequisiti

- [OpenAI Codex CLI](https://github.com/openai/codex) installato
- [Node.js](https://nodejs.org/) 18+ (per i server MCP)
- Account ClickUp con accesso al workspace del team
- (Consigliato) Account Google per accedere alle trascrizioni dei meeting

## Installazione

### Opzione A: Installazione personale (disponibile in tutti i progetti)

```bash
# 1. Crea la directory plugin personale
mkdir -p ~/.codex/plugins

# 2. Scarica il plugin
curl -sL "https://github.com/acadevmy/ai-setup-meta/archive/refs/heads/main.tar.gz" | \
  tar -xz --strip-components=3 -C ~/.codex/plugins/ "ai-setup-meta-main/dist/pm-setup/codex"
mv ~/.codex/plugins/codex ~/.codex/plugins/pm-setup

# 3. Registra il plugin nel marketplace personale
mkdir -p ~/.agents/plugins
cat > ~/.agents/plugins/marketplace.json << 'JSON'
{
  "name": "acadevmy",
  "interface": {
    "displayName": "Acadevmy Plugins"
  },
  "plugins": [
    {
      "name": "pm-setup",
      "source": {
        "source": "local",
        "path": "~/.codex/plugins/pm-setup"
      },
      "policy": {
        "installation": "INSTALLED_BY_DEFAULT"
      },
      "category": "Productivity"
    }
  ]
}
JSON

# 4. Riavvia Codex
```

### Opzione B: Installazione per progetto

```bash
# 1. Nella root del progetto, crea la directory plugin
mkdir -p ./plugins

# 2. Scarica il plugin
curl -sL "https://github.com/acadevmy/ai-setup-meta/archive/refs/heads/main.tar.gz" | \
  tar -xz --strip-components=3 -C ./plugins/ "ai-setup-meta-main/dist/pm-setup/codex"
mv ./plugins/codex ./plugins/pm-setup

# 3. Registra il plugin nel marketplace del repo
mkdir -p .agents/plugins
cat > .agents/plugins/marketplace.json << 'JSON'
{
  "name": "pm-setup-local",
  "interface": {
    "displayName": "PM Setup"
  },
  "plugins": [
    {
      "name": "pm-setup",
      "source": {
        "source": "local",
        "path": "./plugins/pm-setup"
      },
      "policy": {
        "installation": "INSTALLED_BY_DEFAULT"
      },
      "category": "Productivity"
    }
  ]
}
JSON

# 4. Riavvia Codex
```

### 3. Configura i server MCP (opzionale)

Il plugin include gia' la configurazione MCP per ClickUp, Google Drive e Figma.
Se devi personalizzare i server, modifica il file `.mcp.json` nella directory del plugin.

Per configurare Google Drive, imposta le credenziali OAuth seguendo le istruzioni di
[@piotr-agier/google-drive-mcp](https://www.npmjs.com/package/@piotr-agier/google-drive-mcp).

Per Figma, imposta la variabile `FIGMA_OAUTH_TOKEN` nel tuo ambiente.

## Verifica installazione

Avvia Codex CLI:

```bash
codex
```

Verifica che il plugin sia attivo:

```
/plugins
```

Dovresti vedere `pm-setup` nella lista. Verifica i server MCP:

```
/mcp
```

## Skill disponibili

Le skill sono accessibili tramite `/skills` oppure invocando il plugin con `@pm-setup`.

| Skill | Descrizione |
|---|---|
| `pm-flow` | Flusso completo: documento -> task ClickUp |
| `pm-intake` | Analisi documento -> Discovery Brief |
| `pm-transcript` | Analisi trascrizioni Google Meet da Drive |
| `pm-figma` | Analisi design Figma -> task per riprodurre il layout |
| `pm-structure` | Brief -> gerarchia Epic/Story/Task |
| `pm-refine` | Validazione INVEST + criteri di accettazione |
| `pm-review` | Revisione e approvazione |
| `pm-publish` | Pubblicazione su ClickUp |

## Come iniziare

### Da un documento di requisiti

```
@pm-setup esegui pm-flow con il file requisiti.md
```

### Da una trascrizione di meeting

```
@pm-setup esegui pm-transcript
```

### Da un design Figma

```
@pm-setup esegui pm-figma con URL https://www.figma.com/design/abc123/My-Project?node-id=1-2
```

## Struttura plugin

```
pm-setup/
├── .codex-plugin/
│   └── plugin.json            # Manifest plugin Codex
├── .mcp.json                  # Configurazione MCP servers
├── skills/
│   ├── clickup/SKILL.md
│   ├── pm-flow/SKILL.md
│   ├── pm-intake/SKILL.md
│   ├── pm-transcript/SKILL.md
│   ├── pm-figma/SKILL.md
│   ├── pm-structure/SKILL.md
│   ├── pm-refine/SKILL.md
│   ├── pm-review/SKILL.md
│   └── pm-publish/SKILL.md
├── AGENTS.md                  # Istruzioni di sistema
└── PM-CONSTITUTION.md         # Regole qualita' task
```

## Aggiornamento

Per aggiornare il plugin, riesegui i comandi di download del punto 2
(sovrascrivendo la directory del plugin), poi riavvia Codex.

---
*Generato da: ai-base-setup v1.0.0*
