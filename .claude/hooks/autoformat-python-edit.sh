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

# Only format Python files in mealie/ or tests/ directories
if echo "$file_path" | grep -qE "\.py$" && echo "$file_path" | grep -qE "^(mealie/|tests/)"; then
  if [ -f "$file_path" ]; then
    uv run ruff format "$file_path" 2>/dev/null || true
    uv run ruff check --fix --unsafe-fixes "$file_path" 2>/dev/null || true
  fi
fi

exit 0
