# mealie/repos/ — Repository Layer

All database access goes through this layer. `RepositoryGeneric[Schema, Model]` provides typed CRUD + pagination. Domain-specific repos extend it. `AllRepositories` is the single factory aggregating all repos and is the only object injected into services and controllers.

## Getting a Repository

```python
# In routes/services — always via AllRepositories
repos = get_repositories(session, group_id=user.group_id, household_id=user.household_id)
recipes = repos.recipes.get_one(slug, key="slug")

# Admin (cross-tenant)
from mealie.repos._utils import NOT_SET
admin_repos = get_repositories(session, group_id=NOT_SET, household_id=NOT_SET)

# Group-only (no household filter)
group_repos = get_repositories(session, group_id=group_id, household_id=None)
```

**`None` vs `NOT_SET`**: `group_id=None` filters to `WHERE group_id IS NULL`. `group_id=NOT_SET` applies no filter. These are completely different behaviors.

## RepositoryGeneric API

```python
# All methods are group/household-filtered automatically
repo.get_one(value, key="id")    # raises NoResultFound if missing
repo.get_all()                    # returns list; use pagination for large sets
repo.page_all(pagination=q, override=SummarySchema)  # paginated
repo.create(data: Schema | dict)
repo.create_many(items)
repo.update(value, data)          # full replace
repo.patch(value, data)           # partial update (exclude_unset=True)
repo.delete(value, key="id")
repo.delete_many(ids)
```

Always use `.unique()` after `session.execute()` when relationships are eagerly loaded to avoid duplicate rows from joins:
```python
result = session.execute(q).unique().scalars().all()
```

## Schema-Driven Eager Loading

Schemas must implement `loader_options()` classmethod. The repo calls it automatically:

```python
class RecipeOut(MealieModel):
    @classmethod
    def loader_options(cls) -> list[LoaderOption]:
        return [
            selectinload(RecipeModel.tags),
            selectinload(RecipeModel.recipe_ingredient).joinedload(RecipeIngredientModel.unit),
        ]
```

Omitting `loader_options()` for a nested field triggers N+1 queries — no error, just slow.

## Slug Collision Retry

When creating entities with slugs (recipes, groups, households, cookbooks), the repo catches `IntegrityError` and retries up to 10 times, appending ` (N)` to the name on each retry. The created entity's name may differ from the requested name.

## Delete Behavior

`delete_many()` uses row-by-row `session.delete()` instead of bulk DELETE. This is intentional — PostgreSQL doesn't trigger cascade rules correctly with bulk DELETE statements. Never simplify this to a bulk DELETE without testing cascade behavior.

## AllRepositories Cached Properties

Every domain repo is a `@cached_property` on `AllRepositories`. First access creates it; subsequent accesses return the cached instance. This means the Session is shared across all repos in a request.

## Seed Data

Seed resources (foods, units, labels) live in `repos/seed/resources/{domain}/locales/{locale}.json` with `en-US.json` as fallback. The seeder uses `AllRepositories` to insert initial data.

## Column Aliases for Computed Sort Columns

For user-specific computed columns (e.g., `rating`, `last_made` on recipes), override the `column_aliases` property to return a dict of name → SQLAlchemy expression:

```python
@property
def column_aliases(self) -> dict[str, Any]:
    return {
        "rating": sa.case(...),
        "last_made": sa.case(...),
    }
```

The pagination engine substitutes these expressions when applying ORDER BY.
