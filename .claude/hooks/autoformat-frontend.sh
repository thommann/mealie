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

# Only format TypeScript/Vue/JS files in frontend/app/ (not auto-generated types)
if echo "$file_path" | grep -qE "\.(ts|vue|js)$" \
  && echo "$file_path" | grep -q "^frontend/" \
  && ! echo "$file_path" | grep -qE "frontend/app/lib/api/types/"; then
  if [ -f "$file_path" ]; then
    # Get path relative to frontend/ directory
    rel_path="${file_path#frontend/}"
    (cd frontend && yarn lint --fix "$rel_path" 2>/dev/null) || true
  fi
fi

exit 0
