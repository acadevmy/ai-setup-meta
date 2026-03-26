---
name: render-template
description: Renderizza file con variabili da .env.local o input fornito per generare file personalizzati
user-invocable: false
disable-model-invocation: false
---

# Skill: Render Template

Renderizza file con variabili da `.env.local` o da input fornito.
Utile per generare file personalizzati per ogni sviluppatore durante il setup.

## Sintassi variabili nei template
I file template usano la sintassi `{{VARIABILE}}` per i placeholder:

```markdown
# AGENTS.md — {{PROJECT_NAME}}

Stack selezionato: {{STACK_PROFILE}}
Sviluppatore: {{DEVELOPER_NAME}}
```

## Come renderizzare un file

1. Leggi il file template (es. `templates/dev-setup-template/AGENTS.md`)
2. Identifica tutti i placeholder `{{VARIABILE}}`
3. Sostituisci con i valori forniti in input o da `.env.local`
4. Scrivi il file renderizzato nella destinazione

## Variabili standard disponibili

| Variabile | Provenienza | Descrizione |
|---|---|---|
| `{{PROJECT_NAME}}` | Input utente | Nome del progetto |
| `{{STACK_PROFILE}}` | Input utente | `web-frontend` / `backend-node` / `mobile` |
| `{{DEVELOPER_NAME}}` | Input utente | Nome dello sviluppatore |
| `{{GITHUB_ORG}}` | `.env.local` | Organizzazione GitHub |
| `{{TEMPLATE_VERSION}}` | `.env.local` | Versione del template |
| `{{SETUP_DATE}}` | Automatico | Data di esecuzione (YYYY-MM-DD) |

## Regole
- Non sostituire mai variabili in file binari
- Verificare che tutte le variabili `{{...}}` siano state sostituite prima di scrivere
- Segnalare variabili mancanti invece di scrivere file con placeholder non risolti
- I file `.example` **non** vengono renderizzati — sono template sorgente
