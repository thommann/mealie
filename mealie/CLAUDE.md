# mealie/ — FastAPI Backend

Python package for the Mealie backend. Layered architecture: **routes** → **services** → **repos** → **db/models**.

## Quick Commands

```bash
# Run
uv run python mealie/app.py

# Check (format + lint + typecheck + test)
task py:check

# Individual steps
uv run ruff format .
uv run ruff check mealie
uv run mypy mealie
uv run pytest

# New migration (after modifying ORM models)
task py:migrate -- "description"
```

## Layer Responsibilities

| Layer | Directory | Rule |
|-------|-----------|------|
| HTTP boundary | `routes/` | No business logic; translates domain exceptions to HTTP |
| Business logic | `services/` | No HTTP imports; raises domain exceptions from `core/exceptions.py` |
| Data access | `repos/` | All DB queries; auto-filters by `group_id`/`household_id` |
| ORM models | `db/models/` | Schema definition only; no business logic |
| DTOs | `schema/` | Pydantic v2; separates API types from ORM types |

## Multi-Tenancy

Every piece of user data is scoped to a `Group`. Households are sub-units within a group. The `AllRepositories` object is always constructed with `group_id` and `household_id`, which are automatically applied as WHERE clauses to every query.

```python
# Correct: repos auto-filter by tenant
repos = get_repositories(session, group_id=user.group_id, household_id=user.household_id)
recipes = repos.recipes.get_all()  # Only returns this household's recipes

# Admin bypass: use NOT_SET sentinel (NOT None!)
from mealie.repos._utils import NOT_SET
admin_repos = get_repositories(session, group_id=NOT_SET, household_id=NOT_SET)
all_recipes = admin_repos.recipes.get_all()  # Returns everything
```

**Never write `WHERE group_id=?` in routes or services.** The repo layer handles it.

## App Startup (`app.py`)

The `@asynccontextmanager lifespan_fn` handles:
1. DB init + Alembic migrations (`init_db.main()`)
2. Scheduler start (daily/hourly/minutely asyncio loops)
3. Seed data creation for first-run

Middleware stack (applied in reverse — last registered = outermost):
`GZip → Session → LocaleContext → CORS (dev only)`

Scheduled tasks are registered at import time via `SchedulerRegistry.register_daily/hourly/minutely()` in `services/scheduler/tasks/`. Adding a new scheduled task: write an async function there and call `SchedulerRegistry.register_*()` at module level.

## Settings / Configuration

All config lives in `mealie/core/settings/settings.py` as `AppSettings(BaseSettings)`. The singleton is obtained via `get_app_settings()` which is `@lru_cache`-decorated.

```python
from mealie.core.config import get_app_settings
settings = get_app_settings()  # cached — same object every call
```

**In tests**: call `get_app_settings.cache_clear()` before `monkeypatch.setenv()` to invalidate the cache.

Sensitive fields (SMTP_PASSWORD, OPENAI_API_KEY, SECRET, etc.) are masked to `*****` during serialization via `MaskedNoneString`. Access them as plain Python attributes — masking only applies to `model_dump()`/`model_dump_json()`.

**Docker secrets**: `SECRET` and `SESSION_SECRET` are loaded from `/run/secrets/` if `VARNAME_FILE` env vars are set.

## Authentication

Three auth providers, all implementing `AuthProvider[T]` ABC:
- `CredentialsProvider`: local bcrypt password verification
- `LDAPProvider(CredentialsProvider)`: LDAP two-phase bind, falls back to local for `AuthMethod.MEALIE` users
- `OpenIDProvider`: OIDC id_token decoding

`get_auth_provider()` in `security.py` returns the correct provider based on `settings.LDAP_ENABLED`.

FastAPI auth dependencies (`mealie/core/dependencies/dependencies.py`):
- `get_current_user()` — enforces auth, raises 401
- `try_get_current_user()` — returns None for anonymous
- `is_logged_in()` — boolean flag

Cookie fallback: JWT is also accepted from `mealie.access_token` cookie (set by login flow).

**Security**: `verify_fake_password()` is always called on auth failure to prevent user enumeration via timing.

## Error Handling Contract

Services raise from `mealie/core/exceptions.py`:
- `PermissionDenied` → 403
- `NoEntryFound` → 404
- `UnexpectedNone` → 500
- `RecursiveRecipe` → 400
- `RateLimitError` → 429

Routes convert these in `mealie_registered_exceptions(translator)`. **Never raise `HTTPException` from a service.**

## Alembic Migration Rules

1. Always use `with op.batch_alter_table(...)` for column changes (SQLite requirement).
2. Check dialect: `op.get_context().dialect.name == 'postgresql'` for PG-specific operations.
3. Use inline `sa.table()/sa.column()` stubs — never import live ORM model classes.
4. Add `server_default` when adding NOT NULL columns to populated tables.
5. Deduplicate rows before adding UNIQUE constraints.
6. The physical column is named `update_at` (typo from early dev), not `updated_at`. Use `update_at` in raw SQL.
