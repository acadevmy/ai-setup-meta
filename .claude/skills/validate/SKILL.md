---
name: validate
description: Validazione pre-release del plugin: riferimenti dei manifest e check statici sulla qualita' delle skill. Usa quando devi verificare il repo prima di una PR o di una release, o quando la CI segnala un finding.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

# /project:validate

Esegue i due gate statici del meta-repo. Sono gli stessi comandi che gira la CI
(`.github/workflows/ci.yml`, job `static-checks`): se passano qui, passano la'.

## Procedura

1. Riferimenti dei manifest — ogni file dichiarato esiste:

   ```bash
   bash scripts/validate-setup-urls.sh
   ```

2. Check statici sulla qualita' delle skill (12 check, vedi l'header dello script):

   ```bash
   bash scripts/validate-plugin.sh --fail-on-stale
   ```

3. Riporta l'esito distinguendo le tre categorie di output:
   - **finding nuovi** → da correggere in questa PR, sono il motivo del fallimento;
   - **finding baselinati** → debito noto censito in `scripts/validate-baseline.txt`;
   - **baseline stale** → difetti risolti: rimuovi le righe corrispondenti dalla
     baseline nella stessa PR che li ha risolti.

## Opzioni utili

- `--strict` — ignora la baseline e mostra lo stato reale del repo.
- `--json` — output machine-readable (chiavi UPPER_SNAKE) per altri script.
- `--update-baseline` — riscrive la baseline. **Solo** per debito accettato
  esplicitamente: la baseline si svuota con le PR della catena, non cresce.

## Regole

- Non allargare la baseline per far passare la CI: un finding nuovo si corregge.
- Se un check produce un falso positivo, la correzione va nello script, non
  nella baseline.
