# PM-CONSTITUTION.md — Standard qualita' task

> Questo documento definisce le regole di qualita' per la creazione di task ClickUp.
> Ogni task generato dall'agente AI deve rispettare queste regole senza eccezioni.
> Modifiche a questo documento richiedono approvazione esplicita.

---

## I. Tipi di task e formati obbligatori

### 1. Epic (tipo custom ClickUp: "Epic")

Una Epic rappresenta un modulo o una funzionalita' nel suo complesso.

**Formato obbligatorio:**
- **Titolo**: sostantivo che descrive il modulo/funzionalita' (es. "Gestione utenti", "Catalogo prodotti")
- **Descrizione** (segue il template ClickUp — titoli in inglese, contenuto in italiano):
```
Introduction
<Panoramica del modulo: cosa fa e perche' esiste, in italiano>

Product requirement
<Requisiti di prodotto: funzionalita' richieste, in italiano>

Technical requirement
<Requisiti tecnici: vincoli, integrazioni, prestazioni, in italiano>

Design requirement
<Requisiti di design: UX, UI, accessibilita', in italiano>
```
- Ogni Epic deve contenere almeno una User Story o un Task

### 2. User Story (tipo custom ClickUp: "User Story")

Una User Story descrive una funzionalita' dal punto di vista dell'utente.

**Formato obbligatorio (segue il template ClickUp — titoli in inglese, contenuto in italiano):**
```
User Story
As a <ruolo utente, in italiano>,
I want to <obiettivo da raggiungere, in italiano>
so that I can <motivazione dell'obiettivo, in italiano>.


Acceptance Criteria
Scenarios
[Descrizione dello scenario, in italiano]
Given <lo stato iniziale dello scenario, in italiano>
When <l'azione specifica dell'utente, in italiano>
Then <il risultato dell'azione, in italiano>
And <continuazione, in italiano>
```

Ogni User Story deve avere almeno uno scenario Gherkin.

### 3. Task (tipo standard ClickUp)

Un Task descrive un'unita' di lavoro tecnica o operativa.

**Formato obbligatorio (segue il template ClickUp — titoli in inglese, contenuto in italiano):**
```
Task Outcome
<Descrivi chiaramente il risultato, in italiano>

Additional Notes
<Elenca le note a supporto del task, in italiano>

Assumptions
<Elenca le assunzioni da validare, in italiano>

Acceptance Criteria
I know this is true when...
<Descrivi cosa si vedra' a task completato, in italiano>

Risks
<Rischi potenziali e chi potrebbe mitigarli, in italiano>
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

1. La gerarchia ha **massimo 1 livello di annidamento**: Epic → sotto-task
2. I sotto-task di un'Epic possono essere **User Story** o **Task**, mai entrambi annidati
3. **Mai creare** la struttura Epic → User Story → Task (3 livelli)
4. Non sono ammessi elementi orfani (sotto-task senza epic)
5. Le dipendenze tra task devono essere dichiarate esplicitamente su ClickUp

**Struttura corretta:**
```
Epic
├── User Story (sotto-task diretto dell'Epic)
├── User Story
├── Task (sotto-task diretto dell'Epic)
└── Task
```

**Struttura VIETATA:**
```
Epic
└── User Story
    └── Task    ← MAI! Massimo 1 livello
```

---

## IV. Naming conventions

| Tipo | Convenzione | Esempio |
|---|---|---|
| Epic | Sostantivo breve e descrittivo (modulo/funzionalita') | "Gestione utenti" |
| User Story | Prefisso `[Epic]` + nome funzionalita' | "[Gestione utenti] Login con email" |
| Task | Prefisso `[Epic]` + verbo + deliverable | "[Gestione utenti] Implementare endpoint autenticazione" |

### Regole di naming

1. **Epic**: titolo breve e descrittivo, massimo 3-4 parole. Deve identificare
   immediatamente il modulo o l'area funzionale (es. "Gestione utenti", "Catalogo prodotti",
   "Gestione ordini").

2. **Prefisso obbligatorio per sotto-task**: ogni User Story e Task figlio di un'Epic
   deve avere come prefisso il nome dell'Epic tra parentesi quadre.
   Questo garantisce che ogni task sia immediatamente riconducibile al suo modulo
   anche quando visualizzato fuori contesto (notifiche, filtri, ricerche).
   - Formato: `[Nome Epic] Titolo del task`
   - Esempio: `[Gestione utenti] Flusso reset password`

---

## V. Lingua

| Elemento | Lingua |
|---|---|
| Titoli task | Italiano |
| Descrizioni task | Italiano |
| Acceptance Criteria | Italiano |
| Comunicazione con il PM | Italiano |
| Note tecniche [AI-suggested] | Italiano |

---

## VI. Note tecniche (bridging)

L'agente AI puo' aggiungere note tecniche nei task destinate ai developer.
Queste note:
- Devono essere marcate con il prefisso `[AI-suggested]`
- Sono suggerimenti, non prescrizioni — i developer possono ignorarle
- Non devono essere mostrate al PM durante la review (sono nel campo Additional Notes)
- Servono a facilitare il passaggio PM → Developer

---

## VII. Tag

1. Usare **solo tag gia' esistenti** nello space ClickUp — non creare mai tag nuovi
2. Prima di assegnare un tag, verificare quali tag sono disponibili nello space
3. Se nessun tag esistente e' appropriato, non assegnare tag piuttosto che crearne uno nuovo

## VIII. Tracciabilita'

1. La descrizione deve iniziare con il marker `<!-- pm-setup:v1.0 -->` per la tracciabilita'

---

*Versione: 1.0.0*
