# mealie/schema/ — Pydantic v2 DTOs

All API request/response types. Schemas are the contract between routes and the ORM layer. They define validation, serialization, camelCase translation, and eager-load configuration.

## Base Class: `MealieModel`

All schemas inherit from `MealieModel` (`mealie/schema/_mealie/mealie_model.py`). It provides:
- `alias_generator=camelize` → snake_case Python ↔ camelCase JSON
- `populate_by_name=True` → both forms accepted
- Model validator attaching UTC tzinfo to all datetimes
- `.cast(TargetModel, **extra_fields)` → promotes to another schema, injecting extras
- `.map_to(target)` / `.map_from(source)` → copies matching fields

## Schema Lifecycle (Create → Save → Update → Out)

```python
class CreateMyEntity(MealieModel):
    name: str  # user-supplied only

class SaveMyEntity(CreateMyEntity):
    group_id: UUID4  # injected by service
    household_id: UUID4

class MyEntityUpdate(SaveMyEntity):
    id: UUID4  # for PUT bodies

class MyEntityOut(SaveMyEntity):
    id: UUID4
    created_at: datetime | None
    updated_at: datetime | None = UpdatedAtField(None)
    model_config = ConfigDict(from_attributes=True)  # REQUIRED — not inherited

    @classmethod
    def loader_options(cls) -> list[LoaderOption]:
        return [selectinload(MyEntityModel.tags)]

class MyEntityPagination(PaginationBase[MyEntityOut]):
    items: list[MyEntityOut]
```

**`from_attributes=True` MUST be declared explicitly** on every `*Out` schema — it is NOT inherited from `MealieModel`.

## Validators

```python
# Before-mode for coercion (runs before Pydantic validation)
@field_validator('name', mode='before')
@classmethod
def coerce_name(cls, v):
    if hasattr(v, 'name'):  # ORM object → string
        return v.name
    return v

# After-mode for derivation (runs after all fields are set)
@model_validator(mode='after')
def compute_display(self):
    if not self.display:
        self.display = f"{self.quantity} {self.unit} {self.food}"
    return self
```

## Circular Reference Fix

When Schema A references Schema B which back-references Schema A, place the import at the file bottom and call `model_rebuild()`:

```python
# ... class definitions ...

from mealie.schema.other.module import OtherSchema  # noqa: E402
MySchema.model_rebuild()
```

## Searchable Schemas

To make a schema searchable via the pagination filter DSL, add:

```python
class MyOut(MealieModel):
    _searchable_properties: ClassVar[list[str]] = ["name", "description"]
    _normalize_search: ClassVar[bool] = True
    _fuzzy_similarity_threshold: ClassVar[float] = 0.5  # 0.0–1.0 for trigram %
```

## `UpdatedAtField()`

Use `UpdatedAtField()` (not plain `Field()`) for `updated_at` columns. It registers alias variants: `update_at`, `updateAt`, `updated_at`, `updatedAt`, and always serializes as `updatedAt`.

## OpenAI Schemas

Schemas for structured OpenAI output inherit from `OpenAIBase` (not `MealieModel`). Field `description=` strings are prompt instructions to the model — write them as imperative commands, not developer docs. These schemas live in `mealie/schema/openai/`.

## Key Files

| File | Contents |
|------|----------|
| `_mealie/mealie_model.py` | `MealieModel` base, `UpdatedAtField`, `cast()`/`map_to()` |
| `response/pagination.py` | `PaginationBase[T]`, `PaginationQuery` |
| `response/query_search.py` | `SearchFilter` — PostgreSQL trigram vs SQLite LIKE |
| `recipe/recipe.py` | Full recipe schema chain |
| `recipe/recipe_ingredient.py` | Ingredient with auto-computed `display` field |
| `household/group_shopping_list.py` | Shopping list + item schemas, `populate_missing_label` validator |
| `mapper.py` | `cast()` utility for cross-schema promotion |
