# PM Setup — Guida installazione Gemini CLI

Guida per configurare il workflow AI-Native per Project Manager su **Gemini CLI**.

## Prerequisiti

- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installato
- [Node.js](https://nodejs.org/) 18+ (per i server MCP)
- Account ClickUp con accesso al workspace del team
- (Consigliato) Account Google per accedere alle trascrizioni dei meeting

## Installazione

### 1. Scarica e installa i file

Esegui questi comandi nella directory dove vuoi usare il setup
(la tua home `~` per un setup globale, o la root di un progetto specifico):

```bash
# Crea le directory di configurazione Gemini
mkdir -p .gemini/commands/pm

# Scarica i file principali
curl -sL "https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini/GEMINI.md" -o .gemini/GEMINI.md
curl -sL "https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini/PM-CONSTITUTION.md" -o PM-CONSTITUTION.md

# Scarica i comandi slash
for cmd in pm-flow pm-intake pm-transcript pm-figma pm-structure pm-refine pm-review pm-publish; do
  curl -sL "https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini/commands/pm/$cmd.toml" -o ".gemini/commands/pm/$cmd.toml"
done
```

In alternativa, puoi scaricare i file dalla [pagina release](https://github.com/acadevmy/ai-setup-meta/releases)
e copiarli manualmente.

### 2. Configura i server MCP

Apri (o crea) il file `.gemini/settings.json` e aggiungi i server MCP:

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

Al primo utilizzo di ClickUp, Gemini ti chiedera' di autorizzare l'accesso al tuo workspace.

### 3. (Consigliato) Installa l'estensione Google Workspace

L'estensione Google Workspace permette di accedere a Google Drive, Docs, Calendar e Gmail
direttamente da Gemini CLI. L'autenticazione avviene automaticamente via browser.

```bash
gemini extensions install https://github.com/gemini-cli-extensions/workspace
```

Quando richiesto, conferma con `Y`. Al primo utilizzo, il browser si aprira'
per autorizzare l'accesso al tuo account Google.

> **Nota**: l'estensione gira localmente sulla tua macchina e comunica
> direttamente con le API Google usando le tue credenziali OAuth.
> Nessuna API key o configurazione manuale necessaria.

Per verificare che l'estensione sia installata:
```
gemini /mcp list
```

Dovresti vedere `google-workspace` nella lista dei server attivi.

### 4. (Opzionale) Configura Figma

Per analizzare i design da Figma, aggiungi il server MCP nel tuo `.gemini/settings.json`:

```json
{
  "mcpServers": {
    "clickup": {
      "trust": true,
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.clickup.com/mcp"]
    },
    "figma": {
      "trust": true,
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.figma.com/mcp"]
    }
  }
}
```

## Verifica installazione

Avvia Gemini CLI nella directory del progetto:

```bash
gemini
```

Verifica che i server MCP e le estensioni siano connessi:

```
/mcp
```

Dovresti vedere `clickup` (e `google-workspace`, `figma` se configurati) nella lista dei server attivi.

## Comandi disponibili

| Comando | Descrizione |
|---|---|
| `/pm:pm-flow` | Flusso completo: documento → task ClickUp |
| `/pm:pm-intake <path>` | Analisi documento → Discovery Brief |
| `/pm:pm-transcript` | Analisi trascrizioni Google Meet da Drive |
| `/pm:pm-figma <URL>` | Analisi design Figma → task per riprodurre il layout |
| `/pm:pm-structure` | Brief → gerarchia Epic/Story/Task |
| `/pm:pm-refine` | Validazione INVEST + criteri di accettazione |
| `/pm:pm-review` | Revisione e approvazione |
| `/pm:pm-publish` | Pubblicazione su ClickUp |

I comandi accettano argomenti dopo lo slash command (es. `/pm:pm-figma https://figma.com/...`).

Per ricaricare i comandi dopo un aggiornamento:
```
/commands reload
```

## Come iniziare

### Da un documento di requisiti

```
/pm:pm-flow requisiti.md
```

### Da una trascrizione di meeting

```
/pm:pm-transcript
```

### Da un design Figma

```
/pm:pm-figma https://www.figma.com/design/abc123/My-Project?node-id=1-2
```

### Flusso guidato (scegli l'input durante l'esecuzione)

```
/pm:pm-flow
```

## Struttura file

```
progetto/
├── .gemini/
│   ├── GEMINI.md              # Istruzioni per Gemini (non modificare)
│   ├── settings.json          # Configurazione MCP servers
│   └── commands/
│       └── pm/
│           ├── pm-flow.toml       # /pm:pm-flow
│           ├── pm-intake.toml     # /pm:pm-intake
│           ├── pm-transcript.toml # /pm:pm-transcript
│           ├── pm-figma.toml      # /pm:pm-figma
│           ├── pm-structure.toml  # /pm:pm-structure
│           ├── pm-refine.toml     # /pm:pm-refine
│           ├── pm-review.toml     # /pm:pm-review
│           └── pm-publish.toml    # /pm:pm-publish
└── PM-CONSTITUTION.md         # Regole qualita' task
```

## Aggiornamento

Per aggiornare il setup, riesegui i comandi di download del punto 1.
Dopo l'aggiornamento dei comandi, esegui `/commands reload` in Gemini CLI.

---
*Generato da: ai-base-setup v1.0.0*
