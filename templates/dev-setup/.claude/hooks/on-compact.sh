#!/bin/bash
# SessionStart hook (compact): re-injects critical context after compaction
# When the context is compacted, Claude loses information. This hook
# re-injects the most important reminders and the REGISTRY.md content.

# Read project info if available
PROJECT_NAME=""
if [ -f "package.json" ]; then
  PROJECT_NAME=$(jq -r '.name // empty' package.json 2>/dev/null)
fi

STACK_PROFILE=""
if [ -f ".env.local" ]; then
  STACK_PROFILE=$(grep "^STACK_PROFILE=" .env.local 2>/dev/null | cut -d= -f2)
fi

# Re-inject REGISTRY.md if it exists
REGISTRY_CONTENT=""
if [ -f "REGISTRY.md" ]; then
  REGISTRY_CONTENT=$(cat REGISTRY.md)
fi

# Output to stdout — gets added to Claude's context
cat <<EOF
[Context re-injected after compaction]
- Project: ${PROJECT_NAME:-"(see package.json)"}
- Stack: ${STACK_PROFILE:-"(see .env.local)"}
- ALWAYS follow CONSTITUTION.md before any action
- Use Conventional Commits for commit messages
- Do not modify protected files (.env, lock files)
EOF

if [ -n "$REGISTRY_CONTENT" ]; then
  cat <<EOF

[REGISTRY.md — project context]
$REGISTRY_CONTENT
EOF
fi

exit 0
