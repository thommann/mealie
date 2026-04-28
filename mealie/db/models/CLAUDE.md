# mealie/db/models/ — SQLAlchemy ORM Models

Database schema definition. All models use SQLAlchemy 2.0 declarative style with `Mapped[]` type annotations.

## Model Template

```python
from mealie.db.models._model_base import BaseMixins, SqlAlchemyBase
from mealie.db.models._model_utils.auto_init import auto_init
from mealie.db.models._model_utils.guid import GUID
from mealie.db.models._model_utils.datetime import NaiveDateTime

class MyEntityModel(SqlAlchemyBase, BaseMixins):
    __tablename__ = "my_entities"
    __table_args__ = (
        UniqueConstraint("slug", "group_id", name="my_entities_slug_group_id_key"),
    )

    id: Mapped[GUID] = mapped_column(GUID, primary_key=True, default=GUID.generate)
    name: Mapped[str] = mapped_column(sa.String, nullable=False)
    name_normalized: Mapped[str | None] = mapped_column(sa.String(255), nullable=True, index=True)
    group_id: Mapped[GUID] = mapped_column(GUID, ForeignKey("groups.id"), nullable=False, index=True)
    group: Mapped["Group"] = orm.relationship("Group", back_populates="my_entities")

    @auto_init()
    def __init__(self, **_) -> None:
        # Set normalized field — event listener doesn't fire during __init__
        self.name_normalized = self.normalize(self.name) if self.name else None

@event.listens_for(MyEntityModel.name, "set")
def receive_set_name(target, value, oldvalue, initiator):
    target.name_normalized = MyEntityModel.normalize(value)
```

## Required Rules

1. **Always `@auto_init()`** — the decorator enables transparent initialization from kwargs/dicts including nested relationships. Requires `session=` kwarg at construction time.
2. **Always `GUID`** for PKs and FKs — not `uuid.UUID`, not `str`. Handles SQLite hex ↔ PostgreSQL UUID.
3. **Always `NaiveDateTime`** for timestamps — UTC without tzinfo.
4. **Register in `_all_models.py`** — Alembic won't detect new tables until the model is imported there.
5. **Group-scoped unique constraints** — use `UniqueConstraint("slug", "group_id")`, not a standalone `UNIQUE` on slug.
6. **Normalized search columns** — add `name_normalized` sibling + `@event.listens_for(Model.column, "set")` listener. Also set in `__init__` since event listeners don't fire during construction.

## `@auto_init()` Details

- Inspects SQLAlchemy mapper metadata at call time
- Sets scalar columns directly from kwargs
- For relationship kwargs: creates new related instances (if dict) or updates existing ones
- Requires `session=` kwarg to hydrate relationships from nested data
- Silent about unknown kwargs (`**_` pattern) — typos in kwarg names silently do nothing (validate at the Pydantic schema layer)

## `update_at` Typo

The physical column is named `update_at` (typo from early development). `SqlAlchemyBase` provides a `updated_at` synonym for Python access. In raw SQL and Alembic migrations, always use `update_at`.

## Model Groups

| Directory | Contains |
|-----------|----------|
| `group/` | `Group`, `GroupPreferencesModel`, `ReportModel`, `GroupDataExportsModel` |
| `household/` | `Household`, `GroupMealPlan`, `ShoppingList`, `ShoppingListItem`, `CookBook`, `GroupWebhooksModel`, `GroupEventNotifierModel` |
| `recipe/` | `RecipeModel`, `RecipeIngredientModel`, `IngredientUnitModel`, `IngredientFoodModel`, `Tag`, `Category`, `Tool`, `RecipeComment`, `Nutrition`, `Note` |
| `users/` | `User`, `UserToRecipe` (ratings/favorites), `LongLiveToken` |
| `server/` | `ServerTask` (deprecated background task tracking) |

## Many-to-Many Pattern

```python
# Define join table at module level (not inside a class)
recipes_to_tags = sa.Table(
    "recipes_to_tags",
    SqlAlchemyBase.metadata,
    sa.Column("recipe_id", GUID, ForeignKey("recipes.id"), primary_key=True),
    sa.Column("tag_id", GUID, ForeignKey("tags.id"), primary_key=True),
    sa.UniqueConstraint("recipe_id", "tag_id"),
)

# In the owning model:
tags: Mapped[list["Tag"]] = orm.relationship(
    "Tag",
    secondary=recipes_to_tags,
    back_populates="recipes",
)
```

Junction tables that carry payload (extra columns beyond the two FKs) need a full model class, not a plain `sa.Table`.

## Cascade Policy

`cascade='all, delete-orphan'` + `single_parent=True` for owned children (they cease to exist when the parent is deleted). Omit cascade for associations (M2M, references) where child independently exists.

## PostgreSQL GIN Indices

Full-text search indices are created conditionally at model `__init__` time by checking `session.get_bind().name == 'postgresql'`. This means indices only exist on PostgreSQL — SQLite search falls back to LIKE. Never assume GIN indices in SQLite test environments.
