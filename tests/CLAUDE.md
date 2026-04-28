# tests/ — Python Test Suite

Integration, unit, multitenant, and e2e tests. All tests use pytest against a real SQLite/PostgreSQL database — no DB mocking.

## Quick Commands

```bash
# Run all tests (used in CI)
uv run pytest

# Run a specific test file
uv run pytest tests/unit_tests/test_config.py

# Run with verbose output
uv run pytest -v tests/integration_tests/user_recipe_tests/

# E2E tests (requires Docker)
cd tests/e2e && docker compose -f docker/docker-compose.yml up -d
yarn playwright test
```

## Test Structure

| Directory | Scope | DB Access |
|-----------|-------|----------|
| `integration_tests/` | HTTP API through FastAPI TestClient | Via TestClient (real DB) |
| `unit_tests/` | Service classes, schemas, repos, security | Via repos directly |
| `multitenant_tests/` | Cross-group data isolation | Both HTTP and repos |
| `tests/e2e/` | Full browser flows via Playwright | Via full Docker stack |

## `TestUser` — The Core Fixture

All integration tests receive a `TestUser` dataclass from fixtures:

```python
@dataclass
class TestUser:
    email: str
    _group_id: UUID4          # UUID object
    _household_id: UUID4      # UUID object
    group_id: str             # str property
    household_id: str         # str property
    token: dict               # {"Authorization": "Bearer <jwt>"}
    repos: AllRepositories    # tenant-scoped DB access
    password: str             # always 'fake-password'
```

```python
# HTTP call with auth
response = api_client.get(
    api_routes.recipes_slug(slug),
    headers=unique_user.token,  # pass directly as headers=
)

# White-box DB assertion
db_recipe = unique_user.repos.recipes.get_one(slug, key="slug")
assert db_recipe.name == "My Recipe"
```

## Fixture Scopes

| Fixture | Scope | Created How |
|---------|-------|-------------|
| `api_client` | session | FastAPI TestClient with DB session override |
| `session` | module | SQLAlchemy session |
| `unique_user` | module | Registration API + login |
| `unique_user_fn_scoped` | function | Same but per-test |
| `admin_user` | module | Admin API endpoint |
| `random_recipe` | function | Repo create + `finally` delete |
| `h2_user` | module | Same group, different household |
| `g2_user` | module | Different group entirely |
| `multitenants` | module | Two completely independent users |
| `unfiltered_database` | session | `AllRepositories(NOT_SET, NOT_SET)` |

**Module-scoped users are never deleted** — they accumulate in the shared SQLite DB across all modules. Never assert on exact global user counts.

## Writing Tests

### URL Constants

```python
from tests.utils import api_routes

# Use api_routes constants — never raw URL strings
url = api_routes.recipes  # '/api/recipes'
url = api_routes.recipes_slug(slug)  # '/api/recipes/{slug}'
```

### Test Data

```python
from tests.utils.factories import random_string, random_email

# Always use random data — prevents unique constraint collisions
recipe_name = random_string(10)
user_email = random_email()
```

### Assertions

```python
from tests.utils.assertion_helpers import assert_deserialize, assert_ignore_keys

# assert_deserialize checks status code and returns .json()
data = assert_deserialize(response, 200)

# assert_ignore_keys skips server-generated fields
assert_ignore_keys(actual, expected, ignore_keys=["id", "createdAt"])
```

### Settings Cache

```python
# After monkeypatching env vars, ALWAYS clear the cache
monkeypatch.setenv("ALLOW_SIGNUP", "false")
get_app_settings.cache_clear()  # REQUIRED
```

Forgetting this = silent test pollution (cached settings ignore the patch).

## Resource Cleanup Pattern

```python
def test_my_thing(unique_user):
    recipe = unique_user.repos.recipes.create(some_data)
    try:
        # test body
        ...
    finally:
        with contextlib.suppress(NoResultFound):
            unique_user.repos.recipes.delete(recipe.id)
```

The `contextlib.suppress(NoResultFound)` handles the case where the test itself already deleted the resource.

## Environment Setup (`conftest.py`)

Environment variables are patched **before app imports** via `MonkeyPatch()` at the top of `tests/conftest.py`. This is critical — moving these after app imports breaks module-level initialization.

Default test env:
- `PRODUCTION=false`
- `TESTING=true`
- `ALLOW_SIGNUP=true`
- `OPENAI_API_KEY=dummy-api-key` (must monkeypatch HTTP to test AI features)

## Multitenant Tests

`tests/multitenant_tests/` uses an abstract test case pattern:

```python
class CategoryTestCase(ABCMultiTenantTestCase):
    def seed_action(self, group_id) -> set[str]: ...
    def get_all(self, token) -> list: ...
    def cleanup(self): ...
```

A single parametrized test in `test_multitenant_cases.py` runs isolation scenarios against all entity types. To add a new entity, create a `case_<entity>.py` with the concrete class and add it to the `all_cases` list.

## SSE Response Parsing

```python
from tests.utils.helpers import parse_sse_events

response = api_client.get(url, headers=user.token)
events = parse_sse_events(response.text)  # list of {'event': str, 'data': str}
```

FastAPI's TestClient doesn't natively stream SSE — parse the raw text.
