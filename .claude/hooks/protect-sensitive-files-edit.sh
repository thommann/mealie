#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
if [ -z "$input" ]; then
  exit 0
fi

file_path=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

if [ -z "$file_path" ]; then
  exit 0
fi

# Block edits to existing Alembic migration files
# Editing an existing migration corrupts the sequential migration chain
# and causes irreversible data loss on all existing databases.
# To change DB schema: run 'task py:migrate -- "description"' to create a NEW migration.
if echo "$file_path" | grep -qE "mealie/alembic/versions/.*\.py$"; then
  if [ -f "$file_path" ]; then
    echo "ERROR: Cannot edit existing Alembic migration: $file_path" >&2
    echo "Editing an existing migration corrupts the migration chain for all databases that have run it." >&2
    echo "To change the database schema, create a NEW migration:" >&2
    echo "  task py:migrate -- \"description of change\"" >&2
    exit 2
  fi
fi

# Block edits to auto-generated TypeScript types
if echo "$file_path" | grep -qE "frontend/app/lib/api/types/.*\.ts$"; then
  echo "ERROR: $file_path is auto-generated from Pydantic models." >&2
  echo "Manual edits will be overwritten by the next 'task dev:generate' run." >&2
  echo "To fix a type: change mealie/schema/ then run 'task dev:generate'." >&2
  echo "For frontend-only types: edit frontend/app/lib/api/types/non-generated.ts" >&2
  exit 2
fi

exit 0
