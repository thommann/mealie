---
name: add-service
description: "
  Scaffold a new business logic service subclassing BaseService with constructor dependency injection.
  Use when adding complex business logic that spans multiple repos.
  Do NOT use for simple CRUD that can be handled by HttpRepo mixin, or for adding methods to existing services.
---

## Before You Start

Read these files:
- `mealie/services/_base_service/__init__.py` — `BaseService` providing dirs, settings, logger
- `mealie/services/recipe/recipe_service.py` — `RecipeServiceBase` pattern with dual repo scoping
- `mealie/services/group_services/group_service.py` — `GroupService` with `AllRepositories` injection
- `mealie/services/household_services/shopping_lists.py` — complex service with custom logic
- `mealie/core/exceptions.py` — domain exceptions to raise from services

## Step 1: Create the service file

```python
# mealie/services/{domain}/{entity}_service.py
from mealie.repos.all_repositories import AllRepositories
from mealie.schema.user.user import PrivateUser
from mealie.schema.household.household import HouseholdInDB
from mealie.services._base_service import BaseService
from mealie.core.exceptions import NoEntryFound, PermissionDenied


class {Entity}Service(BaseService):
    def __init__(
        self,
        repos: AllRepositories,
        user: PrivateUser,
        # Add other deps: household: HouseholdInDB, translator: Translator
    ):
        self.repos = repos
        self.user = user
        # super().__init__() MUST be called LAST — it sets self.dirs, self.settings, self.logger
        super().__init__()

    def get_one(self, item_id: UUID4) -> {Entity}Out:
        item = self.repos.{entities}.get_one(item_id)
        if not item:
            raise NoEntryFound(f"{entity} {item_id} not found")
        return item

    def create(self, data: Create{Entity}) -> {Entity}Out:
        # Inject tenant context before saving — never let service accept group_id from user
        save_data = data.cast(Save{Entity}, group_id=self.user.group_id)
        return self.repos.{entities}.create(save_data)

    def update(self, item_id: UUID4, data: Update{Entity}) -> {Entity}Out:
        item = self.get_one(item_id)  # raises NoEntryFound if missing
        self._check_permission(item)
        return self.repos.{entities}.update(item_id, data)

    def delete(self, item_id: UUID4) -> None:
        item = self.get_one(item_id)
        self._check_permission(item)
        self.repos.{entities}.delete(item_id)

    def _check_permission(self, item: {Entity}Out) -> None:
        """Raise PermissionDenied if user cannot modify this item."""
        if item.group_id != self.user.group_id:
            raise PermissionDenied("Cannot modify items from another group")
        # Check can_manage for privileged operations:
        # if not self.user.can_manage:
        #     raise PermissionDenied("Requires manage permission")
```

**`super().__init__()` MUST be the last line** in the constructor. `BaseService.__init__()` assigns `self.dirs`, `self.settings`, and `self.logger` — referencing these before the super() call raises `AttributeError`.

## Step 2: Dual repo scope pattern (for recipe-like services)

If your service needs both household-scoped writes and group-scoped reads:

```python
class {Entity}ServiceBase(BaseService):
    def __init__(self, repos: AllRepositories, user: PrivateUser, ...):
        self.repos = repos  # household-scoped (for writes)
        # group_recipes pattern — use cross_household_repos for reads
        self.group_{entities} = repos.{entities}  # but initialized with group_id only
        # Validation: ensure user's group matches the data being accessed
        super().__init__()
```

## Step 3: Wire into the controller

```python
# In the controller:
@cached_property
def service(self) -> {Entity}Service:
    return {Entity}Service(
        repos=self.repos,
        user=self.user,
    )

@router.post("", response_model={Entity}Out, status_code=201)
def create_one(self, data: Create{Entity}):
    return self.service.create(data)  # service handles tenant injection
```

## Step 4: Exception translation

Services raise from `mealie/core/exceptions.py`. The controller's `registered_exceptions` property maps these to HTTP responses:

| Exception | HTTP Status |
|-----------|-------------|
| `PermissionDenied` | 403 |
| `NoEntryFound` | 404 |
| `UnexpectedNone` | 500 |
| `RecursiveRecipe` | 400 |
| `RateLimitError` | 429 |

Never import `HTTPException` from FastAPI into a service.

## Verify

```bash
uv run ruff format mealie/services/{domain}/{entity}_service.py
uv run mypy mealie/services/{domain}/{entity}_service.py
uv run pytest tests/ -k "{entity}" -v
```

## Common Mistakes

1. **`super().__init__()` not last**: If you reference `self.logger` before `super().__init__()`, you get `AttributeError: 'MyService' object has no attribute 'logger'`.
2. **Service calling `HTTPException`**: Services must not import FastAPI. Raise `PermissionDenied` or `NoEntryFound` from `mealie/core/exceptions.py` instead.
3. **Service accepting `group_id` from user input**: Always derive `group_id` from `self.user.group_id`. Never let callers specify which group they're operating on — that's a privilege escalation vector.
4. **`ShoppingListService` has no `BaseService`**: This is an existing inconsistency — `self.logger`, `self.dirs`, and `self.settings` are unavailable in that service. New services should always inherit `BaseService`.
