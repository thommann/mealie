---
name: add-recipe-migrator
description: "
  Scaffold a new recipe format importer by extending BaseMigrator, implementing _migrate(),
  wiring MigrationAlias field mappings, and registering in the migration dispatch table.
  Use when adding support for a new recipe manager format like Paprika, Nextcloud, or a custom format.
  Do NOT use for the Mealie ZIP format (use create_from_zip in RecipeService).
---

## Before You Start

Read these files:
- `mealie/services/migrations/_migration_base.py` — `BaseMigrator` template method + `MigrationAlias`
- `mealie/services/migrations/paprika.py` — ZIP-based migrator with base64 images
- `mealie/services/migrations/nextcloud.py` — JSON-based migrator
- `mealie/services/migrations/utils/migration_helpers.py` — `get_zip_base_path()`, `safe_local_path()`
- `mealie/routes/groups/controller_migrations.py` — dispatch table where you register your migrator
- `mealie/services/migrations/__init__.py` — module exports

## Step 1: Analyze the source format

Before coding, identify:
- Archive format: ZIP, single file, directory structure?
- Data format: JSON, XML, HTML, CSV?
- Image storage: base64-encoded, separate file, URL reference?
- Field mapping: which source fields map to Mealie's schema.org Recipe fields?

## Step 2: Create the migrator class

```python
# mealie/services/migrations/{format_name}.py
from pathlib import Path
from zipfile import ZipFile

from mealie.pkgs.safehttp.transport import AsyncSafeTransport
from mealie.services.migrations._migration_base import BaseMigrator
from mealie.services.migrations.utils.migration_alias import MigrationAlias
from mealie.services.migrations.utils.migration_helpers import get_zip_base_path


class {FormatName}Migrator(BaseMigrator):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "{format_name}"

        # MigrationAlias maps source field names to Mealie's schema.org Recipe keys
        # Key: Mealie's camelCase field name, alias: source format field name
        # Optional func: transform function applied to the source value
        self.key_aliases = [
            MigrationAlias(key="name", alias="title"),  # source uses "title"
            MigrationAlias(key="recipeYield", alias="servings"),
            MigrationAlias(key="prepTime", alias="prep_time", func=lambda v: f"PT{v}M"),
            MigrationAlias(key="recipeIngredient", alias="ingredients"),
        ]

    def _migrate(self) -> None:
        """Main migration logic. Never let exceptions escape — append to self.report_entries."""
        # ZIP archive extraction:
        with ZipFile(self.archive) as zf:
            base = get_zip_base_path(zf)  # handles Safari's __MACOSX wrapping

            for member in zf.namelist():
                if not member.endswith(".json") or not member.startswith(str(base)):
                    continue

                try:
                    raw = zf.read(member)
                    recipe_data = self._parse_one(raw)
                    if recipe_data:
                        # rewrite_alias() maps source fields to Mealie schema fields
                        # It MUTATES the dict in place — do not reuse recipe_data after this
                        rewritten = self.rewrite_alias(recipe_data)
                        # clean_recipe_dictionary() normalizes and validates
                        cleaned = clean_recipe_dictionary(rewritten)
                        self.recipes.append(cleaned)
                except Exception as e:
                    self.logger.error(f"Error parsing {member}: {e}")
                    # Append to report, do NOT re-raise — let other recipes succeed

        self.import_recipes_to_database(self.recipes)

    def _parse_one(self, raw: bytes) -> dict | None:
        """Parse one recipe from raw bytes."""
        import json
        try:
            return json.loads(raw)
        except Exception:
            return None
```

**CRITICAL: `asyncio.run()` inside `_migrate()` will raise `RuntimeError`** if called from within an async context (FastAPI route). Use `asyncio.get_event_loop().run_until_complete()` or structure async work differently.

**`safe_local_path()`** must be used for any path constructed from archive member names:
```python
from mealie.services.migrations.utils.migration_helpers import safe_local_path
dest = safe_local_path(base_dir, member_name)  # prevents path traversal
```

## Step 3: Register in the dispatch table

```python
# mealie/routes/groups/controller_migrations.py
from mealie.services.migrations.{format_name} import {FormatName}Migrator

# Inside the dispatch table dict:
migration_handlers = {
    # ... existing entries ...
    "{format_name}": {FormatName}Migrator,
}
```

Also add to the `SupportedMigrations` enum if one exists.

## Step 4: Export from migrations/__init__.py

```python
# mealie/services/migrations/__init__.py
from mealie.services.migrations.{format_name} import {FormatName}Migrator  # noqa: F401
```

## Step 5: Write a test

```python
# tests/unit_tests/services_tests/migration_tests/test_{format_name}_migrator.py
import pytest
from pathlib import Path

from mealie.services.migrations.{format_name} import {FormatName}Migrator

# Add a sample archive fixture to tests/data/migrations/{format_name}/
FIXTURE = Path("tests/data/migrations/{format_name}/sample.zip")

@pytest.mark.skipif(not FIXTURE.exists(), reason="no fixture")
def test_{format_name}_migration(unique_user):
    migrator = {FormatName}Migrator(
        archive=FIXTURE,
        db=unique_user.repos,
        user=unique_user,
    )
    migrator.migrate()
    assert len(migrator.report_entries) > 0  # at least one recipe processed
    # Verify at least one recipe was imported:
    recipes = unique_user.repos.recipes.get_all()
    assert len(recipes) >= 1
```

## Common Mistakes

1. **`rewrite_alias()` mutates in place**: Do not reuse the `recipe_data` dict after calling `rewrite_alias()`. The original keys are gone.
2. **`asyncio.run()` in `_migrate()`**: This raises `RuntimeError` inside an async FastAPI route. The Paprika migrator has this issue. Use synchronous HTTP clients or a thread executor.
3. **`get_zip_base_path()` handles only one level of `__MACOSX` nesting**: Deeply nested or non-standard Safari archives may still produce wrong base paths.
4. **Exception escaping `_migrate()`**: If an exception propagates out of `_migrate()`, the entire migration fails with no progress report. Catch per-recipe exceptions and append to `self.report_entries`.
