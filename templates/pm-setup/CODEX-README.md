# PM Setup — Guida installazione OpenAI Codex CLI

Guida per configurare il workflow AI-Native per Project Manager su **OpenAI Codex CLI**.

## Prerequisiti

- [OpenAI Codex CLI](https://github.com/openai/codex) installato
- [Node.js](https://nodejs.org/) 18+ (per i server MCP)
- Account ClickUp con accesso al workspace del team
- (Consigliato) Account Google per accedere alle trascrizioni dei meeting

## Installazione

### 1. Installa le skill (globali — disponibili in tutti i progetti)

```bash
# Scarica e installa le skill nella directory globale di Codex
mkdir -p ~/.agents/skills
curl -sL "https://github.com/acadevmy/ai-setup-meta/archive/refs/heads/main.tar.gz" | \
  tar -xz -C /tmp "ai-setup-meta-main/dist/pm-setup/codex/skills"

# Copia ogni skill nella directory di discovery globale
for skill in /tmp/ai-setup-meta-main/dist/pm-setup/codex/skills/*/; do
  cp -R "$skill" ~/.agents/skills/
done

# Copia AGENTS.md e PM-CONSTITUTION.md nella home (setup globale)
cp /tmp/ai-setup-meta-main/dist/pm-setup/codex/AGENTS.md ~/.agents/AGENTS.md
cp /tmp/ai-setup-meta-main/dist/pm-setup/codex/PM-CONSTITUTION.md ~/.agents/PM-CONSTITUTION.md

# Pulizia
rm -rf /tmp/ai-setup-meta-main
```

### 2. Configura i server MCP

Aggiungi i server MCP nel file `~/.codex/config.toml`:

```toml
# ClickUp — gestione task
[mcp_servers.clickup]
command = "npx"
args = ["-y", "mcp-remote", "https://mcp.clickup.com/mcp"]
```

Al primo utilizzo di ClickUp, Codex ti chiedera' di autorizzare l'accesso al tuo workspace.

### 3. (Opzionale) Configura Google Drive

Per accedere alle trascrizioni Google Meet, aggiungi in `~/.codex/config.toml`:

```toml
[mcp_servers.gdrive]
command = "npx"
args = ["@piotr-agier/google-drive-mcp"]

[mcp_servers.gdrive.env]
GOOGLE_DRIVE_OAUTH_CREDENTIALS = "${GOOGLE_DRIVE_OAUTH_CREDENTIALS}"
```

Configura le credenziali OAuth seguendo le istruzioni di
[@piotr-agier/google-drive-mcp](https://www.npmjs.com/package/@piotr-agier/google-drive-mcp).

### 4. (Opzionale) Configura Figma

Per analizzare i design da Figma, aggiungi in `~/.codex/config.toml`:

```toml
[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
bearer_token_env_var = "FIGMA_OAUTH_TOKEN"
```

## Verifica installazione

Avvia Codex CLI:

```bash
codex
```

Verifica che le skill siano caricate:

```
/skills
```

Dovresti vedere le skill `pm-flow`, `pm-intake`, `pm-transcript`, etc. nella lista.

Verifica i server MCP:

```
/mcp
```

## Skill disponibili

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

## Struttura dei file installati

```
~/.agents/
├── AGENTS.md                      # Istruzioni di sistema
├── PM-CONSTITUTION.md             # Regole qualita' task
└── skills/
    ├── clickup/SKILL.md
    ├── pm-flow/SKILL.md
    ├── pm-intake/SKILL.md
    ├── pm-transcript/SKILL.md
    ├── pm-figma/SKILL.md
    ├── pm-structure/SKILL.md
    ├── pm-refine/SKILL.md
    ├── pm-review/SKILL.md
    └── pm-publish/SKILL.md

~/.codex/
└── config.toml                    # Configurazione MCP servers
```

## Aggiornamento

Per aggiornare le skill, riesegui i comandi di download del punto 1
(sovrascrivendo le skill esistenti), poi riavvia Codex.

---
*Generato da: ai-base-setup v1.0.0*
