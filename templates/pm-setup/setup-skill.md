---
name: setup
description: Setup AI-Native per Project Manager. Configura MCP (ClickUp, Figma) e installa la governance per la creazione di task strutturati.
model: sonnet
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# PM Setup

Skill per configurare il workflow AI-Native per Project Manager.
Le risorse sono bundled nel plugin — nessun download remoto necessario.

---

## Risorse locali

Tutti i file template sono disponibili in:
```
${CLAUDE_SKILL_DIR}/templates/
```

Contiene: AGENTS.template.md, PM-CONSTITUTION.md, settings.json, .gitignore

---

## Strategia di lettura

I file si dividono in due categorie:

- **Verbatim**: letti dal plugin e scritti direttamente nella destinazione finale (PM-CONSTITUTION, settings, .gitignore).
- **Con trasformazione**: letti dal plugin, trasformati in memoria, poi scritti (AGENTS.template.md → AGENTS.md).

**IMPORTANTE**: Skills e agents NON vengono installati nel progetto. Sono forniti dal plugin stesso e disponibili automaticamente.

---

## Procedura completa

Esegui i passi seguenti **nell'ordine indicato**. Non saltare nessun passo.

### Passo 1 — Rileva la modalita'

Analizza il progetto corrente per determinare la modalita' operativa:

1. **UPDATE** — Se esistono gia' `PM-CONSTITUTION.md` E `AGENTS.md` nella root del progetto.
   Chiedi al PM: "Il setup e' gia' stato eseguito. Vuoi aggiornare i file?"
   Se risponde no, fermati.

2. **FRESH** — In tutti gli altri casi. Il setup non e' stato ancora eseguito.

Comunica la modalita' rilevata al PM prima di procedere.

---

### Passo 2 — Installare le risorse (verbatim)

Leggi i file dal plugin e scrivili nella root del progetto.

#### 2.1 PM-CONSTITUTION.md

Leggi `${CLAUDE_SKILL_DIR}/templates/PM-CONSTITUTION.md`.

**Conflict detection**: se esiste gia' `PM-CONSTITUTION.md` nella root:
- In modalita' UPDATE: sovrascrivi (e' l'intento dell'aggiornamento)
- In modalita' FRESH: scrivi direttamente

Scrivi in: `./PM-CONSTITUTION.md`

#### 2.2 settings.json

Leggi `${CLAUDE_SKILL_DIR}/templates/settings.json`.

**Conflict detection**: se esiste gia' `.claude/settings.json`:
- In modalita' UPDATE: sovrascrivi
- In modalita' FRESH: crea la directory `.claude/` se non esiste, poi scrivi

Scrivi in: `./.claude/settings.json`

#### 2.3 .gitignore

Leggi `${CLAUDE_SKILL_DIR}/templates/.gitignore`.

**Conflict detection**: se esiste gia' `.gitignore`:
- Leggi il contenuto esistente
- Aggiungi SOLO le righe mancanti (non duplicare)

Scrivi/aggiorna in: `./.gitignore`

---

### Passo 3 — Generare AGENTS.md

Leggi `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md`.

Non ci sono placeholder da sostituire (a differenza del dev-setup che ha {{STACK_DESCRIPTION}}).
Scrivi direttamente come `AGENTS.md`.

Crea anche `CLAUDE.md` con il seguente contenuto:
```
@AGENTS.md
```

---

### Passo 4 — Configurare MCP servers

#### 4.1 ClickUp (obbligatorio)

Verifica se il MCP ClickUp e' gia' configurato (scope utente).

Se NON configurato:
```bash
claude mcp add clickup --transport url https://mcp.clickup.com/mcp -s user
```

Informa il PM: "Ho configurato il server MCP ClickUp. Al primo utilizzo ti verra' chiesto di autorizzare l'accesso."

#### 4.2 Google Drive (consigliato)

Chiedi al PM: "Vuoi configurare Google Drive per poter analizzare le trascrizioni dei meeting direttamente?"

Se si':
```bash
npx -y @anthropic-ai/mcp-server-google-drive auth
claude mcp add gdrive -- npx -y @anthropic-ai/mcp-server-google-drive -s user
```

Informa il PM: "Ho configurato Google Drive. Al primo utilizzo ti verra' chiesto di autorizzare l'accesso al tuo account Google."

> **Nota**: il pacchetto npm potrebbe variare. Se `@anthropic-ai/mcp-server-google-drive`
> non e' disponibile, alternative valide sono:
> - `@modelcontextprotocol/server-gdrive`
> - `@a-bonus/google-docs-mcp`
> Verifica quale e' disponibile con `npx -y <pacchetto> --help`

#### 4.3 Figma (opzionale)

Chiedi al PM: "Vuoi configurare anche Figma per poter analizzare i design in futuro?"

Se si':
```bash
claude mcp add figma --transport http https://mcp.figma.com/mcp -s user
```

---

### Passo 5 — Riepilogo

Mostra un riepilogo al PM:

```
Setup PM completato!

File installati:
- PM-CONSTITUTION.md — regole di qualita' per i task
- AGENTS.md — istruzioni per l'agente AI
- CLAUDE.md — riferimento ad AGENTS.md
- .claude/settings.json — permessi e configurazione
- .gitignore — aggiornato

MCP configurati:
- ClickUp: <si/no>
- Google Drive: <si/no>
- Figma: <si/no>

Comandi disponibili:
- /project:pm-flow [PATH]   — flusso completo: documento → task ClickUp
- /project:pm-intake [PATH] — analisi documento → Discovery Brief
- /project:pm-transcript     — analisi trascrizioni Google Meet
- /project:pm-structure      — brief → gerarchia Epic/Story/Task
- /project:pm-refine         — validazione INVEST + Acceptance Criteria
- /project:pm-review         — revisione e approvazione
- /project:pm-publish        — pubblicazione su ClickUp

Per iniziare:
- Con un documento: esegui /project:pm-flow con il path del file
- Con un meeting: esegui /project:pm-transcript per scegliere una trascrizione
```
