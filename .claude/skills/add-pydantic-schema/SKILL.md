---
name: add-pydantic-schema
description: "
  Scaffold a new Pydantic v2 schema domain following the Create-Save-Update-Out-Pagination chain,
  with MealieModel inheritance, loader_options, and from_attributes.
  Use when adding new API request/response types.
  Do NOT use for OpenAI structured-output schemas (use add-openai-prompt) or for modifying existing schemas.
---

## Before You Start

Read these files:
- `mealie/schema/_mealie/mealie_model.py` — `MealieModel` base, `UpdatedAtField`, `cast()`, `map_to()`
- `mealie/schema/household/group_shopping_list.py` — complex example with validators, loader_options, M2M
- `mealie/schema/recipe/recipe.py` — full lifecycle chain with circular references and model_rebuild()
- `mealie/schema/response/pagination.py` — `PaginationBase[T]`

## Step 1: Create the schema file

```python
# mealie/schema/{domain}/{entity}.py
from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, ClassVar
from uuid import UUID

from pydantic import UUID4, ConfigDict, field_validator, model_validator
from sqlalchemy.orm import selectinload, joinedload
from mealie.db.models.{domain}.{entity} import {Entity}Model  # for loader_options only
from mealie.schema._mealie import MealieModel
from mealie.schema._mealie.mealie_model import UpdatedAtField
from mealie.schema.response.pagination import PaginationBase


class {Entity}Summary(MealieModel):
    """Lightweight read-only view for list endpoints."""
    id: UUID4
    name: str
    slug: str | None = None

    model_config = ConfigDict(from_attributes=True)  # REQUIRED on every Out/Summary schema


class Create{Entity}(MealieModel):
    """User-supplied fields only. No IDs, no group_id."""
    name: str
    description: str | None = None


class Save{Entity}(Create{Entity}):
    """Adds tenant context. Injected by service, never by user."""
    group_id: UUID4
    household_id: UUID4 | None = None  # omit if entity is group-scoped only


class Update{Entity}(Save{Entity}):
    """Adds primary key for PUT endpoints."""
    id: UUID4


class {Entity}Out(Update{Entity}):
    """Full read response. Must have from_attributes=True (NOT inherited from MealieModel)."""
    created_at: datetime | None = None
    updated_at: datetime | None = UpdatedAtField(None)  # use UpdatedAtField, not Field()

    # REQUIRED: ConfigDict(from_attributes=True) must be declared explicitly — it is NOT inherited
    model_config = ConfigDict(from_attributes=True)

    @classmethod
    def loader_options(cls) -> list:
        """Eager-load options to prevent N+1 queries. Must be updated whenever a new relationship field is added."""
        return [
            selectinload({Entity}Model.tags),
            selectinload({Entity}Model.related_items).joinedload(RelatedModel.unit),
        ]


class {Entity}Pagination(PaginationBase[{Entity}Out]):
    items: list[{Entity}Out]
```

**Critical: `from_attributes=True` is NOT inherited from MealieModel.** Every `*Out` or `*InDB` schema that is initialized from an ORM object MUST declare it explicitly in `model_config`.

## Step 2: Add validators when needed

```python
# Before-mode: coerce ORM objects to scalars (runs before Pydantic validation)
@field_validator("category", mode="before")
@classmethod
def convert_category_to_name(cls, v):
    if hasattr(v, "name"):  # ORM object → string
        return v.name
    return v

# After-mode: derive computed fields (runs after all fields are validated)
@model_validator(mode="after")
def compute_display(self):
    if not self.display:
        q = self.quantity or ""
        u = self.unit or ""
        f = self.food or ""
        self.display = f"{q} {u} {f}".strip()
    return self
```

## Step 3: Handle circular references

When Schema A references Schema B which references Schema A (e.g., Recipe contains RecipeIngredient which has a `referenced_recipe: Recipe` field):

```python
# At the BOTTOM of the file, after all class definitions:
from mealie.schema.other.module import OtherSchema  # noqa: E402
MySchema.model_rebuild()  # REQUIRED to resolve forward references
```

## Step 4: Export from __init__.py

```python
# mealie/schema/{domain}/__init__.py
from mealie.schema.{domain}.{entity} import (
    Create{Entity},
    Save{Entity},
    Update{Entity},
    {Entity}Out,
    {Entity}Pagination,
    {Entity}Summary,
)
```

## Step 5: Update loader_options when adding relationship fields

Every time you add a nested schema field that maps to a SQLAlchemy relationship:
```python
# Add the corresponding eager-load directive
@classmethod
def loader_options(cls) -> list:
    return [
        selectinload({Entity}Model.existing_tags),
        selectinload({Entity}Model.new_relation),  # ADD THIS when you add the field
    ]
```

Omitting this causes silent N+1 queries — no error, just slow performance.

## Verify

```bash
uv run ruff format mealie/schema/{domain}/{entity}.py
uv run mypy mealie/schema/{domain}/{entity}.py
# Verify the schema serializes correctly
uv run python -c "
from mealie.schema.{domain}.{entity} import {Entity}Out
print({Entity}Out.model_fields.keys())
print({Entity}Out.model_config)
"
```

## Common Mistakes

1. **`from_attributes=True` missing on Out schema**: Initializing `{Entity}Out.model_validate(orm_obj)` raises `ValidationError` if `from_attributes` is not set.
2. **`updated_at: datetime = Field(None)` instead of `UpdatedAtField(None)`**: The `UpdatedAtField` registers aliases (`update_at`, `updateAt`, `updated_at`, `updatedAt`) so clients sending legacy field names still work.
3. **`Save*` schema in frontend**: The frontend must only use `Create*`, `Update*`, or `*Out` schemas. `Save*` contains server-injected fields (`group_id`) and must never be in API responses.
4. **Adding nested field without updating `loader_options()`**: Silent N+1 — the nested field will be loaded by SQLAlchemy lazily in a loop for every result row.
