#!/usr/bin/env bash
set -euo pipefail

# Read stdin (required for all hooks)
input=$(cat)

# Check if we're in the mealie repo by looking for characteristic files
if [ ! -f "mealie/app.py" ] || [ ! -f "frontend/nuxt.config.ts" ]; then
  exit 0
fi

# Only print reminder if files were likely changed (check git status)
if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  exit 0
fi

echo "" >&2
echo "=== Mealie Pre-PR Checklist ==" >&2
echo "Backend : task py:check  (ruff format + ruff check + mypy + pytest)" >&2
echo "Frontend: task ui:check  (yarn lint --max-warnings=0 + yarn test:ci)" >&2
echo "" >&2
echo "If mealie/schema/ changed : task dev:generate  (regen TS types)" >&2
echo "If mealie/db/models/ changed: task py:migrate -- \"description\"" >&2
echo "" >&2
echo "PR target: mealie-next (NOT main)" >&2
echo "PR description MUST disclose AI/LLM assistance (.github/pull_request_template.md)" >&2
echo "============================" >&2

exit 0
