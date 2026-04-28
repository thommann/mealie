---
name: pre-pr-checklist
description: "
  Run all required checks before opening a pull request: backend format, lint, typecheck,
  and tests; frontend lint and tests; TS type regeneration if schemas changed;
  migration verification if models changed. Use before any PR targeting mealie-next.
---

## Quick reference

All PRs target `mealie-next` (NOT `main`). PR description MUST disclose LLM/AI assistance (`.github/pull_request_template.md` requirement).

## Backend checks

```bash
# Full backend check (format + lint + typecheck + test) — run this first
task py:check

# Or individually:
uv run ruff format .           # format Python
uv run ruff check mealie       # lint Python (must pass with 0 errors)
uv run mypy mealie             # typecheck (strict_optional=true, pydantic plugin)
uv run pytest                  # all tests (runs against SQLite by default)
```

CI also runs tests against PostgreSQL. If your change involves SQL queries, test with:
```bash
DB_ENGINE=postgres uv run pytest  # requires Docker Postgres from dev compose
```

## Frontend checks

```bash
# Full frontend check (lint + test) — required
task ui:check

# Or individually:
cd frontend
yarn lint --max-warnings=0     # ESLint with Prettier — zero warnings allowed in CI
yarn test:ci                   # Vitest unit tests (--watch=false)
```

## If you changed Pydantic schemas (mealie/schema/)

```bash
# Regenerate TypeScript types from Pydantic
task dev:generate

# Then verify frontend still compiles:
cd frontend && yarn lint --max-warnings=0

# Review the diff for breaking changes:
git diff frontend/app/lib/api/types/
```

## If you changed ORM models (mealie/db/models/)

```bash
# Generate a new Alembic migration (NEVER edit existing ones)
task py:migrate -- "description of schema change"

# Verify the chain is intact:
uv run alembic --config mealie/alembic/alembic.ini check

# Test upgrade + downgrade:
uv run alembic --config mealie/alembic/alembic.ini upgrade head
uv run alembic --config mealie/alembic/alembic.ini downgrade -1
uv run alembic --config mealie/alembic/alembic.ini upgrade head
```

## If you changed EventTypes

Verify all four files were updated in sync:
1. `mealie/services/event_bus_service/event_types.py` — enum member added
2. `mealie/schema/household/group_events.py` — boolean field added with matching name
3. `mealie/db/models/household/events.py` — ORM column added
4. A new migration file in `mealie/alembic/versions/`

```bash
# Spot-check that enum names match schema fields:
uv run python -c "
from mealie.services.event_bus_service.event_types import EventTypes
from mealie.schema.household.group_events import GroupEventNotifierOptions
fields = GroupEventNotifierOptions.model_fields.keys()
for et in EventTypes:
    if et.name not in ['test_message', 'webhook_task']:
        assert et.name in fields, f'Missing field for {et.name}'
print('All EventTypes have corresponding schema fields')
"
```

## Security-sensitive file checklist

If you touched any of these, flag for human security review in the PR:
- `mealie/core/security/security.py` — JWT creation
- `mealie/core/security/hasher.py` — bcrypt password hashing
- `mealie/core/security/providers/*.py` — auth providers
- `mealie/core/dependencies/dependencies.py` — JWT validation, admin enforcement
- `mealie/routes/auth/auth.py` — login/logout endpoints
- `mealie/app.py` — CORS policy
- `frontend/app/middleware/*.ts` — route guards (client-side only — backend must also enforce)

## PR description requirements

1. Title must start with a Conventional Commit prefix: `feat:`, `fix:`, `docs:`, `chore:`, `dev:`
2. Must include: **"I used AI/LLM assistance"** (required by `.github/pull_request_template.md`)
3. Reference issues with `Fixes #N` if applicable
4. Target branch: `mealie-next` (not `main`, not `master`)

## Common last-minute issues

- `from_attributes=True` missing on a new `*Out` schema
- New store composable added but `reset{Entity}Store()` not added to `clearAllStores()`
- New ORM model added but not registered in `mealie/db/models/_all_models.py`
- New relationship added to schema without updating `loader_options()`
- `en-US.json` key added but corresponding frontend usage missing (or vice versa)
