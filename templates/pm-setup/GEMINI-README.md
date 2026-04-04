# PM Setup — Guida installazione Gemini CLI

Guida per configurare il workflow AI-Native per Project Manager su **Gemini CLI**.

## Prerequisiti

- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installato
- [Node.js](https://nodejs.org/) 18+ (per i server MCP)
- Account ClickUp con accesso al workspace del team
- (Opzionale) Credenziali Google Cloud per Google Drive

## Installazione

### 1. Copia i file nella directory del progetto

Copia i file dalla cartella `gemini/` nella root del tuo progetto (o nella tua home se vuoi un setup globale):

```bash
# Nella root del progetto
cp gemini/GEMINI.md .gemini/GEMINI.md
cp gemini/PM-CONSTITUTION.md ./PM-CONSTITUTION.md
```

Se la directory `.gemini/` non esiste:
```bash
mkdir -p .gemini
```

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

### 3. (Opzionale) Configura Google Drive

Se vuoi analizzare le trascrizioni dei meeting Google Meet direttamente dal Drive:

#### 3.1 Crea le credenziali OAuth

1. Vai su [Google Cloud Console](https://console.cloud.google.com/)
2. Crea un nuovo progetto (o usa uno esistente)
3. Abilita le API: **Google Drive**, **Google Docs**, **Google Calendar**
4. Vai su "Credenziali" → "Crea credenziali" → "ID client OAuth"
5. Tipo applicazione: **App desktop**
6. Scarica il file JSON e salvalo come `gcp-oauth.keys.json`

#### 3.2 Aggiungi il server MCP

Aggiungi questa voce nel tuo `.gemini/settings.json`:

```json
{
  "mcpServers": {
    "clickup": {
      "trust": true,
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.clickup.com/mcp"]
    },
    "gdrive": {
      "command": "npx",
      "args": ["@piotr-agier/google-drive-mcp"],
      "env": {
        "GOOGLE_DRIVE_OAUTH_CREDENTIALS": "/path/to/gcp-oauth.keys.json"
      }
    }
  }
}
```

Sostituisci `/path/to/gcp-oauth.keys.json` con il path reale del file scaricato.

Al primo utilizzo, il browser si aprira' per autorizzare l'accesso al tuo Google Drive.

### 4. (Opzionale) Configura Figma

Per analizzare i design da Figma in futuro:

```json
{
  "mcpServers": {
    "clickup": { "..." },
    "gdrive": { "..." },
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

Verifica che i server MCP siano connessi:

```
/mcp
```

Dovresti vedere `clickup` (e `gdrive`, `figma` se configurati) nella lista dei server attivi.

## Comandi disponibili

| Comando | Descrizione |
|---|---|
| `Esegui pm-flow` | Flusso completo: documento → task ClickUp |
| `Esegui pm-intake con <path>` | Analisi documento → Discovery Brief |
| `Esegui pm-transcript` | Analisi trascrizioni Google Meet da Drive |
| `Esegui pm-structure` | Brief → gerarchia Epic/Story/Task |
| `Esegui pm-refine` | Validazione INVEST + Acceptance Criteria |
| `Esegui pm-review` | Revisione e approvazione |
| `Esegui pm-publish` | Pubblicazione su ClickUp |

> **Nota**: su Gemini CLI i comandi non sono invocabili con `/project:`.
> Chiedi a Gemini in linguaggio naturale di eseguire il workflow desiderato.
> Le istruzioni delle skill sono incluse nel file `GEMINI.md`.

## Come iniziare

### Da un documento di requisiti

```
Analizza il documento requisiti.md e crea i task su ClickUp per il progetto Alpha
```

### Da una trascrizione di meeting

```
Cerca le trascrizioni dei meeting recenti e analizza l'ultima per creare i task
```

### Senza documenti (intervista guidata)

```
Aiutami a creare i task per una nuova funzionalita'. Fammi delle domande per capire cosa serve.
```

## Struttura file

```
progetto/
├── .gemini/
│   ├── GEMINI.md          # Istruzioni per Gemini (non modificare)
│   └── settings.json      # Configurazione MCP servers
└── PM-CONSTITUTION.md     # Regole qualita' task
```

## Aggiornamento

Per aggiornare il setup, scarica la nuova versione dei file `GEMINI.md` e `PM-CONSTITUTION.md`
e sostituiscili nella directory del progetto.

---
*Generato da: ai-base-setup v1.0.0*
