---
name: add-multitenant-test
description: "
  Add a new entity to the Mealie multitenant isolation test suite by implementing
  ABCMultiTenantTestCase and registering in all_cases.
  Use when adding a new group-scoped or household-scoped entity that needs isolation verification.
  Do NOT use for adding regular integration tests (use add-integration-test instead).
---

## Before You Start

Read these files:
- `tests/multitenant_tests/case_abc.py` — `ABCMultiTenantTestCase` abstract base class
- `tests/multitenant_tests/case_categories.py` — simplest concrete example
- `tests/multitenant_tests/test_multitenant_cases.py` — `all_cases` list and parametrized test
- `tests/fixtures/fixture_multitenant.py` — `multitenants` fixture with two isolated users
- `tests/utils/api_routes/__init__.py` — URL constants for the API list endpoint

## Step 1: Create the case file

```python
# tests/multitenant_tests/case_{entity}.py
from __future__ import annotations

import contextlib
from typing import Generator
from uuid import UUID

from mealie.repos.all_repositories import AllRepositories
from mealie.schema.{domain}.{entity} import Save{Entity}
from tests.multitenant_tests.case_abc import ABCMultiTenantTestCase
from tests.utils import api_routes
from tests.utils.factories import random_string


class {Entity}MultiTenantTestCase(ABCMultiTenantTestCase):
    """Verifies that {Entity} data is isolated between groups."""

    # The set of IDs created for this test (used for isolation assertions)
    item_ids: set[str] = set()

    def seed_action(self, group_id: UUID) -> set[str]:
        """
        Create test items for a group. Returns a set of the created item IDs.
        Called once per group (group 1 and group 2 separately).
        """
        created_ids = set()
        for _ in range(5):  # create 5 items per group
            item = self.database.{entities}.create(
                Save{Entity}(
                    name=random_string(10),
                    group_id=group_id,
                )
            )
            created_ids.add(str(item.id))
        return created_ids

    def seed_multi(self, group1_id: UUID, group2_id: UUID) -> tuple[set[str], set[str]]:
        """
        Seed items for BOTH groups. The same name in both groups tests that
        the unique constraint is (name, group_id) not just (name).
        """
        shared_name = random_string(10)  # same name in both groups — tests compound uniqueness
        ids1 = set()
        ids2 = set()
        for _ in range(5):
            item1 = self.database.{entities}.create(
                Save{Entity}(name=random_string(10), group_id=group1_id)
            )
            ids1.add(str(item1.id))
            item2 = self.database.{entities}.create(
                Save{Entity}(name=random_string(10), group_id=group2_id)
            )
            ids2.add(str(item2.id))
        return ids1, ids2

    def get_all(self, token: dict) -> list:
        """Fetch all items via the API using the given auth token."""
        response = self.client.get(api_routes.{entities}, headers=token)
        assert response.status_code == 200
        return response.json()["items"]

    def cleanup(self) -> Generator[None, None, None]:
        """Clean up all created items."""
        yield  # tests run here
        for item_id in self.item_ids:
            with contextlib.suppress(Exception):
                self.database.{entities}.delete(item_id)
        self.item_ids.clear()
```

## Step 2: Register in all_cases

```python
# tests/multitenant_tests/test_multitenant_cases.py
from tests.multitenant_tests.case_{entity} import {Entity}MultiTenantTestCase

all_cases = [
    # ... existing cases ...
    {Entity}MultiTenantTestCase,  # ADD THIS
]
```

The parametrized test automatically runs isolation scenarios against all cases in `all_cases`.

## Step 3: Understand what the test verifies

The abstract test case framework runs these scenarios:
1. `test_multitenant_cases_get_all` — seeds 5 items in group 1, verifies group 2 API returns 0 of them
2. `test_multitenant_cases_get_all_multi` — seeds 5 items per group with the same names, verifies each group only sees its own
3. `test_multitenant_cases_seed_action` — seeds in group 1 using `seed_action`, verifies count

This tests that the UNIQUE constraint is `(name, group_id)` not just `(name)`. If your entity has a global unique constraint, `seed_multi()` will raise `IntegrityError` — that's a bug to fix in the model.

## Step 4: Handle the unfiltered_database fixture

```python
# The test uses unfiltered_database which has group_id=None (not NOT_SET)
# This means queries go to WHERE group_id IS NULL — not all data
# The multitenants fixture creates real groups and users
# Your seed_action() receives the actual group_id to use
```

## Verify

```bash
# Run just the new case:
uv run pytest tests/multitenant_tests/test_multitenant_cases.py -k "{entity}" -v

# Run the full multitenant suite:
uv run pytest tests/multitenant_tests/ -v
```

## Common Mistakes

1. **Global unique constraint on name**: If `{Entity}Model` has `UniqueConstraint("name")` (not scoped to `group_id`), `seed_multi()` with the same name will raise `IntegrityError`. Fix the model to use `UniqueConstraint("name", "group_id")`.
2. **`test_multitenant_cases_get_all` relies on default page size**: The test checks `len(data) == len(item_ids)` without pagination. If default page size is less than 5 (the seeded count), the assertion silently under-counts.
3. **Cleanup not called on failure**: The `ABCMultiTenantTestCase` uses a context manager pattern — if `cleanup()` yield is inside a try/finally, failures still clean up. Verify your case's `cleanup()` runs in the finally block.
4. **`multitenants` fixture is module-scoped**: Seeded rows from one parametrized run contaminate later runs that share the same users if cleanup doesn't run.
