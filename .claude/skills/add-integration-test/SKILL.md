---
name: add-integration-test
description: "
  Scaffold a new pytest integration test file for a Mealie API endpoint using the TestUser fixture,
  api_routes constants, assert_deserialize, and proper cleanup.
  Use when adding tests for new API endpoints or extending coverage of existing ones.
  Do NOT use for unit tests of service classes (those go in unit_tests/).
---

## Before You Start

Read these files:
- `tests/integration_tests/user_recipe_tests/test_recipe_crud.py` — canonical CRUD test pattern
- `tests/integration_tests/user_household_tests/test_household_permissions.py` — permission matrix tests
- `tests/utils/fixture_schemas.py` — `TestUser` dataclass
- `tests/utils/api_routes/__init__.py` — URL constants (NEVER use raw strings)
- `tests/utils/factories.py` — `random_string()`, `random_email()` for collision-free test data
- `tests/utils/assertion_helpers.py` — `assert_deserialize`, `assert_ignore_keys`

## Step 1: Determine test location

```
tests/integration_tests/
├── admin_tests/          # admin-only endpoints
├── user_recipe_tests/    # recipe CRUD, scraper, timeline
├── user_household_tests/ # shopping lists, meal plans, cookbooks
└── user_group_tests/     # labels, seeder, migrations
```

## Step 2: Create the test file

```python
# tests/integration_tests/{domain}_tests/test_{entity}.py
import contextlib
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from tests.utils import api_routes
from tests.utils.assertion_helpers import assert_deserialize, assert_ignore_keys
from tests.utils.factories import random_string
from tests.utils.fixture_schemas import TestUser


# Module-scoped user — shared across all tests in this file
# For test-isolation, use function-scoped unique_user_fn_scoped instead
pytestmark = pytest.mark.usefixtures("api_client")


class Test{Entity}CRUD:
    def test_create_{entity}(self, api_client: TestClient, unique_user: TestUser):
        # Always use random data to avoid unique constraint collisions
        payload = {
            "name": random_string(10),
            "description": random_string(20),
        }

        response = api_client.post(
            api_routes.{entities},  # NEVER use raw URL strings
            json=payload,
            headers=unique_user.token,  # pass directly as headers=
        )
        created = assert_deserialize(response, 201)

        # Dual assertion: HTTP response AND direct DB state
        assert created["name"] == payload["name"]
        # White-box DB assertion:
        db_item = unique_user.repos.{entities}.get_one(created["id"])
        assert db_item is not None
        assert db_item.name == payload["name"]

        # Cleanup — use finally so it runs even if assertions fail
        try:
            yield created
        finally:
            with contextlib.suppress(Exception):
                unique_user.repos.{entities}.delete(created["id"])

    def test_get_{entity}(self, api_client: TestClient, unique_user: TestUser):
        # Create test data through the repo (faster than API for setup)
        from mealie.schema.{domain}.{entity} import Save{Entity}
        item = unique_user.repos.{entities}.create(
            Save{Entity}(
                name=random_string(10),
                group_id=unique_user._group_id,
            )
        )
        try:
            response = api_client.get(
                api_routes.{entities}_item_id(item.id),
                headers=unique_user.token,
            )
            data = assert_deserialize(response, 200)
            assert_ignore_keys(
                data,
                {"name": item.name},
                ignore_keys=["id", "createdAt", "updatedAt"],  # dynamic fields
            )
        finally:
            with contextlib.suppress(Exception):
                unique_user.repos.{entities}.delete(item.id)

    def test_cross_group_isolation(self, api_client: TestClient, unique_user: TestUser, g2_user: TestUser):
        """Verify user cannot access another group's data."""
        # Create item in g2's group
        from mealie.schema.{domain}.{entity} import Save{Entity}
        item = g2_user.repos.{entities}.create(
            Save{Entity}(
                name=random_string(10),
                group_id=g2_user._group_id,
            )
        )
        try:
            # unique_user trying to access g2_user's item should get 404
            response = api_client.get(
                api_routes.{entities}_item_id(item.id),
                headers=unique_user.token,
            )
            assert response.status_code == 404
        finally:
            with contextlib.suppress(Exception):
                g2_user.repos.{entities}.delete(item.id)
```

## Key patterns

**URL constants only** — never raw strings:
```python
# CORRECT:
api_routes.recipes  # '/api/recipes'
api_routes.recipes_slug(slug)  # '/api/recipes/{slug}'

# WRONG:
api_client.get("/api/recipes")  # typos won't be caught
```

**Auth header pattern:**
```python
api_client.get(url, headers=unique_user.token)
# unique_user.token is {"Authorization": "Bearer <jwt>"}
```

**JSON response keys are camelCase:**
```python
assert response.json()["groupId"] == str(unique_user._group_id)
# NOT response.json()["group_id"] — that KeyError will be silent on 200
```

**Settings cache invalidation:**
```python
def test_with_setting(monkeypatch, ...):
    monkeypatch.setenv("ALLOW_SIGNUP", "false")
    get_app_settings.cache_clear()  # REQUIRED — lru_cache ignores env changes
    ...
```

## Verify

```bash
uv run pytest tests/integration_tests/{domain}_tests/test_{entity}.py -v
# Run full suite to check for regressions:
uv run pytest tests/ -x
```

## Common Mistakes

1. **Module-scoped `unique_user` collects state**: Module-scoped users are never deleted and accumulate in the shared SQLite DB. Never assert on exact global user counts.
2. **Hardcoded recipe name like 'Test Recipe'**: Identical names across tests cause `IntegrityError` on slug collision. Always use `random_string(10)`.
3. **`response.json()['group_id']` KeyError**: JSON keys are camelCase (`groupId`). Use `assert_ignore_keys` which handles this, or explicitly use `groupId`.
4. **No cleanup in `finally`**: If the test creates a resource and then fails, subsequent tests may see leftover data. Always clean up in a `finally` block with `contextlib.suppress`.
