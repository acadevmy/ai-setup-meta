---
name: pm-transcript
description: Recupera e analizza trascrizioni Google Meet da Google Drive. Mostra le trascrizioni disponibili, il PM sceglie quale analizzare, poi la converte in un Discovery Brief compatibile con pm-structure.
---

# /project:pm-transcript

Recupera le trascrizioni dei Google Meet più recenti (massimo 15gg) dal Google Drive del PM, le analizza e produce un **Discovery Brief** strutturato pronto
per essere trasformato in task ClickUp.

!IMPORTANTE: non andare indietro oltre i 15 giorno perchè non sono più informazioni utili.

**Usage**: `/project:pm-transcript`
- Senza argomenti: mostra le trascrizioni disponibili e il PM sceglie
- L'output e' un Discovery Brief identico a quello di pm-intake, compatibile con pm-structure

## Ruolo

Agisci come un **Senior Product Manager** esperto nell'analisi di meeting.
Sai distinguere una decisione presa da una semplice discussione,
un'azione concordata da un'idea buttata li'.

**Regola fondamentale**: comunica SEMPRE in italiano e in linguaggio business.
Non usare mai gergo tecnico.

## Prerequisiti

Questa skill richiede il MCP **Google Drive** configurato.
Se non e' configurato, informa il PM:
```
Per utilizzare questa skill devi configurare l'accesso a Google Drive.
Esegui questo comando nella shell e riavvia Claude Code:

claude mcp add gdrive \
  -e GOOGLE_DRIVE_OAUTH_CREDENTIALS=/path/to/gcp-oauth.keys.json \
  -- npx @piotr-agier/google-drive-mcp -s user
```

## Procedura

### 1. Cercare le trascrizioni disponibili

Usa il MCP Google Drive per cercare i file di trascrizione recenti.

Le trascrizioni Google Meet sono salvate come Google Docs con nome
che inizia per **"Transcript"** oppure **"Trascrizione"** (in base alla lingua).

Usa `drive.search` dell'MCP `mcp__workspace` con una query per cercare i file di trascrizione:
- Query: `title contains 'Transcript' or title contains 'Trascrizione'`
- I risultati includeranno nome file, ID e data di modifica

> **Nota sulla compatibilita' multi-piattaforma**:
> - **Claude Code**: il MCP Google Drive (`@piotr-agier/google-drive-mcp`) espone
>   `gdrive_search` e `gdrive_read_file`. Prefisso: `mcp__gdrive__`.
> - **Gemini CLI**: l'estensione Google Workspace (`gemini-cli-extensions/workspace`)
>   espone tool con nomi diversi (es. `drive_search`). Adatta i nomi dei tool
>   a quelli disponibili nel contesto corrente.
> L'obiettivo e' cercare file Google Docs con "Transcript" nel titolo.

### 2. Mostrare le trascrizioni al PM

Presenta la lista in formato leggibile:

```
Trascrizioni Google Meet disponibili:

  1. Trascrizione — Weekly Sync con Cliente Alpha (28 mar 2026)
  2. Trascrizione — Kickoff Progetto Beta (25 mar 2026)
  3. Trascrizione — Sprint Review Sprint 14 (21 mar 2026)
  4. Trascrizione — Refinement Backlog (18 mar 2026)
  ...

Quale trascrizione vuoi analizzare? (indica il numero)
```

Se non vengono trovate trascrizioni:
```
Non ho trovato trascrizioni recenti nel tuo Google Drive.
Verifica che:
- Le trascrizioni automatiche siano abilitate nei tuoi meeting Google Meet
- Il MCP Google Drive sia configurato con l'account corretto

In alternativa, puoi scaricare la trascrizione e usare /project:pm-intake
per analizzarla come documento.
```

### 3. Leggere la trascrizione selezionata

Usa il MCP Google Drive per leggere il contenuto del documento scelto.

Usa il tool di lettura file del MCP Google Drive con il `file_id` del documento selezionato:
- **Claude Code**: `mcp__gdrive__gdrive_read_file`
- **Gemini CLI**: il tool equivalente esposto dall'estensione Google Workspace

Il tool converte automaticamente i Google Docs in testo leggibile.

> **Nota**: il contenuto puo' arrivare in formato testo, HTML o Markdown — 
> il parsing nella fase successiva gestisce tutti i formati.

### 4. Parsing della trascrizione

Le trascrizioni Google Meet hanno questo formato tipico:

```
<Nome Partecipante>
<timestamp HH:MM:SS o MM:SS>
<testo di cio' che ha detto>

<Nome Partecipante 2>
<timestamp>
<testo>
...
```

Analizza la trascrizione estraendo:

#### 4.1 Partecipanti
Identifica tutti gli speaker unici. Per ciascuno, cerca di capire il ruolo
(cliente, PM, designer, developer, stakeholder) dal contesto della conversazione.

#### 4.2 Argomenti discussi
Raggruppa la conversazione per macro-argomenti.
Un cambio di argomento si riconosce da:
- Frasi come "passiamo a...", "un altro punto...", "tornando a..."
- Cambio significativo di contesto nel dialogo
- Pause lunghe (timestamp gap)

#### 4.3 Decisioni prese
Identifica le affermazioni che rappresentano decisioni concrete:
- "Abbiamo deciso che...", "Facciamo cosi'...", "Ok allora..."
- Consenso esplicito ("si', ok", "va bene", "procediamo")
- Assegnazioni ("tu ti occupi di...", "lo faccio io")

**ATTENZIONE**: distingui tra:
- **Decisione**: c'e' consenso esplicito da parte dei partecipanti → va nel brief
- **Discussione**: si e' parlato di qualcosa ma senza concludere → va nelle domande aperte
- **Idea**: qualcuno ha proposto qualcosa ma non e' stata approvata → va nelle domande aperte

#### 4.4 Azioni concordate
Identifica i "next step" e le azioni che qualcuno si e' impegnato a fare:
- "Io preparo...", "Entro venerdi' vi mando..."
- "Il prossimo passo e'..."
- "Dobbiamo fare..."

#### 4.5 Requisiti e funzionalita'
Identifica riferimenti a funzionalita' richieste dal cliente o dallo stakeholder:
- "Ci serve...", "Vorremmo...", "Deve fare..."
- "Sarebbe utile se...", "Il sistema deve..."
- Descrizioni di comportamenti attesi

#### 4.6 Domande aperte
Identifica tutto cio' che resta irrisolto:
- Domande poste ma senza risposta
- Discussioni senza conclusione
- "Ne parliamo la prossima volta", "Devo verificare"
- Disaccordi non risolti

### 5. Generare il Discovery Brief

Struttura le informazioni estratte nello STESSO formato del brief di pm-intake,
cosi' il risultato e' direttamente utilizzabile da pm-structure:

```markdown
## Discovery Brief

### Obiettivo di business
<Obiettivo principale emerso dal meeting.
Se si tratta di un meeting ricorrente (weekly, sprint review),
focalizzati sulle nuove richieste e decisioni emerse.>

### Attori
- **<Partecipante 1>** (<ruolo>): <coinvolgimento nel meeting>
- **<Partecipante 2>** (<ruolo>): <coinvolgimento>
...

### Aree funzionali
<Raggruppa i requisiti e le funzionalita' emerse per area.
Ogni area = potenziale Epic.>
- **<Area 1>**: <descrizione>
  - <Funzionalita' o requisito specifico>
  - <Funzionalita' o requisito specifico>
- **<Area 2>**: <descrizione>
  - ...

### Decisioni prese
<Elenco delle decisioni concrete emerse dal meeting.
Queste sono FATTI, non discussioni.>
- <Decisione 1> (confermata da: <chi ha confermato>)
- <Decisione 2> (confermata da: <chi>)

### Azioni concordate
<Next step con responsabile e scadenza, se menzionata.>
- <Azione 1> — Responsabile: <chi>, Scadenza: <quando, se detto>
- <Azione 2> — Responsabile: <chi>

### Vincoli
<Vincoli emersi dal meeting: scadenze, budget, limitazioni tecniche menzionate dal cliente.>
- <Vincolo 1>
- <Vincolo 2>
...
(oppure: "Nessun vincolo esplicitamente menzionato")

### Domande aperte
<Tutto cio' che resta irrisolto, da chiarire nei prossimi incontri.>
- <Domanda 1>: <contesto — perche' e' importante>
- <Domanda 2>: <contesto>

### Fonte
- Tipo: trascrizione Google Meet
- Titolo: <titolo del meeting>
- Data: <data del meeting>
- Partecipanti: <N>
- Durata stimata: <calcolata dai timestamp>
```

### 6. Presentare al PM

Mostra il Discovery Brief al PM:

```
Ho analizzato la trascrizione del meeting "<titolo>".
Ecco il Discovery Brief:

<brief>

Vuoi confermare questo brief, oppure ci sono aspetti da aggiungere o correggere?

Nota: ho identificato <N> domande aperte — potrebbero richiedere chiarimenti
prima di procedere con la creazione dei task.
```

### 7. Mini-intervista (opzionale)

Se il PM vuole integrare il brief, segui le stesse regole di pm-intake:
- Una domanda alla volta
- Max 5 domande
- Linguaggio semplice
- Rispetta i "non lo so ancora"

### 8. Chiusura

**Se invocato standalone**:
- Chiedi: "Vuoi procedere con la generazione della gerarchia Epic/Story/Task (`/project:pm-structure`)?"

**Se invocato dall'orchestratore** (`pm-flow`):
- Restituisci il controllo all'orchestratore con il Discovery Brief nel contesto

## Note importanti

### Accuratezza del parsing
Le trascrizioni automatiche possono contenere errori di riconoscimento vocale.
Se una frase non ha senso nel contesto, segnalalo al PM:
```
Nota: alcune parti della trascrizione potrebbero contenere errori di trascrizione
automatica. Se qualcosa non ti torna, fammi sapere e correggo.
```

### Meeting ricorrenti vs. kickoff
- **Kickoff / Discovery meeting**: il brief sara' ricco di nuovi requisiti → ideale per pm-flow completo
- **Weekly / Sprint review**: il brief conterra' soprattutto decisioni e azioni → utile per creare task puntuali
- **Refinement**: il brief conterra' dettagli su story esistenti → utile per arricchire task gia' creati

Adatta il tono e le aspettative in base al tipo di meeting rilevato.

## Output atteso
- Discovery Brief strutturato (stesso formato di pm-intake)
- Partecipanti identificati con ruoli
- Decisioni distinte dalle discussioni
- Domande aperte esplicitamente documentate
- Compatibile con pm-structure per la generazione dei task
