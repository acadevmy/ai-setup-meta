#!/bin/bash
# SessionStart hook (compact): re-inietta contesto critico dopo compaction
# Quando il contesto viene compattato, Claude perde informazioni. Questo hook
# re-inietta i reminder piu' importanti dal progetto.

# Leggi info dal progetto se disponibili
PROJECT_NAME=""
if [ -f "package.json" ]; then
  PROJECT_NAME=$(jq -r '.name // empty' package.json 2>/dev/null)
fi

STACK_PROFILE=""
if [ -f ".env.local" ]; then
  STACK_PROFILE=$(grep "^STACK_PROFILE=" .env.local 2>/dev/null | cut -d= -f2)
fi

# Output su stdout — viene aggiunto al contesto di Claude
cat <<EOF
[Context re-injected after compaction]
- Progetto: ${PROJECT_NAME:-"(vedi package.json)"}
- Stack: ${STACK_PROFILE:-"(vedi .env.local)"}
- Segui SEMPRE la CONSTITUTION.md prima di ogni azione
- Aggiorna REGISTRY.md quando crei/modifichi moduli
- Usa Conventional Commits per i messaggi di commit
- Non modificare file protetti (.env, lock files)
EOF

exit 0
