# mealie/routes/ — FastAPI Route Handlers

API route layer organized by domain. All controllers use a class-based view (CBV) pattern via the custom `@controller` decorator. This directory is the HTTP boundary — it accepts requests, delegates to services/repos, and converts domain exceptions to HTTP responses.

## Controller Pattern

```python
from mealie.routes._base import controller, router as base_router
from mealie.routes._base.base_controllers import BaseUserController
from mealie.routes._base.routers import UserAPIRouter

router = UserAPIRouter(prefix="/my-entity", tags=["My Entity"])

@controller(router)  # wires all @router.get/post/put/delete methods as FastAPI routes
class MyEntityController(BaseUserController):
    # FastAPI injects these automatically via Depends()
    # (UserAPIRouter pre-injects get_current_user; no need to add it)

    @cached_property
    def repo(self):
        return self.repos.my_entities  # tenant-scoped AllRepositories accessor

    @cached_property
    def mixins(self):
        return HttpRepo[CreateMyEntity, MyEntityOut, UpdateMyEntity](
            self.repo, self.logger, self.registered_exceptions
        )

    @router.get("", response_model=MyEntityPagination)
    def get_all(self, q: PaginationQuery = Depends(PaginationQuery), response: Response = None):
        result = self.repo.page_all(pagination=q, override=MyEntitySummary)
        result.set_pagination_guides(router.url_path_for("get_all"), q.model_dump())
        return result

    @router.post("", response_model=MyEntityOut, status_code=201)
    def create_one(self, data: CreateMyEntity):
        return self.mixins.create_one(data)
```

## Base Controller Hierarchy

```
_BaseController                   # session, user, translator injected
├── BasePublicController          # no auth
├── BaseUserController            # get_current_user enforced
│   ├── BaseCrudController        # + EventBusService, publish_event()
│   └── BaseAdminController       # repos scoped to group_id=None (cross-tenant)
└── BasePublicHouseholdExploreController  # public explore endpoints
```

**Key `BaseUserController` properties:**
- `self.user: PrivateUser` — authenticated user
- `self.group_id: UUID` — user's group
- `self.household_id: UUID` — user's household
- `self.repos: AllRepositories` — scoped to user's group+household
- `self.cross_household_repos` — scoped to group only (all households)
- `self.checks: OperationChecks` — raises 403 if permission fails
- `self.t(key)` — translated string
- `self.registered_exceptions` — callable mapping exception types to translated messages

**`BaseAdminController`**: Overrides `repos` to return `AllRepositories(group_id=None, household_id=None)`. All queries are cross-tenant. Never add tenant scoping inside admin controller methods.

## Router Types

- `UserAPIRouter`: pre-injects `Depends(get_current_user)` — use for all authenticated routes
- `AdminAPIRouter`: pre-injects `Depends(get_admin_user)` — use for admin-only routes
- `APIRouter`: no auth — use only for public routes, then manually add `BaseUserController`'s DI
- `MealieCrudRoute`: set as `route_class=` on a router to inject `Last-Modified` header from response's `updatedAt` field

**Never add `Depends(get_current_user)` manually** inside a `UserAPIRouter` — it runs twice and causes issues.

## Pagination

```python
@router.get("", response_model=XxxPagination)
def get_all(self, q: PaginationQuery = Depends(PaginationQuery), response: Response = None):
    result = self.repo.page_all(pagination=q, override=XxxSummary)
    result.set_pagination_guides(router.url_path_for("get_all"), q.model_dump())
    return result
```

Both steps (`page_all` + `set_pagination_guides`) are required.

## Event Publishing (BaseCrudController only)

```python
self.publish_event(
    event_type=EventTypes.recipe_created,
    document_data=EventRecipeData(operation=EventOperation.create, recipe_id=recipe.id),
    group_id=self.group_id,
    household_id=self.household_id,
    message=self.t("notifications.generic-created", name=recipe.name),
)
```

Passing `household_id=None` dispatches to all households in the group.

## Permission Checks

```python
# These raise HTTP 403 internally — no if/return needed
self.checks.can_manage()         # user.can_manage
self.checks.can_organize()       # user.can_organize
self.checks.can_invite()         # user.can_invite
self.checks.can_manage_household() # user.can_manage_household
```

## Public Explore Endpoints

Public controllers MUST manually inject privacy filters before `page_all()`. Without this, private household data leaks:

```python
public_filter = '(household.preferences.privateHousehold = FALSE AND settings.public = TRUE)'
if q.query_filter:
    q.query_filter = f"({q.query_filter}) AND {public_filter}"
else:
    q.query_filter = public_filter
```

## Route Registration

Routers are composed in each domain's `__init__.py`. Important ordering note: **meal plan rules router must be registered before meal plan router** in `routes/households/__init__.py` — reversing the order causes URL matching to fail silently.

## Error Response Format

```python
# Always use these for HTTPException detail:
raise HTTPException(404, detail=ErrorResponse.respond(message, exception=e))
raise HTTPException(200)  # use SuccessResponse.respond(message) for success envelopes
```

Never pass a bare string to `HTTPException(detail=...)`.

## File Downloads Security

All file download endpoints must use `validate_file_token` dependency — never accept raw file paths from clients.

The two-step flow: `GET /endpoint/{file_name}` → returns `FileTokenResponse` with short-lived JWT → client hits download endpoint with that token.
