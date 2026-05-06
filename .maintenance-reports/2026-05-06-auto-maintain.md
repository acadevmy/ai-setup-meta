# Auto-maintain — esecuzione del 2026-05-06

**Esito**: NO-OP (pipeline non eseguita).
**Run type**: scheduled task `attivit-di-manutenzione-progetto-ai-setup` → `/auto-maintain`.
**Generato**: 2026-05-06 06:37 UTC.

## Sintesi

Anche in questo ciclo la pipeline `/auto-maintain` non puo' essere eseguita.
Lo stato del repository e dell'ambiente e' invariato rispetto al run del
2026-05-05 (vedi `.maintenance-reports/2026-05-05-auto-maintain.md`): la
skill non e' ancora installata sul branch attivo, il working tree non e'
pulito e `CLICKUP_API_TOKEN` resta vuoto. Nessuna modifica a file, nessuna
chiamata verso ClickUp o GitHub, nessuna PR aperta.

## 1. Skill `/auto-maintain` non disponibile sul branch corrente

Il branch attualmente in checkout e' `feat/pm-setup-template`. La skill
`auto-maintain` (file `.claude/skills/auto-maintain/SKILL.md`) e' presente
solo sul branch `feat/auto-maintain-pipeline`, che non risulta mergiato ne'
in `main` ne' nel branch corrente:

- `git branch --contains origin/feat/auto-maintain-pipeline` →
  `feat/auto-maintain-pipeline` e `remotes/origin/feat/auto-maintain-pipeline`
  (nessun altro)
- `find .claude -path "*auto-maintain*"` → nessun match sul branch corrente
- `ls .claude/skills` → `generate-setup`, `sync-profiles`,
  `update-constitution` (nessuna `auto-maintain`)
- `ls .claude/commands` → `build-plugin.md`, `release-plugin.md`,
  `validate.md` (nessun `auto-maintain.md`)

Di conseguenza il comando `/auto-maintain` non e' realmente invocabile in
questo ambiente; la richiesta del task schedulato fa riferimento a una
funzionalita' ancora in feature branch.

L'ultimo commit su `origin/feat/auto-maintain-pipeline` e' `9ff06ca`
(`refactor: remove dependency on gh CLI by reimplementing GitHub and ClickUp
operations using curl and jq`) — branch fermo, nessun avanzamento dal run
precedente.

## 2. Prerequisiti dello Step 0 (preflight) non soddisfatti

Sono stati eseguiti i check di preflight definiti dalla skill (cosi' come
documentati su `feat/auto-maintain-pipeline`). Esito:

| Check | Stato | Dettagli |
|---|---|---|
| Working tree pulito (`git status --porcelain` vuoto) | FAIL | 4 file modificati e 3 untracked sul branch `feat/pm-setup-template` |
| `.env.local` presente | OK | File esistente, permessi `600` |
| `CLICKUP_MAINTENANCE_LIST_ID` valorizzata | OK | impostata (13 char) |
| `GH_TOKEN` valorizzato | OK | impostato (40 char) — non validato via API per non emettere chiamate non necessarie in modalita' no-op |
| `CLICKUP_API_TOKEN` valorizzato | FAIL | la chiave esiste in `.env.local` ma e' **vuota**; lo Step 0.5 prevede uscita immediata con `CLICKUP_API_TOKEN non configurato in .env.local.` |

Anche se la skill fosse installata, il preflight terminerebbe con bail-out
prima di Step 1 (selezione task). Non sono state quindi effettuate chiamate
verso l'API ClickUp ne' GitHub.

## 3. Stato del repo (informativo)

- Branch corrente: `feat/pm-setup-template` (up-to-date con
  `origin/feat/pm-setup-template`, HEAD `82cfd4b`)
- Branch dell'auto-maintain pipeline (non mergiato): `feat/auto-maintain-pipeline` (HEAD `9ff06ca`)
- Branch principale: `main` (HEAD `f53f957`, `chore(main): release dev-setup 1.10.0`)

### Working tree

Modificati:

- `.claude-plugin/marketplace.json`
- `dist/pm-setup/gemini/README.md`
- `scripts/builders/build-gemini.sh`
- `templates/pm-setup/GEMINI-README.md`

Untracked:

- `.maintenance-reports/` (la directory contenente i report di
  manutenzione, inclusa l'esecuzione di ieri e quella di oggi)
- `dist/pm-setup/gemini/install.sh`
- `scripts/install-pm-gemini.sh`

Le modifiche sembrano riconducibili al lavoro del template `pm-setup` per
Gemini (build script + README) e non riguardano la pipeline di manutenzione:
non sono state toccate ne' stagiate.

## 4. Azioni suggerite (lato umano)

Le indicazioni sono identiche al ciclo precedente. Per abilitare le
esecuzioni schedulate di `/auto-maintain`:

1. **Mergiare `feat/auto-maintain-pipeline`** in `main` (o quantomeno
   propagare la skill `.claude/skills/auto-maintain/` e l'agent
   `.claude/agents/clickup.md` sul branch usato dallo scheduler) cosi' che
   la skill diventi effettivamente invocabile.
2. **Popolare `CLICKUP_API_TOKEN`** in `.env.local` con un token valido per
   il workspace ClickUp che ospita la lista di manutenzione. Senza questo
   valore la pipeline esce immediatamente in preflight.
3. **Pulire il working tree** prima di lanciare la pipeline: lo scheduler si
   aspetta `git status --porcelain` vuoto. Le modifiche pendenti sul ramo
   `feat/pm-setup-template` vanno committate (su un branch dedicato) o
   stashate prima dell'orario schedulato. In aggiunta, valutare se aggiungere
   `.maintenance-reports/` al `.gitignore`: la directory cresce ad ogni run
   schedulato e altrimenti continuera' a comparire come untracked.
4. (Opzionale) **Eseguire `/auto-maintain` on-demand** una volta soddisfatti
   i punti 1-3, per validare end-to-end la pipeline su un task ClickUp di
   prova prima di affidarla al cron.

Nessuna delle azioni qui sopra e' stata eseguita autonomamente: tutte e tre
ricadono fuori dal perimetro che la skill stessa autorizza alla pipeline
(modifica di credenziali, merge di branch verso `main`, gestione di working
tree con modifiche non riconducibili al task corrente).

## 5. Delta rispetto al run del 2026-05-05

- Skill `/auto-maintain`: **invariato** (ancora solo su `feat/auto-maintain-pipeline`).
- Branch corrente: **invariato** (`feat/pm-setup-template`, stesso HEAD).
- Working tree: **invariato** nei file modificati; aggiunta solo la directory
  untracked `.maintenance-reports/` (creata dal run precedente).
- `.env.local`: **invariato**, `CLICKUP_API_TOKEN` ancora vuoto.

In assenza di interventi umani sui punti elencati nella sezione 4, ogni
prossima esecuzione schedulata produrra' lo stesso esito.

---
Report generato dall'esecuzione schedulata di `/auto-maintain`.
