---
name: new-migration
description: "
  Create a new Alembic database migration following all Mealie conventions: batch_alter_table,
  dialect branching, inline table stubs, server_default for NOT NULL columns.
  Use after modifying ORM models or when adding data migrations.
  Do NOT use for editing existing migration files (that corrupts the chain).
---

## Before You Start

Read these files:
- `mealie/alembic/versions/2024-07-12-00.00.00_feecc8ffb956_add-households.py` — complex migration with data migration, deduplication, and constraints
- `mealie/alembic/versions/2023-10-04-00.00.00_dded3119c1fe_add-unique-constraints.py` — deduplicate-before-constrain pattern
- `mealie/alembic/env.py` — migration environment setup
- `mealie/db/migration_types.py` — custom column types used in stubs

**NEVER edit an existing migration file.** The chain is sequential; editing a file that has already run corrupts all existing databases.

## Step 1: Generate the migration

```bash
# Preferred (uses task shortcut):
task py:migrate -- "add {description} to {table}"

# Equivalent direct command:
uv run alembic --config mealie/alembic/alembic.ini revision --autogenerate -m "add {description} to {table}"
```

The generated file appears in `mealie/alembic/versions/` with a timestamped filename.

## Step 2: Apply the mandatory patterns

**Always use batch_alter_table for column/constraint changes (SQLite compatibility):**

```python
def upgrade():
    # REQUIRED: wrap ALL column/constraint changes in batch_alter_table
    with op.batch_alter_table("recipes", schema=None) as batch_op:
        batch_op.add_column(sa.Column("new_field", sa.String(), nullable=True))
        # For NOT NULL columns on populated tables — MUST have server_default:
        batch_op.add_column(
            sa.Column("required_field", sa.String(), nullable=False, server_default="default_value")
        )
        batch_op.create_index("ix_recipes_new_field", ["new_field"])
        batch_op.create_foreign_key("fk_recipes_group_id", "groups", ["group_id"], ["id"])


def downgrade():
    with op.batch_alter_table("recipes", schema=None) as batch_op:
        batch_op.drop_column("new_field")
        batch_op.drop_column("required_field")
```

**Dialect branching for PostgreSQL-specific operations (GIN indices, sequences):**

```python
def upgrade():
    bind = op.get_context().dialect.name
    if bind == "postgresql":
        op.execute("CREATE INDEX CONCURRENTLY ix_recipes_fts ON recipes USING GIN(name_normalized gin_trgm_ops)")
    # else: SQLite gets no GIN index — this divergence is intentional and documented
```

**Inline table stubs for data migrations (NEVER import live ORM models):**

```python
# CORRECT — inline stub, import-independent
recipes_table = sa.table(
    "recipes",
    sa.column("id", sa.String),
    sa.column("group_id", sa.String),
    sa.column("name", sa.String),
)

# WRONG — importing live model will break if model changes after migration runs
# from mealie.db.models.recipe.recipe import RecipeModel  # NEVER DO THIS
```

**Deduplication before UNIQUE constraint:**

```python
def upgrade():
    # Step 1: Find and remove duplicates BEFORE adding the constraint
    bind = op.get_context().bind
    if op.get_context().dialect.name == "postgresql":
        bind.execute(sa.text("""
            DELETE FROM cookbooks a
            USING cookbooks b
            WHERE a.id > b.id
              AND a.slug = b.slug
              AND a.group_id = b.group_id
        """))
    else:
        # SQLite: use ROWID
        bind.execute(sa.text("""
            DELETE FROM cookbooks
            WHERE rowid NOT IN (
                SELECT MIN(rowid) FROM cookbooks GROUP BY slug, group_id
            )
        """))

    # Step 2: Add the constraint only after duplicates are removed
    with op.batch_alter_table("cookbooks") as batch_op:
        batch_op.create_unique_constraint("uq_cookbooks_slug_group", ["slug", "group_id"])
```

**Irreversible data migrations (downgrade: pass):**

```python
def downgrade():
    # This migration transforms data in a way that cannot be reversed.
    # Downgrading past this point leaves data in the post-migration state.
    pass
```

## Step 3: Critical column naming gotcha

The physical timestamp column is named `update_at` (NOT `updated_at`) — typo from early development. In raw SQL and migration DDL, always use `update_at`:

```python
batch_op.add_column(sa.Column("update_at", sa.DateTime(), nullable=True))  # correct
batch_op.add_column(sa.Column("updated_at", sa.DateTime(), nullable=True))  # WRONG — creates new column
```

## Step 4: Test the migration

```bash
# Test upgrade on fresh DB
uv run alembic --config mealie/alembic/alembic.ini upgrade head

# Test downgrade (if implemented)
uv run alembic --config mealie/alembic/alembic.ini downgrade -1
uv run alembic --config mealie/alembic/alembic.ini upgrade head

# Run full test suite to check for regressions
uv run pytest tests/ -x
```

## Verify

```bash
uv run ruff format mealie/alembic/versions/<new_file>.py
# Verify alembic chain is intact
uv run alembic --config mealie/alembic/alembic.ini history --verbose
```

## Common Mistakes

1. **Missing `batch_alter_table`**: Direct `op.add_column()` outside batch context fails on SQLite. Every column/index/constraint change needs the batch wrapper.
2. **No `server_default` on NOT NULL column**: If the table has existing rows and you add a NOT NULL column without `server_default`, the migration fails with a constraint violation.
3. **Importing live models**: `from mealie.db.models.recipe.recipe import RecipeModel` in a migration will break when that model later changes. Use `sa.table()` stubs.
4. **UNIQUE constraint without deduplication**: If existing data has duplicates, the constraint addition fails mid-migration with no partial rollback on SQLite.
