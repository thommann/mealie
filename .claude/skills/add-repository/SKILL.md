---
name: add-repository
description: "
  Scaffold a new domain repository by subclassing the correct base (GroupRepositoryGeneric or
  HouseholdRepositoryGeneric), registering it as a cached_property in AllRepositories.
  Use when adding a new entity that needs data access.
  Do NOT use for admin cross-tenant access (use NOT_SET sentinel instead).
---

## Before You Start

Read these files:
- `mealie/repos/repository_generic.py` — `RepositoryGeneric`, `GroupRepositoryGeneric`, `HouseholdRepositoryGeneric`
- `mealie/repos/all_repositories.py` — `AllRepositories` with `@cached_property` pattern
- `mealie/repos/repository_group.py` — group-scoped repo with slug collision retry
- `mealie/repos/repository_recipes.py` — complex repo with column aliases, custom queries
- `mealie/repos/_utils.py` — `NOT_SET` sentinel definition

## Step 1: Determine the correct base class

- `GroupRepositoryGeneric[Schema, Model]` — data is group-scoped (labels, cookbooks, reports)
- `HouseholdRepositoryGeneric[Schema, Model]` — data is household-scoped (shopping lists, meal plans)
- `RepositoryGeneric[Schema, Model]` — no tenant scoping (rarely used — only for users, server tasks)

## Step 2: Create the repository file

```python
# mealie/repos/repository_{entity}.py
from mealie.db.models.{domain}.{entity} import {Entity}Model
from mealie.repos.repository_generic import GroupRepositoryGeneric  # or Household*
from mealie.schema.{domain}.{entity} import {Entity}Out, Save{Entity}


class Repository{Entity}(GroupRepositoryGeneric[{Entity}Out, {Entity}Model]):
    # The base class provides: get_one, get_all, create, update, patch, delete,
    # delete_many, page_all — all automatically filtered by group_id.

    # Override these if needed:
    # def create(self, data): ...
    # def update(self, value, data): ...

    # For slug collision retry (copy from repository_group.py):
    def create(self, data: Save{Entity}) -> {Entity}Out:
        max_retries = 10
        original_name = data.name
        for attempt in range(max_retries):
            try:
                return super().create(data)
            except Exception:  # IntegrityError on slug collision
                self.session.rollback()
                data.name = f"{original_name} ({attempt + 1})"
        return super().create(data)  # let it fail on final attempt

    # For computed sort columns (e.g., user-specific rating):
    @property
    def column_aliases(self) -> dict:
        return {
            "rating": sa.case(...),
        }
```

**After `session.execute()` with relationships, always call `.unique()`:**
```python
# REQUIRED when relationships are eagerly loaded — prevents duplicate rows from joins
result = self.session.execute(q).unique().scalars().all()
```

**Use row-by-row delete for cascades:**
```python
def delete_many(self, ids: list[UUID4]) -> None:
    # DO NOT use bulk DELETE — PostgreSQL doesn't trigger cascade rules
    for item_id in ids:
        obj = self.get_one(item_id)
        if obj:
            self.session.delete(obj)
    self.session.commit()
```

## Step 3: Register in AllRepositories

```python
# mealie/repos/all_repositories.py
from mealie.repos.repository_{entity} import Repository{Entity}
from mealie.schema.{domain}.{entity} import {Entity}Out
from mealie.db.models.{domain}.{entity} import {Entity}Model

class AllRepositories:
    # ... existing cached properties ...

    @cached_property
    def {entities}(self) -> Repository{Entity}:
        return Repository{Entity}(
            self.session,
            group_id=self.group_id,
            household_id=self.household_id,
            schema=({Entity}Out, {Entity}Model),
        )
```

## Step 4: Use in controllers and services

```python
# In a controller:
@cached_property
def repo(self):
    return self.repos.{entities}  # auto-scoped by user's group/household

# Admin cross-tenant access:
from mealie.repos._utils import NOT_SET
admin_repos = get_repositories(session, group_id=NOT_SET, household_id=NOT_SET)
all_items = admin_repos.{entities}.get_all()  # sees all tenants

# WRONG — group_id=None means WHERE group_id IS NULL (not bypass):
# wrong_repos = get_repositories(session, group_id=None, household_id=None)
```

## Verify

```bash
uv run ruff format mealie/repos/repository_{entity}.py
uv run mypy mealie/repos/repository_{entity}.py
# Verify AllRepositories can instantiate
uv run python -c "
from mealie.repos.repository_factory import get_repositories
from mealie.db.db_setup import generate_session
print('AllRepositories imports OK')
"
```

## Common Mistakes

1. **`NOT_SET` vs `None`**: `group_id=None` filters to `WHERE group_id IS NULL`. `group_id=NOT_SET` skips the filter entirely. Confusing these causes silent data leaks or empty results.
2. **Missing `.unique()`**: When a query uses `selectinload()` and returns multiple rows, SQLAlchemy may produce duplicate results from the JOIN. Always call `.unique()` before `.scalars().all()`.
3. **Bulk DELETE bypasses cascades**: `session.execute(delete(Model))` does not trigger SQLAlchemy's cascade rules on PostgreSQL. Use `session.delete(obj)` row-by-row inside `delete_many()`.
4. **`HTTPException` in repository**: `mealie/repos/repository_cookbooks.py` raises `HTTPException` directly — this is a known anti-pattern. New repositories should raise `NoEntryFound` from `mealie/core/exceptions.py` instead.
