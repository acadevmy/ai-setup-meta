---
name: setup
description: Setup agent AI-Native — seleziona il dominio e avvia il setup specifico
user-invocable: true
disable-model-invocation: true
---

# /project:setup

Setup agent AI-Native. Seleziona il tipo di progetto e delega al setup agent di dominio.

**Uso**: `/project:setup` (senza argomenti)

---

## Passo 1 — Verifica prerequisiti

1. Verifica che `gh` CLI sia installata: `command -v gh`
2. Verifica autenticazione: `gh auth status`
3. Se uno dei due fallisce, informa l'utente e fermati

---

## Passo 2 — Scopri i domini disponibili

Scarica la lista dei template disponibili dal repo sorgente:

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates -H "Accept: application/vnd.github.raw+json"
```

Per ogni directory trovata, scarica il relativo `manifest.json`:

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/<NOME>/manifest.json -H "Accept: application/vnd.github.raw" 2>/dev/null
```

Costruisci la lista dei domini disponibili leggendo `name` e `description` da ciascun manifest.

---

## Passo 3 — Selezione del dominio

Mostra all'utente i domini disponibili in questo formato:

```
Che tipo di setup vuoi creare?

  1. dev-setup — Setup AI-native per progetti di sviluppo software
  2. pm-setup  — Setup AI-native per project management
  ...

Scegli un numero:
```

Se e' disponibile un solo dominio, selezionalo automaticamente informando l'utente.
Se l'utente passa un argomento (es. `/project:setup dev`), usa quello senza chiedere.

---

## Passo 4 — Lancia l'agent di dominio

L'agent di dominio corrispondente e' gia' presente in locale (scaricato insieme a questa skill):

```
.claude/agents/<nome>-setup-agent.md
```

Lancia l'agent con il suo nome. Ad esempio, per `dev-setup`:

> Lancia l'agent `dev-setup-agent`

L'agent di dominio si occupera' di tutto: download risorse, detection stack, composizione setup.

---

## Note

- Questo dispatcher non contiene logica di setup — delega tutto all'agent di dominio
- Gli agent di dominio sono distribuiti insieme a questa skill nel repo di distribuzione
- Il repo sorgente e': `acadevmy/ai-setup-meta`
