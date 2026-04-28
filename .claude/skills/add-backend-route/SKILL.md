---
name: add-backend-route
description: "
  Scaffold a complete new CBV controller and route module for a new domain in the Mealie FastAPI backend.
  Use when adding new API endpoints, creating new route files, building new REST resources.
  Do NOT use for adding a single method to an existing controller, for auth routes under mealie/routes/auth/,
  or for Socket.IO handlers.
---

## Before You Start

Read these exemplar files before writing any code:
- `mealie/routes/groups/controller_labels.py` — canonical reference for a complete group-scoped CBV controller
- `mealie/routes/households/controller_cookbooks.py` — household-scoped CRUD with event publishing
- `mealie/routes/_base/base_controllers.py` — base class hierarchy and DI attributes
- `mealie/routes/_base/mixins.py` — HttpRepo CRUD mixin
- `mealie/routes/_base/routers.py` — router types (UserAPIRouter vs AdminAPIRouter)

Decide which domain this belongs to:
- `mealie/routes/groups/` — group-scoped data (labels, settings, reports)
- `mealie/routes/households/` — household-scoped data (shopping lists, meal plans, cookbooks)
- `mealie/routes/recipe/` — recipe-related (add to existing base if possible)
- `mealie/routes/admin/` — cross-tenant admin operations

## Step 1: Create the controller file

```python
# mealie/routes/{domain}/controller_{entity}.py
from functools import cached_property

from mealie.routes._base import controller
from mealie.routes._base.base_controllers import BaseUserController  # or BaseCrudController for events
from mealie.routes._base.mixins import HttpRepo
from mealie.routes._base.routers import UserAPIRouter
from mealie.schema.{domain}.{entity} import (
    Create{Entity},
    {Entity}Out,
    {Entity}Pagination,
    Update{Entity},
)
from mealie.schema.response.pagination import PaginationQuery
from fastapi import Depends, Response

router = UserAPIRouter(prefix="/{entities}", tags=["{Domain}"])


@controller(router)
class {Entity}Controller(BaseUserController):  # use BaseCrudController if you need publish_event()
    # FastAPI injects these via Depends() automatically — no Depends() annotation needed here

    @cached_property
    def repo(self):
        return self.repos.{entities}  # AllRepositories accessor — add this first

    @cached_property
    def mixins(self):
        return HttpRepo[Create{Entity}, {Entity}Out, Update{Entity}](
            self.repo,
            self.logger,
            self.registered_exceptions,
        )

    @router.get("", response_model={Entity}Pagination)
    def get_all(self, q: PaginationQuery = Depends(PaginationQuery), response: Response = None):
        result = self.repo.page_all(pagination=q, override={Entity}Summary)
        result.set_pagination_guides(router.url_path_for("get_all"), q.model_dump())
        return result

    @router.post("", response_model={Entity}Out, status_code=201)
    def create_one(self, data: Create{Entity}):
        save_data = data.cast(Save{Entity}, group_id=self.group_id, household_id=self.household_id)
        return self.mixins.create_one(save_data)

    @router.get("/{item_id}", response_model={Entity}Out)
    def get_one(self, item_id: UUID4):
        return self.mixins.get_one(item_id)

    @router.put("/{item_id}", response_model={Entity}Out)
    def update_one(self, item_id: UUID4, data: Update{Entity}):
        return self.mixins.update_one(item_id, data)

    @router.delete("/{item_id}", status_code=204)
    def delete_one(self, item_id: UUID4):
        return self.mixins.delete_one(item_id)
```

**Key rules:**
- `UserAPIRouter` already injects `get_current_user` — never add `Depends(get_current_user)` again inside methods
- `AdminAPIRouter` is for cross-tenant admin routes only (`BaseAdminController.repos` has no group filter)
- Use `BaseCrudController` only when you need `self.publish_event()` and `self.user_id` for event dispatch
- `mapper.cast(Save{Entity}, group_id=..., household_id=...)` is the correct way to inject tenant context into user-supplied data

## Step 2: Register the router in the subdomain __init__.py

```python
# mealie/routes/{domain}/__init__.py
from mealie.routes.{domain}.controller_{entity} import router as {entity}_router

router = APIRouter()
router.include_router({entity}_router)
```

**Warning for households/__init__.py**: If your route path could conflict with `/mealplan`, register `mealplan_rules_router` BEFORE `mealplan_router`. Reversing this order silently breaks URL matching.

## Step 3: Register in mealie/routes/__init__.py

```python
from mealie.routes.{domain} import router as {domain}_router
api_router.include_router({domain}_router, prefix="/api")
```

## Step 4: Add error translation

In your controller, the `registered_exceptions` property (from `BaseUserController`) maps domain exceptions to translated messages. Override it if you have domain-specific exceptions:

```python
@property
def registered_exceptions(self):
    return {**super().registered_exceptions, My{Domain}Error: self.t("errors.my-domain-error")}
```

Services raise from `mealie/core/exceptions.py` — never raise `HTTPException` from service layer.

## Step 5: Add permission checks if needed

```python
@router.post("", response_model={Entity}Out, status_code=201)
def create_one(self, data: Create{Entity}):
    self.checks.can_manage()  # raises HTTP 403 internally — no if/return needed
    ...
```

Available checks: `can_manage()`, `can_organize()`, `can_invite()`, `can_manage_household()`.

## Verify

```bash
uv run ruff check mealie/routes/{domain}/controller_{entity}.py
uv run mypy mealie/routes/{domain}/controller_{entity}.py
uv run pytest tests/integration_tests/ -k "{entity}" -v
```

Also check that the route appears in the OpenAPI spec:
```bash
uv run python -c "from mealie.app import app; print([r.path for r in app.routes if '{entity}' in r.path])"
```

## Common Mistakes

1. **Wrong repo scope**: `self.repos.{entities}` is household-scoped. For group-scoped reads (e.g., search all group recipes), use `self.cross_household_repos.{entities}`.
2. **Double auth injection**: `UserAPIRouter` already injects auth. Adding `Depends(get_current_user)` inside a method runs the dependency twice.
3. **Missing `set_pagination_guides`**: Both `page_all()` AND `set_pagination_guides()` are required for proper pagination `next`/`previous` links.
4. **Using `None` instead of `NOT_SET`**: In admin contexts, `group_id=None` filters to NULL rows. Use `NOT_SET` sentinel from `mealie/repos/_utils.py` to bypass scoping.
