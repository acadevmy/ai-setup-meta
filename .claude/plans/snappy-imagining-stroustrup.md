# Piano: Flusso Spec-Driven Development (SDD)

## Contesto

Il progetto dispone gia' di un flusso rapido (`start-task`) che prende un task ClickUp e va direttamente a scrivere codice con TDD/BDD. Per task complessi serve un flusso alternativo ispirato a **Spec-Driven Development** (spec-kit): prima si produce una **specifica tecnica** e un **piano di implementazione**, li si discute con lo sviluppatore, e solo dopo l'approvazione si procede allo sviluppo. Questo riduce rework e allinea l'AI con l'intento dello sviluppatore.

**Differenza chiave rispetto a spec-kit**: non includiamo la fase PRD (gia' gestita dal PM su ClickUp). Il flusso parte dal task ClickUp e produce direttamente la specifica tecnica.

---

## Architettura: 4 skill composabili

| Skill | Dir | Model | Invocabile | Ruolo |
|-------|-----|-------|------------|-------|
| `sdd` | `sdd/` | opus | si | Orchestratore — esegue il flusso completo |
| `sdd-spec` | `sdd-spec/` | opus | si | Genera la specifica tecnica + piano di implementazione |
| `sdd-plan` | `sdd-plan/` | sonnet | si | Presenta la spec per discussione/approvazione |
| `sdd-dev` | `sdd-dev/` | opus | si | Esegue lo sviluppo seguendo la spec approvata |

Lo sviluppatore puo' invocare ogni skill autonomamente (`/project:sdd-spec DE-123`) oppure usare `/project:sdd` per il flusso completo.

---

## Storage delle specifiche

Directory `.specs/` nella root del progetto (versionata con git):

```
.specs/
  DE-123-add-user-auth.md
  DE-456-payment-flow.md
```

### Formato spec

```markdown
# Spec: <Titolo Task> [<customId>]

> Status: draft | approved | implemented
> Task: <ClickUp URL>
> Branch: <branch name>
> Created: <data>
> Approved: <data o "pending">

## Contesto
<Perche' questo task esiste, background>

## Requisiti
<Estratti dalla description del task ClickUp, come bullet points>

## Decisioni tecniche
<Approccio, pattern, librerie scelte>

## Impatto
- **File da creare**: <lista>
- **File da modificare**: <lista>
- **Dipendenze**: <nuove dipendenze, se presenti>

## Piano di implementazione
1. Step 1 — descrizione
2. Step 2 — descrizione
...

## Strategia di test
<Cosa testare, approccio TDD/BDD, test case chiave>

## Note
<Rischi, domande aperte, contesto aggiuntivo>
```

---

## Dettaglio skill per skill

### 1. `sdd` — Orchestratore

**File**: `templates/dev-setup/.claude/skills/sdd/SKILL.md`

**Flusso completo**:

1. **Selezione task**
   - Con `TASK_ID`: fetch diretto via clickup agent (INTENT: `read`)
   - Senza `TASK_ID`: fetch 5 task in stato SPRINT via clickup agent (INTENT: `filter`, PARAMS: `list_id, status: SPRINT`), ordinati per priorita', presentati come lista numerata. Lo sviluppatore sceglie, poi fetch completo del task scelto

2. **Branch + status update**
   - Crea branch `<tipo>/<customId>-<slug>` (stessa logica di `start-task`)
   - Aggiorna stato ClickUp → IN PROGRESS

3. **Mostra brief** — riepilogo task (come `start-task` step 4)

4. **Intervista lo sviluppatore** — fai delle domande allo sviluppatore per capire meglio il task e raccogliere informazioni utili per la spec o per segnalare eventuali criticità.

5. **Genera spec** — invoca `/project:sdd-spec` passando il contesto del task

6. **Revisione spec** — invoca `/project:sdd-plan` per discussione e approvazione

6. **Scelta metodologia** — chiede allo sviluppatore:
   - TDD (backend/logica)
   - BDD (frontend/UI)
   - Nessuna (sviluppo diretto)

7. **Sviluppo** — invoca `/project:sdd-dev` passando spec path + metodologia

8. **Chiusura** (identico a `start-task` step 6):
   - Commit con Conventional Commits + customId
   - Esegui `simplify`
   - Esegui `/project:review`
   - Riepilogo allo sviluppatore di quanto implementato
   - Attendi OK dello sviluppatore
   - Push branch + apri PR (con link alla spec nel body)
   - Aggiorna ClickUp → CODE REVIEW (fallback: IN REVIEW)
   - La review aggiorna gia' REGISTRY.md automaticamente

---

### 2. `sdd-spec` — Generatore specifica tecnica

**File**: `templates/dev-setup/.claude/skills/sdd-spec/SKILL.md`

**Input**: `$ARGUMENTS` — task ID ClickUp, oppure contesto gia' disponibile dall'orchestratore

**Procedura**:
1. Se invocata standalone con task ID → fetch task via clickup agent
2. Leggi `CONSTITUTION.md` per vincoli applicabili
3. Leggi `REGISTRY.md` per componenti e pattern esistenti
4. Analizza la codebase per individuare file rilevanti
5. Intervista lo sviluppatore per capire meglio il task e raccogliere informazioni utili per la spec
6. Crea `.specs/` se non esiste
7. Genera il documento spec in `.specs/<customId>-<slug>.md` con status `draft`
8. Mostra la spec completa allo sviluppatore

---

### 3. `sdd-plan` — Revisione e approvazione

**File**: `templates/dev-setup/.claude/skills/sdd-plan/SKILL.md`

**Input**: `$ARGUMENTS` — path spec o customId

**Procedura**:
1. Localizza la spec (da path, da customId in `.specs/`, o elenca disponibili)
2. Presenta la spec con formattazione chiara
3. Loop di discussione:
   - **Approva** → aggiorna status a `approved`, data approvazione
   - **Modifica** → applica modifiche, ri-presenta
   - **Rigenera** → rigenera la spec da zero
4. Conferma approvazione con path file

---

### 4. `sdd-dev` — Esecuzione sviluppo

**File**: `templates/dev-setup/.claude/skills/sdd-dev/SKILL.md`

**Input**: `$ARGUMENTS` — path spec o customId + metodologia (tdd/bdd/none)

**Procedura**:
1. Carica la spec da `.specs/`. Se status != `approved`, avvisa e chiedi conferma
2. Parsa "Piano di implementazione" dalla spec
3. Crea task breakdown interno (checklist), presenta allo sviluppatore
4. Per ogni step del piano:
   - Se TDD: segui procedura Red/Green/Refactor (stessa logica di `/project:tdd`)
   - Se BDD: segui procedura Gherkin (stessa logica di `/project:bdd`)
   - Se nessuna: implementa direttamente
   - Dopo ogni step: esegui test + linter
5. A completamento: esegui `simplify`
6. Riepilogo di quanto implementato

---

## File da creare/modificare

### Nuovi file (4 skill)
1. `templates/dev-setup/.claude/skills/sdd/SKILL.md`
2. `templates/dev-setup/.claude/skills/sdd-spec/SKILL.md`
3. `templates/dev-setup/.claude/skills/sdd-plan/SKILL.md`
4. `templates/dev-setup/.claude/skills/sdd-dev/SKILL.md`

### File da modificare
5. **`templates/dev-setup/manifest.json`** — aggiungere le 4 skill a `template_skills`
6. **`templates/dev-setup/dev-setup-agent.md`** — aggiungere directory sdd* in step 6.1 (mkdir) e menzionare sdd nelle skills installate (step 6.3)
7. **`templates/dev-setup/AGENT.template.md`** — menzionare `/project:sdd` come alternativa a `/project:start-task`

### File da NON modificare
- `shared/agents/clickup.md` — supporta gia' tutto il necessario (filter + read + update)
- `start-task`, `tdd`, `bdd`, `review` — rimangono invariati
- `CONSTITUTION.md` — nessuna modifica necessaria

---

## Sequenza di implementazione

1. Creare `sdd-spec/SKILL.md` (standalone, nessuna dipendenza)
2. Creare `sdd-plan/SKILL.md` (dipende dal formato spec definito in 1)
3. Creare `sdd-dev/SKILL.md` (dipende dal formato spec definito in 1)
4. Creare `sdd/SKILL.md` (dipende da 1, 2, 3)
5. Aggiornare `manifest.json`
6. Aggiornare `dev-setup-agent.md`
7. Aggiornare `AGENT.template.md`

---

## Verifica

- [ ] Ogni skill ha frontmatter corretto (name, description, model, user-invocable, disable-model-invocation)
- [ ] Le skill seguono i pattern esistenti (lingua italiana, delegazione a clickup agent, formato output)
- [ ] `sdd-spec` puo' essere invocata standalone con un task ID
- [ ] `sdd-plan` puo' essere invocata standalone con un customId
- [ ] `sdd-dev` puo' essere invocata standalone con path spec
- [ ] `sdd` orchestra correttamente tutte le fasi
- [ ] `manifest.json` dichiara le 4 nuove skill
- [ ] `dev-setup-agent.md` crea le directory e installa le skill
- [ ] Nessuna modifica ai file condivisi/shared (clickup agent, review, ecc.)
- [ ] Eseguire `/project:validate-template` per validare coerenza del template
