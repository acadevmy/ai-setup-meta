---
name: sdd-plan
description: Presenta la specifica tecnica allo sviluppatore per discussione, iterazione e approvazione
model: sonnet
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-plan

Presenta una specifica tecnica allo sviluppatore per revisione, discussione e approvazione.
Lo sviluppatore puo' commentare, richiedere modifiche o approvare la spec.

**Uso**: `/project:sdd-plan [SPEC_REF]`
- Con path (es. `.specs/DE-123-add-auth.md`): apre quella spec
- Con customId (es. `DE-123`): cerca la spec corrispondente in `.specs/`
- Senza argomenti: elenca le spec disponibili e chiede quale aprire

## Procedura

### 1. Localizza la spec

**Se `$ARGUMENTS` contiene un path**:
- Leggi il file al path indicato
- Se il file non esiste, informa lo sviluppatore e fermati

**Se `$ARGUMENTS` contiene un customId**:
- Cerca in `.specs/` un file che inizi con il customId (es. `DE-123-*.md`)
- Se trovato, leggi il file
- Se non trovato, informa lo sviluppatore e fermati

**Se `$ARGUMENTS` e' vuoto**:
- Elenca tutti i file `.md` in `.specs/`
- Se non ci sono spec, informa lo sviluppatore e fermati
- Se ce n'e' una sola, aprila direttamente
- Se ce ne sono piu' di una, presentale come lista numerata e chiedi quale aprire

### 2. Presenta la spec

Mostra la spec completa allo sviluppatore con formattazione chiara.
Evidenzia lo status corrente (draft/approved/implemented).

### 3. Discussione e iterazione

Chiedi allo sviluppatore come vuole procedere:

```
Come vuoi procedere?
1. Approva — la spec e' pronta, procedi con lo sviluppo
2. Modifica — indica cosa cambiare
3. Rigenera — rigenera la spec da zero (invochera' sdd-spec)
```

**Se lo sviluppatore sceglie "Approva"**:
- Aggiorna il file spec: cambia `Status: draft` in `Status: approved`
- Aggiorna il campo `Approved:` con la data odierna (formato YYYY-MM-DD)
- Conferma l'approvazione:
  ```
  Spec approvata: .specs/<filename>
  Status: approved
  Approved: <data>
  ```

**Se lo sviluppatore sceglie "Modifica"**:
- Raccogli il feedback dello sviluppatore
- Applica le modifiche richieste al file spec
- Ri-presenta la spec aggiornata
- Torna al punto 3 (loop di discussione)

**Se lo sviluppatore sceglie "Rigenera"**:
- Informa lo sviluppatore di invocare `/project:sdd-spec` con il task ID per rigenerare
- Se invocata dall'orchestratore, l'orchestratore gestira' la rigenerazione

**Se lo sviluppatore vuole discutere aspetti specifici**:
- Rispondi alle domande e ai dubbi
- Suggerisci alternative quando richiesto
- Dopo la discussione, torna al punto 3

### 4. Conferma finale

Al termine, conferma lo stato della spec e il path del file:
```
Spec: .specs/<filename>
Status: <status aggiornato>
```

## Output atteso
- Spec presentata e discussa con lo sviluppatore
- File spec aggiornato con le modifiche concordate
- Status aggiornato a `approved` (se approvata) con data di approvazione
