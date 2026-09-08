#!/usr/bin/env bash
# validate-plugin.sh — Check statici sulla qualita' delle skill distribuite.
#
# Uso: bash scripts/validate-plugin.sh [OPZIONI]
#
# Opzioni:
#   --json              Output machine-readable su stdout (chiavi UPPER_SNAKE)
#   --strict            Ignora la baseline: riporta lo stato reale del repo
#   --fail-on-stale     Fallisce se la baseline contiene voci gia' risolte
#   --update-baseline   Riscrive la baseline con i finding correnti
#   --baseline FILE     Baseline alternativa (default: scripts/validate-baseline.txt)
#   -h, --help          Questo messaggio
#
# Exit code: 0 = ok · 1 = finding non baselinati · 2 = errore d'uso o dipendenza
#
# Prerequisiti: jq
#
# I check (numerazione da DE-16471):
#   1  SKILL_LINES             SKILL.md > 500 righe
#   2  SKILL_WORDS             SKILL.md > 500 parole (200 se force-loaded)
#   3  DESCRIPTION_TRIGGER     description senza clausola trigger ("Use when...")
#   4  DESCRIPTION_LENGTH      description > 1024 caratteri
#   5  REFERENCE_DEPTH         reference non linkato direttamente da SKILL.md
#   6  REFERENCE_INDEX         reference > 100 righe senza indice in testa
#   7  FORCE_LOAD_REFERENCE    riferimento @path a un file di reference
#   8  COMMAND_SKILL_DUPLICATE commands/x.md con corpo identico a skills/x/SKILL.md
#   9  CONSTITUTION_SECTIONS   sezioni citate dalle regole di pruning != heading reali
#   10 MANIFEST_ORPHAN         asset dichiarato nel manifest e mai referenziato
#   11 MARKETPLACE_SOURCE      entry di marketplace.json con source o version incoerente
#   12 LEGACY_RUNTIME_RESIDUE  riferimento a Cursor/Codex/Gemini negli artefatti
#
# I check 11 e 12 non sono nella lista originale: sono guardie di regressione
# sui difetti rimossi dalla catena (la entry `pm-setup` rotta, DE-16471; il
# supporto Cursor/Codex/Gemini, DE-16489).
# ---8<--- fine del messaggio di --help
#
# Note di scoping:
#   - Il check 2 usa il budget ridotto (200) solo per le skill force-loaded via
#     `@path` da AGENTS/rules/profili: sono le uniche sempre in contesto.
#   - Il check 10 si applica solo agli asset che la prosa deve tirare dentro
#     (profiles, boilerplate, required_files). Skill e agent dichiarati nel
#     manifest sono entry point registrati dal runtime: non essere citati da
#     altra prosa non e' un difetto. Il campo legacy `agent` non e' piu' letto:
#     l'agent di dominio e' stato sostituito dalla setup skill (PR 2).
#   - Il check 12 cerca la stringa nuda: e' la stessa grep del criterio di
#     accettazione di DE-16489. Se in futuro una regola legittima deve usare
#     una di quelle parole (es. pagination cursor-based), si restringe il
#     pattern del check — non si baselina il finding.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/builders/common.sh
source "${SCRIPT_DIR}/builders/common.sh"

MAX_SKILL_LINES=500
MAX_SKILL_WORDS=500
MAX_SKILL_WORDS_FORCE_LOADED=200
MAX_DESCRIPTION_CHARS=1024
MAX_REFERENCE_LINES=100

# Clausole accettate come trigger nella description (check 3).
TRIGGER_PATTERN='use when|use this when|usa quando|usare quando|da usare quando'

OPT_JSON=false
OPT_STRICT=false
OPT_FAIL_ON_STALE=false
OPT_UPDATE_BASELINE=false
BASELINE_FILE="${SCRIPT_DIR}/validate-baseline.txt"

# Header del file fino alla sentinella: l'elenco dei check cresce, i numeri di
# riga no.
usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

die() { echo "validate-plugin: $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --json)            OPT_JSON=true ;;
    --strict)          OPT_STRICT=true ;;
    --fail-on-stale)   OPT_FAIL_ON_STALE=true ;;
    --update-baseline) OPT_UPDATE_BASELINE=true ;;
    --baseline)        shift; [ $# -gt 0 ] || die "--baseline richiede un percorso"; BASELINE_FILE="$1" ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "opzione non riconosciuta: $1 (usa --help)" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq non trovato. Installa con: brew install jq"

# In modalita' --json l'output umano dei builder (ok/warn/step) va soppresso:
# stdout deve contenere solo il JSON.
if [ "$OPT_JSON" = true ]; then
  ok()   { :; }
  warn() { :; }
  step() { :; }
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FINDINGS="$TMP_DIR/findings.tsv"   # CHECK_ID \t SCOPE \t FILE \t LINE \t KEY \t MESSAGE
SKILLS="$TMP_DIR/skills.tsv"       # SCOPE \t NAME \t SKILL_MD \t SKILL_DIR (vuoto se non applicabile)
: > "$FINDINGS"
: > "$SKILLS"

# ── Helper ───────────────────────────────────────────────────────────────────

# Percorso relativo alla root del repo (i finding sono sempre repo-relative).
rel() { echo "${1#"${REPO_ROOT}"/}"; }

# add_finding CHECK_ID SCOPE FILE LINE KEY MESSAGE
add_finding() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$FINDINGS"
}

# Blocco frontmatter YAML (fra la prima e la seconda riga `---`).
frontmatter() {
  awk 'NR==1 && $0!="---" { exit } NR==1 { next } /^---[[:space:]]*$/ { exit } { print }' "$1"
}

# Valore di una chiave scalare del frontmatter, incluse le continuation righe
# indentate (per description: > e description: | multi-riga).
fm_value() {
  frontmatter "$1" | awk -v key="$2" '
    $0 ~ "^" key ":" {
      sub("^" key ":[[:space:]]*", "")
      # Scalari folded/literal: il valore vero sta nelle righe successive.
      if ($0 == ">" || $0 == "|" || $0 == ">-" || $0 == "|-") { $0 = "" }
      val = $0
      while ((getline line) > 0) {
        if (line ~ /^[[:space:]]+[^[:space:]]/) {
          sub(/^[[:space:]]+/, "", line)
          val = (val == "" ? line : val " " line)
        } else { break }
      }
      print val
      exit
    }'
}

# Corpo del file dopo il frontmatter (tutto il file se non c'e' frontmatter).
body_after_frontmatter() {
  if [ "$(head -1 "$1")" = "---" ]; then
    awk 'NR==1 { next } !seen && /^---[[:space:]]*$/ { seen=1; next } seen' "$1"
  else
    cat "$1"
  fi
}

# Corpo normalizzato per il confronto del check 8: via righe vuote e
# whitespace di coda, cosi' la differenza e' di contenuto e non di formattazione.
norm_body() {
  body_after_frontmatter "$1" | sed 's/[[:space:]]*$//' | grep -v '^$' || true
}

# Token che assomigliano a percorsi .md dentro un file.
md_links() {
  grep -o -E '[A-Za-z0-9_][A-Za-z0-9_./-]*\.md' "$1" 2>/dev/null | sed 's|^\./||' | sort -u || true
}

# ── Inventario skill ─────────────────────────────────────────────────────────
# Superficie distribuita: templates/<t>/.claude/skills/, shared/skills/ e la
# setup skill (che il build monta come skills/setup/SKILL.md).
# Superficie meta: .claude/skills/ del meta-repo, non distribuita ma soggetta
# alla stessa igiene.
collect_skills() {
  local d f name
  for d in "$REPO_ROOT"/templates/*/.claude/skills/*/; do
    f="${d}SKILL.md"; [ -f "$f" ] || continue
    printf 'DISTRIBUTED\t%s\t%s\t%s\n' "$(basename "$d")" "$(rel "$f")" "$(rel "${d%/}")" >> "$SKILLS"
  done
  for d in "$REPO_ROOT"/shared/skills/*/; do
    f="${d}SKILL.md"; [ -f "$f" ] || continue
    printf 'DISTRIBUTED\t%s\t%s\t%s\n' "$(basename "$d")" "$(rel "$f")" "$(rel "${d%/}")" >> "$SKILLS"
  done
  # setup-skill.md vive nella root del template: nessuna dir di reference propria.
  for f in "$REPO_ROOT"/templates/*/setup-skill.md; do
    [ -f "$f" ] || continue
    printf 'DISTRIBUTED\tsetup\t%s\t\n' "$(rel "$f")" >> "$SKILLS"
  done
  for d in "$REPO_ROOT"/.claude/skills/*/; do
    f="${d}SKILL.md"; [ -f "$f" ] || continue
    printf 'META\t%s\t%s\t%s\n' "$(basename "$d")" "$(rel "$f")" "$(rel "${d%/}")" >> "$SKILLS"
  done
}

# Una skill e' "sempre caricata" se qualcuno la force-loada con @path da
# AGENTS/rules/profili: solo in quel caso il corpo entra in ogni sessione.
is_force_loaded() {
  local skill_md="$1"
  grep -r -q -E "@[A-Za-z0-9_./-]*$(basename "$(dirname "$skill_md")")/SKILL\.md" \
    "$REPO_ROOT"/templates/*/AGENTS*.md \
    "$REPO_ROOT"/templates/*/CLAUDE*.md \
    "$REPO_ROOT"/templates/*/profiles/*.md \
    "$REPO_ROOT"/templates/*/.claude/rules/*.md \
    2>/dev/null
}

# ── Check 1-4: budget e frontmatter delle skill ──────────────────────────────
check_skill_budget_and_frontmatter() {
  step "Check 1-4 — budget righe/parole e frontmatter delle skill"
  local scope name skill_md skill_dir abs lines words desc budget
  while IFS=$'\t' read -r scope name skill_md skill_dir; do
    [ -n "${skill_md:-}" ] || continue
    abs="$REPO_ROOT/$skill_md"

    lines=$(wc -l < "$abs" | tr -d ' ')
    if [ "$lines" -gt "$MAX_SKILL_LINES" ]; then
      add_finding SKILL_LINES "$scope" "$skill_md" 0 "$skill_md" \
        "$lines righe (max $MAX_SKILL_LINES): spostare i dettagli in reference/"
    fi

    words=$(wc -w < "$abs" | tr -d ' ')
    budget=$MAX_SKILL_WORDS
    if is_force_loaded "$skill_md"; then budget=$MAX_SKILL_WORDS_FORCE_LOADED; fi
    if [ "$words" -gt "$budget" ]; then
      add_finding SKILL_WORDS "$scope" "$skill_md" 0 "$skill_md" \
        "$words parole (max $budget): spostare i dettagli in reference/"
    fi

    desc=$(fm_value "$abs" description)
    if [ -z "$desc" ]; then
      add_finding DESCRIPTION_TRIGGER "$scope" "$skill_md" 0 "$skill_md" \
        "frontmatter senza description"
    else
      if ! printf '%s' "$desc" | grep -q -i -E "$TRIGGER_PATTERN"; then
        add_finding DESCRIPTION_TRIGGER "$scope" "$skill_md" 0 "$skill_md" \
          "description senza clausola trigger (attese: Use when / Usa quando)"
      fi
      if [ "${#desc}" -gt "$MAX_DESCRIPTION_CHARS" ]; then
        add_finding DESCRIPTION_LENGTH "$scope" "$skill_md" 0 "$skill_md" \
          "description di ${#desc} caratteri (max $MAX_DESCRIPTION_CHARS)"
      fi
    fi
  done < "$SKILLS"
}

# ── Check 5-6: struttura dei file di reference ───────────────────────────────
check_references() {
  step "Check 5-6 — profondita' e indice dei file di reference"
  local scope name skill_md skill_dir abs_dir refs ref rel_ref direct linked_from other
  while IFS=$'\t' read -r scope name skill_md skill_dir; do
    [ -n "${skill_dir:-}" ] || continue
    abs_dir="$REPO_ROOT/$skill_dir"
    [ -d "$abs_dir" ] || continue

    refs=$(find "$abs_dir" -type f -name '*.md' ! -name 'SKILL.md' 2>/dev/null | sort || true)
    [ -n "$refs" ] || continue

    direct="$TMP_DIR/direct.txt"
    md_links "$abs_dir/SKILL.md" > "$direct"

    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      rel_ref="${ref#"${abs_dir}"/}"

      # Linkato direttamente da SKILL.md? (path relativo o solo basename)
      if grep -q -x -F "$rel_ref" "$direct" || grep -q -x -F "$(basename "$ref")" "$direct"; then
        : # profondita' 1, ok
      else
        linked_from=""
        while IFS= read -r other; do
          [ "$other" = "$ref" ] && continue
          if md_links "$other" | grep -q -x -F -e "$rel_ref" -e "$(basename "$ref")"; then
            linked_from="$(rel "$other")"; break
          fi
        done <<< "$refs"
        if [ -n "$linked_from" ]; then
          add_finding REFERENCE_DEPTH "$scope" "$(rel "$ref")" 0 "$(rel "$ref")" \
            "raggiungibile solo via $linked_from (profondita' >= 2 da SKILL.md)"
        else
          add_finding REFERENCE_DEPTH "$scope" "$(rel "$ref")" 0 "$(rel "$ref")" \
            "non raggiungibile: nessun link da SKILL.md ne' da altri reference"
        fi
      fi

      if [ "$(wc -l < "$ref" | tr -d ' ')" -gt "$MAX_REFERENCE_LINES" ] && ! has_index "$ref"; then
        add_finding REFERENCE_INDEX "$scope" "$(rel "$ref")" 0 "$(rel "$ref")" \
          "$(wc -l < "$ref" | tr -d ' ') righe (> $MAX_REFERENCE_LINES) senza indice nelle prime 40"
      fi
    done <<< "$refs"
  done < "$SKILLS"
}

# Indice in testa: un heading Index/Indice/Contents/Sommario oppure almeno due
# voci di lista che linkano ad anchor o ad altri .md, nelle prime 40 righe.
has_index() {
  local head40
  head40=$(head -40 "$1")
  if printf '%s\n' "$head40" | grep -q -i -E '^#+[[:space:]]+(index|indice|contents|table of contents|sommario)'; then
    return 0
  fi
  if [ "$(printf '%s\n' "$head40" | grep -c -E '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+.*\]\((#|[A-Za-z0-9_./-]+\.md)')" -ge 2 ]; then
    return 0
  fi
  return 1
}

# ── Check 7: force-load di un file di reference ──────────────────────────────
check_force_load() {
  step "Check 7 — force-load @path verso file di reference"
  local f line no token target
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      no="${line%%:*}"
      token=$(printf '%s' "${line#*:}" | grep -o -E '@[A-Za-z0-9_./-]+\.md' | head -1)
      [ -n "$token" ] || continue
      target="${token#@}"
      # Un force-load conta come difetto solo se punta dentro una skill e non
      # e' la SKILL.md stessa: quello e' contenuto che deve restare on-demand.
      case "$target" in
        */SKILL.md) continue ;;
        */skills/*|reference/*|references/*)
          add_finding FORCE_LOAD_REFERENCE DISTRIBUTED "$(rel "$f")" "$no" "$(rel "$f"):$target" \
            "force-load '$token': i file di reference vanno linkati, non iniettati"
          ;;
      esac
    done < <(grep -n -E '(^|[[:space:]])@[A-Za-z0-9_./-]+\.md' "$f" 2>/dev/null || true)
  done < <(find "$REPO_ROOT/templates" "$REPO_ROOT/shared" -type f -name '*.md' 2>/dev/null | sort)
}

# ── Check 8: comandi duplicati delle skill ───────────────────────────────────
check_command_duplicates() {
  step "Check 8 — commands/ con corpo identico alla skill omonima"
  local cmd name skill_md
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    name="$(basename "$cmd" .md)"
    skill_md=$(awk -F'\t' -v n="$name" '$2==n { print $3; exit }' "$SKILLS")
    [ -n "$skill_md" ] || continue
    if diff -q <(norm_body "$cmd") <(norm_body "$REPO_ROOT/$skill_md") >/dev/null 2>&1; then
      add_finding COMMAND_SKILL_DUPLICATE DISTRIBUTED "$(rel "$cmd")" 0 "$(rel "$cmd")" \
        "corpo identico a $skill_md: duplica la superficie pubblica"
    fi
  done < <(find "$REPO_ROOT/dist" "$REPO_ROOT/templates" -type d -name commands -exec find {} -type f -name '*.md' \; 2>/dev/null | sort)
}

# ── Check 9: sezioni della Costituzione citate dalle regole di pruning ───────
# Ogni regola "se <feature> non rilevato -> rimuovi Sezione <N>" viene
# confrontata con il titolo reale dell'heading `## <N>.` della CONSTITUTION.
# E' il check che avrebbe intercettato il pruning su §VII (Nuxt) al posto di
# §VIII (Mobile).
check_constitution_sections() {
  step "Check 9 — sezioni citate dalle regole di pruning vs heading reali"
  local tdir tname constitution headings src no text roman title feature expected
  for constitution in "$REPO_ROOT"/templates/*/CONSTITUTION.md; do
    [ -f "$constitution" ] || continue
    tdir="$(dirname "$constitution")"; tname="$(basename "$tdir")"

    headings="$TMP_DIR/headings-$tname.tsv"
    grep -E '^## [IVXLC]+\.' "$constitution" \
      | sed -E 's/^## ([IVXLC]+)\.[[:space:]]*(.*)$/\1\t\2/' > "$headings" || true

    for src in "$tdir"/setup-skill.md "$tdir"/*-setup-agent.md; do
      [ -f "$src" ] || continue
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        no="${line%%:*}"; text="${line#*:}"

        # Solo righe che rimuovono una sezione, e solo la prima sezione citata:
        # le successive sono i marcatori di confine (`## VIII.`) della regola.
        printf '%s' "$text" | grep -q -i -E 'rimuov|remove|prun' || continue
        roman=$(printf '%s' "$text" | grep -o -E '(Sezione|Section|§)[[:space:]]*[IVXLC]+' | head -1 \
          | grep -o -E '[IVXLC]+$' || true)
        [ -n "$roman" ] || continue

        title=$(awk -F'\t' -v r="$roman" '$1==r { print $2; exit }' "$headings")
        if [ -z "$title" ]; then
          add_finding CONSTITUTION_SECTIONS DISTRIBUTED "$(rel "$src")" "$no" "$(rel "$src"):$roman" \
            "cita la Sezione $roman che non esiste in $(rel "$constitution")"
          continue
        fi

        feature=$(detect_feature "$text")
        [ -n "$feature" ] || continue
        expected=$(expected_section_keyword "$feature")
        [ -n "$expected" ] || continue
        if ! printf '%s' "$title" | grep -q -i -F "$expected"; then
          add_finding CONSTITUTION_SECTIONS DISTRIBUTED "$(rel "$src")" "$no" "$(rel "$src"):$roman" \
            "regola '$feature' punta alla Sezione $roman ('$title'), attesa una sezione '$expected'"
        fi
      done < <(grep -n -E '(Sezione|Section|§)[[:space:]]*[IVXLC]+' "$src" 2>/dev/null || true)
    done
  done
}

# Feature di stack citata dalla regola di pruning. L'ordine e' una priorita':
# 'mobile' vince su 'frontend' perche' le regole mobile citano entrambi.
detect_feature() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$text" in
    *mobile*|*flutter*|*react\ native*) echo mobile ;;
    *infrastructure*|*terraform*)       echo infrastructure ;;
    *frontend*|*nuxt*|*vue*)            echo frontend ;;
    *)                                  echo "" ;;
  esac
}

expected_section_keyword() {
  case "$1" in
    mobile)         echo "Mobile" ;;
    infrastructure) echo "Infrastructure" ;;
    frontend)       echo "Frontend" ;;
    *)              echo "" ;;
  esac
}

# ── Check 10: asset dichiarati nel manifest e mai referenziati ───────────────
check_manifest_orphans() {
  step "Check 10 — asset del manifest non referenziati da nessuna skill"
  local manifest tdir tname corpus declared decl abs base cf referenced
  # Corpus = la prosa che il runtime carica davvero: skill e agent. Restano
  # fuori CHANGELOG e template di documentazione, che citano asset senza
  # caricarli (e terrebbero in vita voci morte del manifest).
  corpus="$TMP_DIR/corpus.txt"
  {
    awk -F'\t' '{ print $3 }' "$SKILLS"
    find "$REPO_ROOT"/shared/agents "$REPO_ROOT"/templates/*/.claude/agents \
      -type f -name '*.md' 2>/dev/null | sed "s|^${REPO_ROOT}/||"
  } | sort -u > "$corpus"

  for manifest in "$REPO_ROOT"/templates/*/manifest.json; do
    [ -f "$manifest" ] || continue
    tdir="$(dirname "$manifest")"; tname="$(basename "$tdir")"

    declared="$TMP_DIR/declared-$tname.txt"
    {
      jq -r '.profiles[]? | "profiles/" + .' "$manifest"
      jq -r '.boilerplate_files[]? | "boilerplate/" + .' "$manifest"
      jq -r '.required_files[]?' "$manifest"
    } | sort -u > "$declared"

    while IFS= read -r decl; do
      [ -n "$decl" ] || continue
      abs="$tdir/$decl"
      if [ ! -e "$abs" ]; then
        add_finding MANIFEST_ORPHAN DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):$decl" \
          "dichiara 'templates/$tname/$decl' che non esiste"
        continue
      fi
      base="$(basename "$decl")"
      # Referenziato se la prosa di una skill/agent lo nomina (anche solo per basename).
      referenced=false
      while IFS= read -r cf; do
        [ -n "$cf" ] || continue
        [ "$REPO_ROOT/$cf" = "$abs" ] && continue
        if grep -q -F -- "$base" "$REPO_ROOT/$cf" 2>/dev/null; then referenced=true; break; fi
      done < "$corpus"
      if [ "$referenced" = false ]; then
        add_finding MANIFEST_ORPHAN DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):$decl" \
          "'$decl' dichiarato nel manifest ma mai citato da una skill: rimuoverlo o referenziarlo"
      fi
    done < "$declared"
  done
}

# ── Check 11: integrita' del catalogo marketplace ────────────────────────────
# Claude Code e' l'unico target di build (DE-16489): un solo catalogo da
# verificare, `.claude-plugin/marketplace.json`.
CATALOG_DIR=".claude-plugin"

check_marketplace() {
  step "Check 11 — source e version delle entry di marketplace.json"
  local catalog mp name source version src_dir plugin_json plugin_version
  catalog="$REPO_ROOT/$CATALOG_DIR/marketplace.json"
  [ -f "$catalog" ] || return 0
  mp="$(rel "$catalog")"

  while IFS=$'\t' read -r name source version; do
    [ -n "$name" ] || continue
    case "$source" in
      ./*) src_dir="$REPO_ROOT/${source#./}" ;;
      *)   continue ;;  # source remoti: non verificabili offline
    esac

    if [ ! -d "$src_dir" ]; then
      add_finding MARKETPLACE_SOURCE DISTRIBUTED "$mp" 0 "$mp:$name" \
        "entry '$name' punta a '$source' che non esiste"
      continue
    fi

    plugin_json="$src_dir/$CATALOG_DIR/plugin.json"
    if [ ! -f "$plugin_json" ]; then
      add_finding MARKETPLACE_SOURCE DISTRIBUTED "$mp" 0 "$mp:$name" \
        "entry '$name': manca $CATALOG_DIR/plugin.json in '$source'"
      continue
    fi

    plugin_version="$(jq -r '.version // empty' "$plugin_json")"
    if [ -n "$version" ] && [ -n "$plugin_version" ] && [ "$version" != "$plugin_version" ]; then
      add_finding MARKETPLACE_SOURCE DISTRIBUTED "$mp" 0 "$mp:$name" \
        "entry '$name' dichiara v$version, plugin.json dice v$plugin_version"
    fi
  done < <(jq -r '.plugins[]? | [.name, .source // "", .version // ""] | @tsv' "$catalog")
}

# ── Check 12: residui dei runtime non piu' supportati ────────────────────────
# Cursor, Codex e Gemini sono stati rimossi con DE-16489: builder, artefatti in
# dist/ e catalogo dedicato. Il check e' la grep del criterio di accettazione,
# resa permanente perche' il supporto non rientri di soppiatto da una PR.
# Esclusi: i CHANGELOG (storia della release, non superficie del plugin) e i due
# file di questo controllo, che contengono i pattern per definizione.
LEGACY_RUNTIME_PATTERN='cursor|codex|gemini'

check_legacy_runtime_residue() {
  step "Check 12 — residui di Cursor/Codex/Gemini negli artefatti"
  local f line no text
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      */CHANGELOG.md) continue ;;
      "$SCRIPT_DIR"/validate-plugin.sh|"$BASELINE_FILE") continue ;;
    esac
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      no="${line%%:*}"
      text="$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//')"
      add_finding LEGACY_RUNTIME_RESIDUE DISTRIBUTED "$(rel "$f")" "$no" "$(rel "$f"):$no" \
        "riferimento a un runtime rimosso (DE-16489): $text"
    done < <(grep -n -i -E "$LEGACY_RUNTIME_PATTERN" "$f" 2>/dev/null || true)
  done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$REPO_ROOT/dist" \
             "$REPO_ROOT/.claude-plugin" -type f 2>/dev/null | sort)
}

# ── Esecuzione ───────────────────────────────────────────────────────────────
collect_skills
[ -s "$SKILLS" ] || die "nessuna skill trovata: eseguire dalla root del repo"

check_skill_budget_and_frontmatter
check_references
check_force_load
check_command_duplicates
check_constitution_sections
check_manifest_orphans
check_marketplace
check_legacy_runtime_residue

sort -o "$FINDINGS" "$FINDINGS"

# ── Baseline ─────────────────────────────────────────────────────────────────
BASELINE_KEYS="$TMP_DIR/baseline-keys.txt"
CURRENT_KEYS="$TMP_DIR/current-keys.txt"
: > "$BASELINE_KEYS"
if [ "$OPT_STRICT" = false ] && [ -f "$BASELINE_FILE" ]; then
  grep -v -E '^[[:space:]]*(#|$)' "$BASELINE_FILE" | sort -u > "$BASELINE_KEYS" || true
fi
awk -F'\t' '{ printf "%s\t%s\n", $1, $5 }' "$FINDINGS" | sort -u > "$CURRENT_KEYS"

STALE_KEYS="$TMP_DIR/stale-keys.txt"
comm -23 "$BASELINE_KEYS" "$CURRENT_KEYS" > "$STALE_KEYS"

if [ "$OPT_UPDATE_BASELINE" = true ]; then
  {
    echo "# validate-baseline.txt — fail noti di scripts/validate-plugin.sh."
    echo "#"
    echo "# Una riga per finding: CHECK_ID <TAB> KEY. Le voci qui elencate sono"
    echo "# riportate ma non fanno fallire la CI. Ogni PR che risolve un difetto"
    echo "# rimuove la riga corrispondente: la baseline si svuota, non cresce."
    echo "# Rigenerare con: bash scripts/validate-plugin.sh --update-baseline"
    echo "#"
    echo "# Stato reale del repo: bash scripts/validate-plugin.sh --strict"
    echo ""
    cat "$CURRENT_KEYS"
  } > "$BASELINE_FILE"
  ok "Baseline riscritta: $(rel "$BASELINE_FILE") ($(wc -l < "$CURRENT_KEYS" | tr -d ' ') voci)"
  exit 0
fi

TOTAL=$(wc -l < "$FINDINGS" | tr -d ' ')
NEW=0
BASELINED=0
NEW_FINDINGS="$TMP_DIR/new.tsv"
: > "$NEW_FINDINGS"
while IFS=$'\t' read -r cid scope file line key msg; do
  [ -n "${cid:-}" ] || continue
  if grep -q -F -x "$(printf '%s\t%s' "$cid" "$key")" "$BASELINE_KEYS" 2>/dev/null; then
    BASELINED=$((BASELINED + 1))
  else
    NEW=$((NEW + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$cid" "$scope" "$file" "$line" "$key" "$msg" >> "$NEW_FINDINGS"
  fi
done < "$FINDINGS"

STALE=$(wc -l < "$STALE_KEYS" | tr -d ' ')

EXIT_CODE=0
[ "$NEW" -gt 0 ] && EXIT_CODE=1
if [ "$OPT_FAIL_ON_STALE" = true ] && [ "$STALE" -gt 0 ]; then EXIT_CODE=1; fi

# ── Report ───────────────────────────────────────────────────────────────────
if [ "$OPT_JSON" = true ]; then
  jq -n \
    --arg status "$([ "$EXIT_CODE" -eq 0 ] && echo PASS || echo FAIL)" \
    --argjson total "$TOTAL" \
    --argjson new_failures "$NEW" \
    --argjson baselined "$BASELINED" \
    --argjson stale_baseline "$STALE" \
    --rawfile findings "$FINDINGS" \
    --rawfile stale "$STALE_KEYS" \
    '{
      STATUS: $status,
      TOTAL_FINDINGS: $total,
      NEW_FAILURES: $new_failures,
      BASELINED: $baselined,
      STALE_BASELINE: $stale_baseline,
      FINDINGS: ($findings | split("\n") | map(select(length > 0)) | map(split("\t")) | map({
        CHECK_ID: .[0], SCOPE: .[1], FILE: .[2], LINE: (.[3] | tonumber), KEY: .[4], MESSAGE: .[5]
      })),
      STALE_BASELINE_KEYS: ($stale | split("\n") | map(select(length > 0)) | map(split("\t")) | map({
        CHECK_ID: .[0], KEY: .[1]
      }))
    }'
  exit "$EXIT_CODE"
fi

echo ""
if [ "$NEW" -gt 0 ]; then
  step "Finding nuovi ($NEW) — non presenti in baseline"
  while IFS=$'\t' read -r cid scope file line key msg; do
    [ -n "${cid:-}" ] || continue
    if [ "$line" != "0" ]; then
      echo -e "${RED}✗${NC} [$cid] $file:$line — $msg"
    else
      echo -e "${RED}✗${NC} [$cid] $file — $msg"
    fi
  done < "$NEW_FINDINGS"
fi

if [ "$STALE" -gt 0 ]; then
  step "Baseline stale ($STALE) — difetti risolti, rimuovere le righe da $(rel "$BASELINE_FILE")"
  while IFS=$'\t' read -r cid key; do
    [ -n "${cid:-}" ] || continue
    echo -e "${YELLOW}⚠${NC}  $cid\t$key"
  done < "$STALE_KEYS"
fi

echo ""
echo "Finding totali: $TOTAL · baselinati: $BASELINED · nuovi: $NEW · baseline stale: $STALE"
if [ "$EXIT_CODE" -eq 0 ]; then
  ok "Nessun finding nuovo. Validazione passata."
else
  echo -e "${RED}✗${NC} Validazione fallita. Correggi i finding nuovi (o aggiorna la baseline se sono debito accettato)."
fi
exit "$EXIT_CODE"
