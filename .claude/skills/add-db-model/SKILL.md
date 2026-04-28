---
name: add-db-model
description: "
  Scaffold a new SQLAlchemy ORM model with all Mealie conventions: double inheritance, GUID PK, auto_init,
  NaiveDateTime, group_id FK, UniqueConstraint, normalized search column, and _all_models.py registration.
  Use when adding a new database table. Do NOT use for adding columns to existing models (use new-migration instead).
---

## Before You Start

Read these files first:
- `mealie/db/models/recipe/recipe.py` — canonical reference model (complex relationships, extras, normalization)
- `mealie/db/models/_model_base.py` — `SqlAlchemyBase`, `BaseMixins`, `update_at` typo explanation
- `mealie/db/models/_model_utils/auto_init.py` — `@auto_init()` decorator mechanics
- `mealie/db/models/_model_utils/guid.py` — `GUID` type (SQLite hex vs PostgreSQL native UUID)
- `mealie/db/models/_all_models.py` — where to register your new model

Decide the domain subdirectory:
- `mealie/db/models/group/` — group-owned entities (labels, preferences, reports)
- `mealie/db/models/household/` — household-owned entities (shopping lists, meal plans)
- `mealie/db/models/recipe/` — recipe-related entities
- `mealie/db/models/users/` — user-related entities

## Step 1: Create the model file

```python
# mealie/db/models/{domain}/{entity}.py
from __future__ import annotations

from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy import orm, event
from sqlalchemy.orm import Mapped, mapped_column

from mealie.db.models._model_base import BaseMixins, SqlAlchemyBase
from mealie.db.models._model_utils.auto_init import auto_init
from mealie.db.models._model_utils.guid import GUID
from mealie.db.models._model_utils.datetime import NaiveDateTime

if TYPE_CHECKING:
    from mealie.db.models.group.group import Group
    # Only import related models inside TYPE_CHECKING to avoid circular imports


class {Entity}Model(SqlAlchemyBase, BaseMixins):
    __tablename__ = "{entities}"
    __table_args__ = (
        # UniqueConstraint MUST include group_id — never a standalone unique slug
        sa.UniqueConstraint("slug", "group_id", name="{entities}_slug_group_id_key"),
    )

    # Primary key — always GUID, never int or raw UUID
    id: Mapped[GUID] = mapped_column(GUID, primary_key=True, default=GUID.generate)

    # Required fields
    name: Mapped[str] = mapped_column(sa.String, nullable=False)
    # Normalized shadow column for search (always add for text fields used in search)
    name_normalized: Mapped[str | None] = mapped_column(sa.String(255), nullable=True, index=True)
    slug: Mapped[str | None] = mapped_column(sa.String, nullable=True, index=True)

    # Timestamps — always NaiveDateTime (UTC without tzinfo), never datetime directly
    # NOTE: physical column is "update_at" (typo from early dev), not "updated_at"
    # BaseMixins provides updated_at as a Python synonym — use that in Python code

    # Multi-tenancy — group-scoped entities MUST have this
    group_id: Mapped[GUID] = mapped_column(GUID, sa.ForeignKey("groups.id"), nullable=False, index=True)
    group: Mapped[Group] = orm.relationship("Group", back_populates="{entities}")

    # For household-scoped entities, add BOTH:
    # household_id: Mapped[GUID] = mapped_column(GUID, ForeignKey("households.id"), nullable=False, index=True)
    # household: Mapped[Household] = orm.relationship("Household", back_populates="{entities}")

    @auto_init()  # REQUIRED — enables transparent kwargs-based construction
    def __init__(self, **_) -> None:
        # Set normalized field here — event listeners do NOT fire during __init__
        self.name_normalized = self.normalize(self.name) if self.name else None


# Event listener to keep normalized field in sync on attribute set
@event.listens_for({Entity}Model.name, "set")
def receive_set_{entity}_name(target, value, oldvalue, initiator):
    target.name_normalized = {Entity}Model.normalize(value)
```

**Critical notes:**
- `@auto_init()` requires `session=db_session` kwarg at construction time to hydrate relationships
- `GUID` is NOT `uuid.UUID` or `str` — always import from `_model_utils/guid.py`
- `NaiveDateTime` is NOT `datetime` — it handles SQLite/PostgreSQL UTC compatibility
- The physical timestamp column is `update_at` (typo), Python synonym is `updated_at`
- Normalized fields MUST be set in both `__init__` AND the event listener

## Step 2: Wire relationship on the parent model (Group or Household)

```python
# In mealie/db/models/group/group.py
from mealie.db.models.group.{entity} import {Entity}Model  # inside TYPE_CHECKING

class Group(SqlAlchemyBase, BaseMixins):
    # ... existing code ...
    {entities}: Mapped[list[{Entity}Model]] = orm.relationship(
        "{Entity}Model",
        back_populates="group",
        **common_args,  # cascade="all, delete-orphan", lazy="select"
    )
```

## Step 3: Register in _all_models.py

```python
# mealie/db/models/_all_models.py — REQUIRED or Alembic won't detect the table
from mealie.db.models.{domain}.{entity} import {Entity}Model  # noqa: F401
```

## Step 4: Generate migration

```bash
task py:migrate -- "add {entity} table"
# Or directly:
uv run alembic --config mealie/alembic/alembic.ini revision --autogenerate -m "add {entity} table"
```

Then verify the generated migration follows all rules (see new-migration skill).

## Verify

```bash
uv run ruff format mealie/db/models/{domain}/{entity}.py
uv run mypy mealie/db/models/{domain}/{entity}.py
# Verify Alembic detects the new table
uv run alembic --config mealie/alembic/alembic.ini check
```

## Common Mistakes

1. **Missing `_all_models.py` registration**: Alembic will not generate a migration for the new table. The model exists in Python but the table never gets created.
2. **`group_id=None` for admin**: In `AllRepositories`, `group_id=None` means `WHERE group_id IS NULL`. Use `NOT_SET` sentinel from `mealie/repos/_utils.py` for unrestricted admin access.
3. **Forgetting normalized field in `__init__`**: Event listeners only fire on attribute SET after construction. The initial value set during `@auto_init()` does NOT trigger the listener.
4. **Global unique constraint on slug**: Must be `UniqueConstraint("slug", "group_id")` — two groups can have the same slug. A standalone `UNIQUE` on slug breaks multi-tenancy.
