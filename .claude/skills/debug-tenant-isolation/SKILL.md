---
name: debug-tenant-isolation
description: "
  Debug data isolation issues, permission errors, and cross-tenant data leaks in Mealie's
  group and household scoping system.
  Use when seeing wrong data returned, 403 errors, or empty results that should have data.
  Do NOT use for auth failures (wrong password, token expiry) — those are authentication issues.
---

## Diagnostic flow

Tenant isolation issues fall into four categories:
1. **Empty results** — data exists but query is over-scoped
2. **Cross-tenant data** — data from another group/household is returned
3. **403 Permission Denied** — user lacks the required permission flag
4. **Silent wrong data** — wrong household's data returned (group vs. household scope)

## Category 1: Empty results — check the scope

```python
# In the controller or service, check what scope AllRepositories was built with:
from mealie.repos._utils import NOT_SET

# group_id=None means WHERE group_id IS NULL (returns nothing unless you have null groups)
# group_id=NOT_SET means no filter (returns everything — admin access)
# group_id=<uuid> means WHERE group_id = <uuid> (normal user access)

# Add debugging:
print(f"repos.group_id = {self.repos.group_id!r}")
print(f"repos.household_id = {self.repos.household_id!r}")

# Verify the user's group matches the data you're querying:
print(f"user.group_id = {self.user.group_id!r}")
```

Common cause: `self.group_recipes` (read-only, group-scoped) vs `self.repos.recipes` (household-scoped):

```python
# mealie/routes/recipe/_base.py — BaseRecipeController:
# self.recipes → household-scoped (for writes, excludes other households)
# self.group_recipes → group-scoped (for reads, sees all households)

# If a read returns empty when the recipe exists:
# Try using self.group_recipes instead of self.repos.recipes
```

## Category 2: Cross-tenant data — check admin bypass

```python
# BaseAdminController.repos returns AllRepositories(None, None)
# This gives UNRESTRICTED access to all tenants
# If an admin route is accidentally returning cross-tenant data:

# Check if your controller inherits BaseAdminController:
class MyController(BaseAdminController):  # <-- all data, cross-tenant
    pass

class MyController(BaseUserController):  # <-- scoped to user's group/household
    pass
```

Public explore endpoints missing visibility filter:
```python
# Public controllers MUST inject this filter before page_all()
# Without it, private household data leaks to unauthenticated users:
public_filter = '(household.preferences.privateHousehold = FALSE AND settings.public = TRUE)'
if q.query_filter:
    q.query_filter = f"({q.query_filter}) AND {public_filter}"
else:
    q.query_filter = public_filter
```

## Category 3: 403 Permission Denied — check permission flags

```python
# Permission flags on PrivateUser:
# user.admin          — site-wide admin
# user.can_manage     — can manage group data
# user.can_organize   — can create/edit categories, tags, tools
# user.can_invite     — can invite new users
# user.can_manage_household  — can manage household settings

# Permission checks in controllers (raise HTTP 403 internally):
self.checks.can_manage()          # requires user.can_manage
self.checks.can_organize()        # requires user.can_organize
self.checks.can_manage_household() # requires user.can_manage_household

# Frontend guards are client-side only — backend must independently enforce:
# frontend/app/middleware/*.ts is a UX guard, not a security boundary
```

## Category 4: Wrong household data — check scope duality

```python
# The key distinction in recipe controllers:
# self.repos.recipes   → household_id = user.household_id  (for WRITES)
# self.group_recipes   → household_id = None               (for READS across all households)

# If a search returns no results but recipe exists:
# The recipe may be in a different household of the same group
# Use self.group_recipes for the search

# If a write affects wrong recipes:
# You may be using self.group_recipes for mutation instead of self.repos.recipes
```

## Multitenant test verification

```bash
# Run the multitenant isolation test suite:
uv run pytest tests/multitenant_tests/ -v

# Run cross-group isolation tests:
uv run pytest tests/integration_tests/ -k "cross_group or isolation" -v

# Manually verify with unfiltered DB access:
uv run python -c "
from mealie.repos._utils import NOT_SET
from mealie.repos.repository_factory import get_repositories
from mealie.db.db_setup import generate_session
with generate_session() as session:
    repos = get_repositories(session, group_id=NOT_SET, household_id=NOT_SET)
    all_recipes = repos.recipes.get_all()
    print(f'Total recipes: {len(all_recipes)}')
    for g, count in ...:
        print(f'Group {g}: {count} recipes')
"
```

## Frontend store isolation debugging

```typescript
// Module-level store refs survive navigation — check clearAllStores():
// frontend/app/composables/store/index.ts

// If previous user's data is visible after login:
// 1. Check that clearAllStores() is called on logout
// 2. Check that reset{Entity}Store() is registered inside clearAllStores()
// 3. Verify the store ref is actually zeroed:

// Debug in browser console:
// (window as any).__vueApp.$data  // may expose store refs

// If public and private stores share data (both use same store ref):
// usePublicCategoryStore and useCategoryStore share the same module-level store
// Only use one variant per page context
```

## Common root causes

| Symptom | Likely Cause |
|---------|-------------|
| Empty results, data exists | `group_id=None` (null filter) instead of `NOT_SET` |
| Admin sees own data only | Using `BaseUserController` instead of `BaseAdminController` |
| Private household data in public API | Missing visibility filter in public controller |
| Wrong household's data in writes | Using `self.group_recipes` for mutation |
| 403 on own data | Permission flag (`can_manage`) not set on user |
| Stale data after logout | `reset{Entity}Store()` not in `clearAllStores()` |
