# docs/legacy — materiale archiviato

Cio' che sta qui **non e' piu' parte del prodotto**: non e' dichiarato in nessun
`manifest.json`, non finisce in `dist/`, non viene caricato da nessuna skill e non
viene validato dalla CI. Resta nel repo solo come riferimento storico, per capire
com'era il setup prima dell'architettura a plugin.

Non modificarlo per "tenerlo aggiornato": se un contenuto serve ancora, va riscritto
nella sede attuale (skill, profilo o rule) e la copia qui resta com'e'.

| File | Cos'era | Perche' e' qui |
|---|---|---|
| `dev-setup-agent.md` | Agent di bootstrap del dominio `dev-setup` (1005 righe), che scaricava i file del template via `gh api` | Sostituito dalla setup skill (`templates/dev-setup/setup-skill.md`): era dichiarato nel manifest ma non veniva distribuito in `dist/` da nessun builder. Archiviato con la PR 2 della rivisitazione (DE-16472) |
