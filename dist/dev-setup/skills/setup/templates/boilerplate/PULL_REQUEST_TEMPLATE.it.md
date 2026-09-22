## Prima bisogna mergiare

<!-- Si prega di eliminare le opzioni che non sono pertinenti. -->

- [ ]({{MR_LINK_BASE}}/{id})

## Descrizione

<!--
Includi un riepilogo della modifica e indica quale problema è stato risolto indicando il numero del task.
Si prega di includere anche la motivazione e il contesto pertinenti.
-->
...

**Issue:** [DE-00000](https://app.clickup.com/t/2428116/DE-00000)

## Screenshots

<!-- Si prega di includere tutte le immagini necessarie per comprendere la richiesta di merge. -->

## Tipo di modifica

- [ ] Bug fix (modifica non dirompente che risolve un problema)
- [ ] New feature (modifica non dirompente che aggiunge una nuova funzionalità)
- [ ] Breaking change (correzione o funzionalità che impedirebbe alle funzionalità esistenti di funzionare come previsto)
- [ ] Docs (correzione o aggiunta di documentazione)

## Come è stata testata?

<!--
Descrivi i passaggi per verificare a mano la modifica: chi rivede deve poterli
ripetere senza chiedere altro. Prima i comandi da terminale, poi la navigazione
nell'applicazione con le rotte esatte.
-->

**Da terminale**

```bash
# i comandi, nell'ordine in cui vanno lanciati
# es. npm install && npm run dev
# es. npm test -- src/auth/login.spec.ts
```

**Nell'applicazione**

1. Apri `<rotta>` — es. `http://localhost:3000/auth/login`
2. `<azione da compiere: cosa inserire, cosa cliccare>`
3. Risultato atteso: `<cosa si deve vedere>`

**Casi verificati**

- [ ] Test A
- [ ] Test B

## Checklist:

- [ ] Ho incluso l'ID del task nel titolo di questa richiesta di merge
- [ ] Ho allineato la mia branch con le modifiche presenti nella branch `{{BASE_BRANCH}}`
- [ ] Ho eseguito un'auto-revisione del mio codice
- [ ] Il mio codice segue le {{CODE_CONVENTIONS_LINK}}
- [ ] Ho commentato il mio codice, in particolare nelle aree difficili da comprendere
- [ ] Ho apportato modifiche corrispondenti alla documentazione
- [ ] Ho formattato e ordinato correttamente il codice
- [ ] Ho aggiunto test che dimostrano che la mia correzione è efficace o che la mia funzionalità è corretta
- [ ] I test unitari nuovi ed esistenti passano localmente con le mie modifiche
