# Mealie

> Authoritative AI-agent project facts (architecture, conventions, build
> commands) live in `.github/copilot-instructions.md`. This file adds
> Claude Code harness configuration only.

Self-hosted recipe manager, meal planner, and shopping list with a FastAPI backend and Nuxt 4/Vue 3 frontend.

## Quick Reference

| Task | Command |
|------|---------|
| Install Python deps | `uv sync --extra pgsql --group dev` |
| Install frontend deps | `cd frontend && yarn install` |
| Run backend | `uv run python mealie/app.py` |
| Run dev stack | `docker compose -f docker/docker-compose.dev.yml up` |
| **Before every PR** | `task py:check` (format + lint + typecheck + test) |
| **Before every PR** | `task ui:check` (frontend lint + test) |
| Python format | `uv run ruff format .` |
| Python lint | `uv run ruff check mealie` |
| Python typecheck | `uv run mypy mealie` |
| Python test (all) | `uv run pytest` |
| Frontend lint | `cd frontend && yarn lint --max-warnings=0` |
| Frontend test | `cd frontend && yarn test:ci` |
| E2E tests | `yarn playwright test` (from `tests/e2e/`) |
| New Alembic migration | `uv run alembic --config mealie/alembic/alembic.ini revision --autogenerate -m "<message>"` |
| Regen TS types | `task dev:generate` (after any Pydantic schema change) |
| Build package | `uv build --out-dir dist` |
| Build Docker image | `docker build --tag mealie:dev --file docker/Dockerfile --build-context packages=dist .` |
| Build docs | `uv run --no-project mkdocs build -d site` |

## Architecture

### Overview

Mealie is a monorepo with two primary packages: `mealie/` (Python/FastAPI backend) and `frontend/` (Nuxt 4/Vue 3 SPA). The backend exposes a REST API at `/api/**`; the frontend is a fully client-side SPA (`ssr: false`) that proxies all requests to the backend through Nuxt server routes in `frontend/server/`. In production, a reverse proxy (nginx/Caddy) is expected to sit in front of both.

The backend follows a strict four-layer architecture: **routes** (HTTP boundary) → **services** (business logic) → **repos** (data access) → **db/models** (ORM). All data is multi-tenant, isolated by `group_id` and `household_id` at the repository layer — individual routes and services never write their own tenant WHERE clauses. The frontend replaces Pinia/Vuex with a composable-first architecture: module-level `ref()` singletons act as shared stores, wired through a class-based API client layer generated from backend Pydantic models.

Deployment is Docker-first (multi-stage Dockerfile + Compose files in `docker/`). The application supports both SQLite (default) and PostgreSQL. Background tasks run via asyncio loops registered through `SchedulerRegistry` — no Celery or APScheduler.

### Directory Structure

```
mealie/                   # FastAPI backend (Python package)
├── app.py                # Application factory + lifespan (scheduler, middleware)
├── core/                 # Settings, security providers, DI deps, logging
│   ├── settings/         # Pydantic BaseSettings — all env-var config
│   ├── security/         # JWT, bcrypt, AuthProvider ABC + LDAP/OIDC providers
│   └── dependencies/     # FastAPI Depends() functions for auth
├── db/
│   ├── models/           # SQLAlchemy ORM models (group/, household/, recipe/, users/)
│   └── init_db.py        # Runs Alembic migrations on startup
├── alembic/              # Migration scripts + env.py
├── repos/                # Repository layer — all DB access
│   ├── repository_generic.py   # RepositoryGeneric[Schema, Model] base
│   ├── all_repositories.py     # AllRepositories — single access point
│   └── repository_factory.py   # get_repositories() factory
├── routes/               # FastAPI routers by domain
│   ├── _base/            # @controller decorator, base controller classes, mixins
│   ├── recipe/           # Recipe CRUD, bulk, SSE scraping, exports
│   ├── households/       # Meal plans, shopping lists, cookbooks, webhooks
│   ├── groups/           # Group self-service, migrations, labels, seeder
│   ├── admin/            # Cross-tenant admin management
│   └── auth/             # JWT token issuance, OIDC callback
├── schema/               # Pydantic v2 DTOs (request/response models)
│   ├── _mealie/          # MealieModel base — camelCase aliasing, UTC normalization
│   ├── recipe/           # Recipe + ingredient + instruction schemas
│   ├── household/        # Shopping list, meal plan, webhook schemas
│   └── openai/           # Structured-output schemas for OpenAI calls
├── services/             # Business logic layer
│   ├── _base_service/    # BaseService — injects dirs, settings, logger
│   ├── recipe/           # RecipeService, RecipeDataService, BulkActionsService
│   ├── scraper/          # Strategy-cascade web scraper + cleaner
│   ├── openai/           # OpenAIService wrapper + prompt files
│   ├── parser_services/  # Ingredient parser (brute/NLP/OpenAI)
│   ├── migrations/       # Format importers (Nextcloud, Paprika, Tandoor, …)
│   ├── event_bus_service/# Pub/sub events → Apprise + webhooks
│   └── scheduler/        # asyncio scheduler registry + tasks
├── middleware/            # LocaleContextMiddleware (Accept-Language → ContextVar)
├── pkgs/                 # Internal utilities: cache, i18n, img, safehttp, stats
└── lang/                 # Locale JSON files for backend error messages

frontend/
├── nuxt.config.ts        # SSR disabled, runtime config (API_URL, AUTH_TOKEN)
├── app/                  # Nuxt 4 app/ source root (auto-imported)
│   ├── pages/            # File-based routes (g/[groupSlug]/, admin/, household/, …)
│   ├── components/       # Domain/ (feature-specific) + global/ (primitives) + Layout/
│   ├── composables/      # State management via module-level refs + store factories
│   │   ├── store/        # Per-entity CRUD stores (useCategoryStore, etc.)
│   │   ├── partials/     # Generic useStore/useStoreActions factory functions
│   │   └── api/          # Axios client factory composables
│   ├── lib/api/          # Typed API client classes (Base → User/Admin/Public)
│   │   ├── base/         # BaseCRUDAPI[C,R,U], route() URL builder
│   │   ├── user/         # UserApiClient + domain sub-APIs
│   │   ├── admin/        # AdminAPI + admin sub-APIs
│   │   └── types/        # TS types auto-generated from Pydantic (DO NOT EDIT)
│   ├── layouts/          # Nuxt layouts (default, admin, basic, blank)
│   ├── middleware/        # Route guards (admin-only, group-only, can-manage-*)
│   ├── plugins/          # Axios interceptors, auth init, theme, dark mode, globals
│   └── lang/             # i18n locale files (40+ languages, en-US is canonical)
├── server/               # Nuxt server routes — proxy to FastAPI backend
└── tests/e2e/            # Playwright e2e (auth flows against full Docker stack)

tests/                    # Python test suite
├── conftest.py           # Session-wide DB init + TestClient + fixture imports
├── fixtures/             # Pytest fixtures (users, recipes, shopping lists, multitenant)
├── utils/                # TestUser schema, factories, assertion helpers, api_routes
├── integration_tests/    # API-level tests by domain
├── unit_tests/           # Service/schema/repo/security unit tests
└── multitenant_tests/    # Cross-group isolation verification (5 entity types)

docker/
├── Dockerfile            # 6-stage multi-arch build
├── docker-compose.yml    # Production compose (SQLite or PostgreSQL)
├── docker-compose.dev.yml# Dev compose with Mailpit + Postgres
├── entry.sh              # Container entrypoint (_FILE secrets, PUID/PGID, gosu)
└── healthcheck.sh        # TLS-aware health check against /api/app/about
```

### Backend Architecture

The route layer uses a **class-based view (CBV)** pattern via a custom `@controller(router)` decorator (`mealie/routes/_base/controller.py`). The decorator rewrites `__init__` so FastAPI injects all class-level type-annotated attributes as `Depends()` parameters. This eliminates repeating `Depends()` on every function. Controllers inherit from `BaseUserController` (for authenticated routes) or `BaseAdminController` (for cross-tenant admin routes). `BaseAdminController` overrides `repos` to pass `group_id=None`, giving unrestricted data access.

The repository layer is built on `RepositoryGeneric[Schema, Model]` which provides typed CRUD + pagination. Subclasses for groups (`GroupRepositoryGeneric`) and households (`HouseholdRepositoryGeneric`) automatically inject `group_id` and `household_id` WHERE clauses into every query. `AllRepositories` (`mealie/repos/all_repositories.py`) aggregates every domain repository as `@cached_property` attributes and is the single entry point passed to services and controllers. Constructing it with `NOT_SET` sentinels (not `None`) bypasses scoping for admin contexts.

The service layer uses `BaseService` for shared infrastructure (logger, directories, settings). Complex domain services split into a `*Base` class that validates tenant context and a concrete service that adds operation methods. Services raise domain exceptions from `mealie/core/exceptions.py`; routes translate these to HTTP responses.

**Multi-tenancy model**: A `Group` is the top-level tenant. A `Group` contains one or more `Household`s. `User`s belong to both. Recipes are group-scoped; meal plans, shopping lists, and cookbooks are household-scoped. All repository queries are silently filtered — never write manual `WHERE group_id=?` in routes or services.

### Frontend Architecture

The frontend is a Nuxt 4 SPA with `ssr: false`. All source lives under `frontend/app/` (Nuxt 4 convention). Components, composables, and Vue APIs are all auto-imported.

**API client layer**: `frontend/app/lib/api/` contains hand-written TypeScript classes. `BaseCRUDAPI<Create, Read, Update>` provides `getAll/getOne/createOne/updateOne/patchOne/deleteOne`. Concrete APIs (`RecipeAPI`, `ShoppingApi`, etc.) extend this and add domain-specific methods. Three aggregator classes (`UserApiClient`, `AdminAPI`, `PublicApi`) freeze-compose all domain APIs and are instantiated via composables (`useUserApi()`, `useAdminApi()`, `usePublicApi()`). Every HTTP method returns `Promise<RequestResponse<T>>` = `{ response, data, error }` — errors are never thrown, always check `.error`.

**State management**: No Pinia/Vuex. All shared state lives in module-level `ref<T[]>()` singletons in `frontend/app/composables/store/`. The `useStore()`/`useReadOnlyStore()` factories in `partials/use-store-factory.ts` auto-hydrate on first call. Call `clearAllStores()` on logout to prevent session data leaking between users.

**TypeScript types**: `frontend/app/lib/api/types/` files are auto-generated from Pydantic models via `pydantic-to-typescript2`. **Never edit them manually.** After any Pydantic schema change, run `task dev:generate` to regenerate.

### Key Abstractions

**`MealieModel`** (`mealie/schema/_mealie/mealie_model.py`): Pydantic v2 base for all API DTOs. Applies `alias_generator=camelize` (snake_case Python ↔ camelCase JSON), `populate_by_name=True` (accepts both forms), and a model validator that attaches UTC tzinfo to all datetimes. All request/response schemas must inherit from it.

**`AllRepositories`** (`mealie/repos/all_repositories.py`): The single data-access façade injected into services and controllers. Built via `get_repositories(session, group_id, household_id)`. Never instantiate repository classes directly.

**`BaseService`** (`mealie/services/_base_service/__init__.py`): Provides `self.dirs` (AppDirs), `self.settings` (AppSettings), and `self.logger` to all services. Call `super().__init__()` **last** in subclass constructors.

**`@controller(router)`** (`mealie/routes/_base/controller.py`): Converts a class into a FastAPI CBV. Route methods are decorated with `@router.get/post/put/delete` on the class; the decorator registers them. All class-level type annotations become DI-injected constructor params. Attributes prefixed with `_` are excluded from DI.

**`HttpRepo[C, R, U]`** (`mealie/routes/_base/mixins.py`): CRUD mixin for controllers. Instantiate as a `@cached_property`. Catches `NoResultFound` → 404, other exceptions → 400, always rolls back on error. Override `registered_exceptions()` for domain-specific messages.

**`useStore()` factory** (`frontend/app/composables/partials/use-store-factory.ts`): Generates a `{ store, actions }` pair from an API endpoint. The `store` is a shared module-level `Ref<T[]>`; `actions` exposes `getAll`, `createOne`, `updateOne`, `deleteOne`. Auto-hydrates on first access.

## Patterns and Conventions

### Creating a New Backend Route

1. Create a controller class extending `BaseUserController` (or `BaseAdminController` for admin-only).
2. Declare dependencies as typed class attributes (FastAPI DI wires them).
3. Add `@cached_property` for repos and services.
4. Decorate the class with `@controller(router)` where `router` is a module-level `UserAPIRouter`.
5. Register the router in the appropriate `__init__.py`.
6. Raise domain exceptions from `mealie/core/exceptions.py`; never `HTTPException` from service layer.

See `mealie/routes/groups/controller_labels.py` for a complete reference.

### Creating a New Pydantic Schema

Follow the Create → Save → Update → Out inheritance chain:
- `Create*` / `*In`: user-supplied fields only, no IDs.
- `Save*`: adds `group_id`, `household_id` (injected by service, never by user).
- `Update*`: adds primary key for PUT endpoints.
- `*Out` / `*InDB`: adds timestamps, nested relations. Must have `ConfigDict(from_attributes=True)` — this is NOT inherited from `MealieModel`.
- Add `loader_options() -> list[LoaderOption]` classmethod with `selectinload`/`joinedload` for every nested field — omitting this causes silent N+1 queries.
- Use `UpdatedAtField()` (not plain `Field()`) for any `updated_at` column.
- Call `Model.model_rebuild()` at file bottom when circular references exist between schemas.

### Creating a New ORM Model

1. Inherit from both `SqlAlchemyBase` and `BaseMixins`.
2. Decorate `__init__` with `@auto_init()`. Body should be `pass`.
3. Use `GUID` for all PKs and FKs (not raw `UUID` or `str`).
4. Use `NaiveDateTime` for all timestamps (stores UTC without tzinfo).
5. Add `group_id: Mapped[GUID] = mapped_column(GUID, ForeignKey('groups.id'), nullable=False, index=True)` for any group-scoped entity.
6. Add a `UniqueConstraint('slug', 'group_id')` for entities that must be unique within a group, not globally.
7. Add `name_normalized` shadow column and a `@event.listens_for(Model.name, 'set')` listener that calls `Model.normalize(value)`.
8. Register the model in `mealie/db/models/_all_models.py` or Alembic will not detect the table.

See `mealie/db/models/recipe/recipe.py` for a complete reference.

### Creating a New Repository

1. Subclass `HouseholdRepositoryGeneric[Schema, Model]` (household-scoped) or `GroupRepositoryGeneric[Schema, Model]` (group-scoped).
2. Add a `@cached_property` entry in `AllRepositories` (`mealie/repos/all_repositories.py`).
3. For slug uniqueness, implement the retry-on-collision loop (up to 10 attempts, append ` (N)` to name on each retry). See `repository_group.py` for the copy-paste pattern.
4. Use `self.session.execute(q).unique().scalars().all()` (`.unique()` required when relationships are eagerly loaded).
5. Use `row-by-row delete_many()` (not bulk DELETE) to trigger SQLAlchemy cascade rules correctly on PostgreSQL.

### Adding a New Store Composable (Frontend)

1. Declare module-level `const store: Ref<T[]> = ref([])` and `const loading = ref(false)`.
2. Export `useXStore()` that calls `useStore(storeKey, store, loading, api)` from `partials/`.
3. Export `resetXStore()` that zeroes both refs.
4. Add `resetXStore()` call inside `clearAllStores()` in `store/index.ts`.
5. Add the export to `store/index.ts`.

### Writing Integration Tests

- Use `TestUser.token` as `headers=` arg: `api_client.get(url, headers=unique_user.token)`.
- Use `unique_user.repos.*` for white-box DB assertions.
- Use `api_routes.*` constants for URL paths — never raw strings.
- Create test data with `random_string()` from `tests/utils/factories.py` to avoid unique-constraint collisions.
- Module-scoped users; function-scoped resources with `yield + finally` cleanup.
- After any `monkeypatch.setenv()`, call `get_app_settings.cache_clear()` immediately.

### Naming Conventions

| Context | Convention |
|---------|-----------|
| Python files/modules | `snake_case` |
| Python classes | `PascalCase` |
| Pydantic schema suffixes | `Create*`, `Save*`, `Update*`, `*Out`, `*Pagination` |
| ORM model classes | `PascalCase` + optional `Model` suffix (e.g. `RecipeModel`, `Tag`) |
| Repository classes | `Repository<Domain>` |
| Service classes | `<Domain>Service` |
| TypeScript/Vue files | `kebab-case` filenames |
| Vue components | `PascalCase` (`RecipeCard.vue`) |
| Composables | `use-<domain>.ts`, exported as `use<Domain>()` |
| Store composables | `use-<entity>-store.ts` |
| API client classes | `PascalCase` + `API` or `Api` suffix |
| Frontend route guards | `<permission>-only.ts` |

### Import Conventions

**Backend**: Absolute imports from `mealie.*` throughout — no relative imports in service or route files. `TYPE_CHECKING` guards for circular imports in ORM models.

**Frontend**: `~` alias maps to `frontend/app/`. Use `~/composables/...`, `~/lib/api/...`, `~/types/...`. No barrel `index.ts` re-exports in most directories — import by path. Nuxt auto-imports composables and components — no explicit import needed for them.

## Development Workflow

### Building and Running

```bash
# First-time setup
uv sync --extra pgsql --group dev
cd frontend && yarn install && cd ..
uv run pre-commit install

# Run backend only
uv run python mealie/app.py

# Run full dev stack (Postgres + Mailpit)
docker compose -f docker/docker-compose.dev.yml up

# Build distributable package
uv build --out-dir dist
cd frontend && yarn generate && cd ..  # frontend static files
```

### Testing

```bash
# Full backend check (required before PR)
task py:check

# Full frontend check (required before PR)
task ui:check

# Backend tests against both SQLite and PostgreSQL
# CI runs: pytest with DB_ENGINE=sqlite, then DB_ENGINE=postgres + services
uv run pytest

# Specific test file
uv run pytest tests/unit_tests/test_config.py

# Frontend unit tests
cd frontend && yarn test:ci

# E2E (requires Docker)
cd tests/e2e && docker compose -f docker/docker-compose.yml up -d
yarn playwright test
```

### Tooling

- **Ruff**: linting + formatting, `line-length=120`, `target-version=py312`, rule sets B/C4/C90/DTZ/E/F/I/T/UP. Replaces black, isort, flake8.
- **MyPy**: strict optional, Pydantic plugin enabled, `python_version=3.12`. Configured in `pyproject.toml`.
- **ESLint + Prettier**: `vue/component-api-style: script-setup only`, `vue/no-v-html: error`, `no-tabs: error`, `max-warnings=0` in CI. Config in `frontend/eslint.config.mjs` and `frontend/.prettierrc`.
- **Pylint**: defined in `.pylintrc` but NOT wired to CI or pre-commit — informational only.
- **Pre-commit**: checks YAML/JSON/TOML validity, EOF newline, trailing whitespace.

### Alembic Migrations

```bash
# Generate a new migration (after modifying ORM models)
task py:migrate -- "description of change"
# Equivalent to:
uv run alembic --config mealie/alembic/alembic.ini revision --autogenerate -m "description"
```

**Every migration must**:
- Use `with op.batch_alter_table(...)` for any column/constraint change (SQLite compatibility).
- Check dialect via `op.get_context().dialect.name == 'postgresql'` for PostgreSQL-specific operations.
- Use inline `sa.table()` stubs instead of importing live ORM models.
- Add a `server_default` when adding a NOT NULL column to a populated table.
- Deduplicate rows before adding a UNIQUE constraint if duplicates may exist.
- Use `downgrade: pass` (with explanation comment) for irreversible data migrations.

### Regenerating TypeScript Types

After any Pydantic schema change, types must be regenerated so the frontend stays in sync:

```bash
task dev:generate
# This calls dev/code-generation/main.py which runs pydantic-to-typescript2
# per module, deduplicates enum names, and runs yarn lint --fix
```

**Never manually edit** any file in `frontend/app/lib/api/types/` — they will be overwritten.

## Things to Know

**`group_id=None` vs `group_id=NOT_SET`**: In `AllRepositories`, passing `group_id=None` still applies a `WHERE group_id IS NULL` filter. To bypass scoping entirely (admin access), use the `NOT_SET` sentinel from `mealie/repos/_utils.py`. Confusing these two produces silent data leaks or empty results.

**`update_at` column typo**: The timestamp column is literally named `update_at` in the database (not `updated_at`). An ORM synonym `updated_at` exists for Python code. In raw SQL or migrations, always use `update_at`.

**`self.recipes` vs `self.group_recipes`**: `BaseRecipeController` exposes two recipe repos. `self.recipes` is household-scoped (for writes). `self.group_recipes` is group-scoped (for reads/searches, to see all households' recipes). Using the wrong one causes silent data-scope bugs.

**`data` is always `T | null`**: `RequestResponse<T>` from the frontend API client has `data: T | null`. Always guard: `if (data) { ... }`. TypeScript does not prevent you from accessing `data.field` without a null check.

**camelCase in JSON, snake_case in Python**: `MealieModel` auto-translates. Never hardcode camelCase field names in Python code; never hardcode snake_case field names in TypeScript responses.

**Module-level store refs are process-lifetime singletons**: Call `clearAllStores()` on logout. If skipped, the previous user's data is visible to the next logged-in session.

**`async_init()` requires a `session` kwarg**: ORM models decorated with `@auto_init()` require `session=db_session` at construction time to hydrate relationships. Omitting it silently skips relationship initialization.

**`from_attributes=True` is NOT inherited**: Every `*Out` / `*InDB` Pydantic schema that maps to an ORM object must declare `model_config = ConfigDict(from_attributes=True)` explicitly.

**Recipe assets live under `{recipe_id}/`, not `{slug}/`**: Use `Recipe.directory_from_id(recipe_id)` for asset paths. `check_assets()` handles the legacy slug-named migration.

**`pagination_seed` required for random order**: Calling the recipes API with `order_by=random` without `pagination_seed` raises a 422 error. Pass any stable integer (e.g. hash of session ID).

**CORS is dev-only**: The `CORSMiddleware` is only registered when `PRODUCTION=False`. Production deployments must configure CORS at the reverse-proxy level.

**APScheduler = multiple processes = multiple runs**: APScheduler jobs start in the FastAPI lifespan, so multi-worker deployments (`uvicorn --workers N`) run every scheduled task N times. The recommended deployment is a single worker process.

**en-US only for i18n contributions**: The `frontend/app/lang/` directory contains 40+ locale files. Only `en-US.json` may be modified by contributors. All other locales are managed by Crowdin and will be overwritten.

**Announcement file naming**: Files in `frontend/app/components/Domain/Announcement/Announcements/` must follow `YYYY-MM-DD_N_slug.vue`. A test (`announcements.test.ts`) validates this pattern.

**`loader_options()` must be updated with schema fields**: Adding a nested schema field that maps to an ORM relationship without updating `loader_options()` causes silent N+1 queries — no error, just slow performance.

## Security-Critical Areas

These files require careful human review before any change:

| File | Risk |
|------|------|
| `mealie/core/security/security.py` | JWT creation (HS256), URL-safe token generation |
| `mealie/core/security/hasher.py` | bcrypt password hashing (silent 72-byte truncation) |
| `mealie/core/security/providers/` | Auth bypass risk in LDAP, OIDC, credentials providers |
| `mealie/core/dependencies/dependencies.py` | JWT validation, admin enforcement, long-lived token lookup |
| `mealie/core/settings/settings.py` | SECRET/SESSION_SECRET generation, lockout limits |
| `mealie/routes/auth/auth.py` | Login, logout, token refresh endpoints |
| `mealie/app.py` | CORS policy, SessionMiddleware SECRET |
| `mealie/alembic/versions/*.py` | Sequential migration chain — editing existing files corrupts the chain |
| `frontend/app/middleware/*.ts` | Client-side guards only — backend must independently enforce permissions |

**Never bypass**: Auth middleware, group_id filtering, `validate_file_token` for file downloads.

**Path traversal guards**: `safe_local_path()` in migrators and `_backup_path()` in admin backups must always be used when constructing paths from user-supplied strings. Never join raw user input to a directory path.

## Domain Terminology

| Term | Meaning in Codebase |
|------|---------------------|
| **Group** | Top-level multi-tenant unit. Users, recipes, labels belong to a group. `group_id` is the primary isolation key. |
| **Household** | Sub-unit within a group. Meal plans, shopping lists, cookbooks, webhooks belong to a household. A group has one or more households. |
| **`private_group`** / `private_household` | Visibility flag — controls whether the public explore endpoints return the group's/household's data. |
| **slug** | URL-safe string derived from the entity name. Unique within `(group_id, slug)` — NOT globally. |
| **`recipe_yield`** | Free-text string (e.g., "12 cookies"). Paired with `recipe_yield_quantity` float for scaling math. |
| **`GUID`** | Custom SQLAlchemy TypeDecorator — UUID stored as hex string in SQLite, native UUID in PostgreSQL. All PKs use this. |
| **`NaiveDateTime`** | Custom TypeDecorator — UTC datetime without tzinfo, compatible with both SQLite and PostgreSQL. |
| **`AllRepositories`** | The single data-access façade. Always constructed with `group_id` and `household_id` for tenant scoping. |
| **`PrivateUser`** | The authenticated user schema returned by `get_current_user()`. Includes `group_id`, `household_id`, `admin`, `can_manage`, etc. |
| **`MealieModel`** | Base Pydantic model for all API schemas. Handles camelCase aliasing, UTC timezone injection, and ORM mapping helpers. |
| **`loader_options()`** | Classmethod on `*Out` schemas returning SQLAlchemy eager-load directives. Called by repos to avoid N+1 queries. |
| **`EventBusService`** | Internal pub/sub for domain events (recipe created, shopping list updated, etc.). Dispatches to Apprise and HTTP webhooks. |
| **`RequestResponse<T>`** | Frontend API response envelope `{ response, data: T|null, error }`. Errors are never thrown — always check `.error`. |
| **`useStore()` factory** | Frontend function that generates a shared CRUD store from an API endpoint. Module-level refs = shared singleton state. |
| **`NOT_SET`** | Sentinel value (`mealie/repos/_utils.py`) used to bypass group/household scoping in admin repository queries. Different from `None`. |
| **`task dev:generate`** | Regenerates frontend TypeScript types from Pydantic schemas. Must be run after any schema change. |
| **`DAILY_SCHEDULE_TIME_UTC`** | Uses server OS timezone (`tzlocal()`). Ensure container TZ env var matches intended timezone. |

## Commit and PR Conventions

- **Conventional Commits** required: `feat:`, `fix:`, `docs:`, `chore:`, `dev:` prefixes.
- PR titles must start with a Conventional Commit prefix.
- Reference issues with `Fixes #<n>` syntax.
- PRs target `mealie-next` branch (not `main`).
- Fork from `mealie-next`.
- **Disclose LLM/AI assistance** in every PR description — required by `.github/pull_request_template.md`.
- Open draft PRs early for major changes.
- Branch naming patterns: `ai-feature/<description>`, `renovate/<package>-<version>.x`, `<short-description-kebab-case>`.
