# PM-CONSTITUTION.md — Standard qualita' task

> Questo documento definisce le regole di qualita' per la creazione di task ClickUp.
> Ogni task generato dall'agente AI deve rispettare queste regole senza eccezioni.
> Modifiche a questo documento richiedono approvazione esplicita.

---

## I. Tipi di task e formati obbligatori

### 1. Epic (tipo custom ClickUp: "Epic")

Una Epic rappresenta un modulo o una funzionalita' nel suo complesso.

**Formato obbligatorio:**
- **Titolo**: sostantivo che descrive il modulo/funzionalita' (es. "User Authentication", "Product Catalog")
- **Descrizione**: panoramica ad alto livello che spiega COSA fa il modulo e PERCHE' esiste
- Ogni Epic deve contenere almeno una User Story

### 2. User Story (tipo custom ClickUp: "User Story")

Una User Story descrive una funzionalita' dal punto di vista dell'utente.

**Formato obbligatorio:**
```
As a <user role>,
I want to <goal to be accomplished>
so that I can <reason of the goal>.
```

**Acceptance Criteria obbligatori (formato Gherkin):**
```
Scenario: <scenario description>
Given <the beginning state of the scenario>
When <specific action that the user makes>
Then <the outcome of the action in "When">
And <used to continue any of three previous statements>
```

Ogni User Story deve avere almeno uno scenario Gherkin.

### 3. Task (tipo standard ClickUp)

Un Task descrive un'unita' di lavoro tecnica o operativa.

**Formato obbligatorio:**
```
Task Outcome
<State the outcome clearly>

Additional Notes
<List any notes that support the initial task>

Assumptions
<List assumptions that require validation>

Acceptance Criteria
I know this is true when...
<Describe what a completed task looks like>

Risks
<Potential risks and who could mitigate them>
```

---

## II. Criteri INVEST per le User Story

Ogni User Story deve soddisfare i criteri INVEST:

| Criterio | Significato | Verifica |
|---|---|---|
| **I**ndependent | Puo' essere sviluppata e consegnata senza dipendere da altre story nello stesso sprint | Se dipende da un'altra story, la dipendenza deve essere esplicitata |
| **N**egotiable | Non prescrive HOW (come implementare), solo WHAT (cosa ottenere) | La story non menziona tecnologie specifiche nel corpo principale |
| **V**aluable | Porta valore misurabile all'utente o al business | La clausola "so that" esprime un valore concreto |
| **E**stimable | Contiene informazioni sufficienti per stimare lo sforzo | Acceptance Criteria sono specifici e verificabili |
| **S**mall | Completabile in uno sprint | Se troppo grande, va suddivisa in story piu' piccole |
| **T**estable | Ha criteri di accettazione che permettono di scrivere test | Almeno uno scenario Gherkin per story |

---

## III. Gerarchia e relazioni

1. Ogni **User Story** deve appartenere a un'**Epic** (relazione padre-figlio su ClickUp)
2. Ogni **Task** deve appartenere a una **User Story** (relazione padre-figlio)
3. Non sono ammessi elementi orfani (story senza epic, task senza story)
4. Le dipendenze tra task devono essere dichiarate esplicitamente su ClickUp

---

## IV. Naming conventions

| Tipo | Convenzione | Esempio |
|---|---|---|
| Epic | Sostantivo (modulo/funzionalita') | "User Authentication" |
| User Story | Formato "As a..." implicito nel titolo breve | "Login with email and password" |
| Task | Verbo + deliverable | "Implement auth endpoint" |

---

## V. Lingua

| Elemento | Lingua |
|---|---|
| Titoli task | Inglese |
| Descrizioni task | Inglese |
| Acceptance Criteria | Inglese |
| Comunicazione con il PM | Italiano |

---

## VI. Note tecniche (bridging)

L'agente AI puo' aggiungere note tecniche nei task destinate ai developer.
Queste note:
- Devono essere marcate con il prefisso `[AI-suggested]`
- Sono suggerimenti, non prescrizioni — i developer possono ignorarle
- Non devono essere mostrate al PM durante la review (sono nel campo Additional Notes)
- Servono a facilitare il passaggio PM → Developer

---

## VII. Tracciabilita'

1. Ogni task creato dall'agente deve includere il tag `pm-created`
2. La descrizione deve iniziare con il marker `<!-- pm-setup:v1.0 -->` per la tracciabilita'
3. I task complessi devono avere il tag `needs-sdd` per segnalare ai developer che richiedono il flusso Spec-Driven Development

---

*Versione: 1.0.0*
