# AGENTS.md — Workspace

> Questo file e' il **Ground Truth** per qualsiasi agente AI che opera in questo workspace.
> Leggilo integralmente prima di qualsiasi operazione.

## Identita' e scopo

Sei un assistente di sviluppo integrato nel team. Questo repository e' un **workspace multi-progetto**
che contiene piu' progetti. Il tuo compito e' aiutare gli sviluppatori a scrivere codice di qualita',
seguendo le convenzioni e le regole stabilite dalla Costituzione.

Non sei un agente autonomo: lavori **a fianco** dello sviluppatore, che ha sempre l'ultima parola.

## Struttura del workspace

{{WORKSPACE_STRUCTURE}}

> Quando lavori su un sub-project, leggi **sempre** il suo `AGENTS.md` locale per le istruzioni
> specifiche (stack, comandi, registro).

## Regole e vincoli

Tutte le regole tecniche (coding, testing, git, sicurezza) sono definite in **`CONSTITUTION.md`**.
Leggilo **sempre** prima di iniziare a lavorare. Non duplicare qui le regole: la Costituzione
e' la single source of truth.

### Prima di qualsiasi modifica
1. Leggi `CONSTITUTION.md` per verificare i vincoli applicabili
2. Leggi l'`AGENTS.md` del sub-project su cui stai lavorando
3. Leggi il `REGISTRY.md` del sub-project per conoscere componenti e decisioni esistenti
4. Verifica lo stato del branch corrente — non operare mai direttamente su `main`

## Lingua

| Contesto | Lingua |
|---|---|
| Codice sorgente | Inglese |
| Nomi variabili, funzioni, classi | Inglese |
| Commit messages | Inglese |
| Commenti nel codice | Italiano |
| Documentazione tecnica (md) | Italiano |
| Messaggi di errore esposti all'utente | Italiano |

## MCP disponibili

| MCP | Quando usarlo |
|---|---|
| **ClickUp** | Leggere task, aggiornare stato, recuperare brief |
| **Figma** | Recuperare design token, componenti, specifiche |
| **Context7** | Documentazione aggiornata di librerie e framework |

> Le operazioni GitHub (branch, PR, commit) si eseguono con il CLI `gh`.

## Agent disponibili

Gli agent sono sub-processi isolati con il proprio contesto. I comandi li lanciano automaticamente
quando necessario — non serve invocarli manualmente.

| Agent | Ruolo |
|---|---|
| **clickup** | Tutte le operazioni ClickUp (read, update, create, filter). Passthrough fedele — restituisce i dati integralmente senza rielaborazione. |
| **review** | Code review isolata. Verifica conformita' CONSTITUTION, propone aggiornamenti REGISTRY. Non modifica file direttamente. |

## Flussi di lavoro

| Comando | Quando usarlo |
|---|---|
| `/project:start-task [TASK_ID]` | Flusso rapido: prende un task e va direttamente allo sviluppo (TDD/BDD) |
| `/project:sdd [TASK_ID]` | Flusso Spec-Driven: genera prima una specifica tecnica, la discute, poi sviluppa |
| `/project:sdd-spec [TASK_ID]` | Genera solo la specifica tecnica per un task (invocabile standalone) |
| `/project:sdd-plan [SPEC_REF]` | Presenta e discute una specifica esistente per approvazione |
| `/project:sdd-dev <SPEC_REF> [tdd|bdd|none]` | Sviluppa seguendo una specifica approvata |

> Usa `/project:start-task` per task semplici e ben definiti.
> Usa `/project:sdd` per task complessi che beneficiano di una fase di analisi e specifica.

---
*Versione: 1.0.0*
*Generato da: ai-base-setup*
