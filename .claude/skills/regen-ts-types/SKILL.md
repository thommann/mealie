---
name: regen-ts-types
description: "
  Regenerate TypeScript API types from Pydantic schemas after a backend schema change,
  then verify no TypeScript compilation errors were introduced.
  Use after any change to mealie/schema/ files.
  Do NOT manually edit files in frontend/app/lib/api/types/ — they will be overwritten.
---

## When to run this

Run this skill any time you:
- Add a new Pydantic schema class to `mealie/schema/`
- Add, remove, or rename fields on existing schemas
- Change field types (Optional, List, nested schema changes)
- Add a new schema domain subdirectory

## Step 1: Run code generation

```bash
# From the repo root — this runs pydantic-to-typescript2 across all schema modules
task dev:generate

# What this does:
# 1. Runs dev/code-generation/main.py
# 2. Calls pydantic-to-typescript2 per module
# 3. Deduplicates enum names across modules
# 4. Runs yarn lint --fix on the generated files
```

## Step 2: Review the diff

```bash
git diff frontend/app/lib/api/types/
```

Look for:
- **New types added**: Verify the generated TypeScript matches your Pydantic field definitions
- **Types removed**: Check if any existing API client methods reference the removed type
- **Fields made optional**: A Pydantic field changing from `str` to `str | None` becomes `field?: string | null` in TS — callers may need null guards
- **Enum changes**: Enums are serialized as string unions. Adding a new enum member is backwards-compatible; removing one may break existing callers

## Step 3: Check for breaking changes in API clients

```bash
# Find API client files that reference changed types
git diff frontend/app/lib/api/types/ | grep '^-' | grep 'export' | awk '{print $NF}' | sort -u
# Then grep for those type names in the API client files:
grep -r "{ChangedTypeName}" frontend/app/lib/api/user/ frontend/app/lib/api/admin/
```

## Step 4: Fix any TypeScript errors

```bash
cd frontend
# Type-check the full frontend project
yarn build 2>&1 | grep -E 'error TS|warning'

# Or just lint (faster):
yarn lint --max-warnings=0
```

Common fixes needed after type regeneration:

```typescript
// Field changed from string to string | null:
// Before:
const name = data.name.toUpperCase();
// After (add null guard):
const name = data.name?.toUpperCase() ?? '';

// Nested type changed:
// Before:
const unit = ingredient.unit.name;
// After:
const unit = ingredient.unit?.name ?? '';
```

## Step 5: Update non-generated types if needed

Some types cannot be auto-generated (frontend-only utilities, enums derived from multiple schemas). These live in:
- `frontend/app/lib/api/types/non-generated.ts` — hand-maintained
- `frontend/app/types/` — hand-maintained types directory

Never add frontend-only types to the auto-generated files.

## Step 6: Verify the camelCase translation

Mealie's `MealieModel` uses `alias_generator=camelize`. Verify the generated TypeScript field names are camelCase:

```python
# Python schema field:
group_id: UUID4  # → TypeScript: groupId
recipe_yield: str  # → TypeScript: recipeYield
```

If a field is missing from the generated TypeScript, check that the Python field is not in the schema's `exclude` set.

## Verify

```bash
# Full check sequence:
task dev:generate
cd frontend && yarn lint --max-warnings=0 && yarn test:ci
```

## Common Mistakes

1. **Manually editing generated files**: Files in `frontend/app/lib/api/types/` have a `/* DO NOT MODIFY BY HAND */` header. Your changes WILL be overwritten on the next `task dev:generate` run.
2. **Adding `from_attributes=True` on `Create*` schema**: Only `*Out`/`*InDB` schemas need this. Pydantic skips ORM mapping for Create schemas, so the field won't appear in generated types.
3. **`static.ts` imports nothing useful**: `frontend/app/lib/api/types/static.ts` exports only an empty `_Master_` interface — it's a codegen artifact. Import from the correct domain file instead.
4. **`QueryFilterJSON` defined in multiple files**: It appears in `non-generated.ts`, `cookbook.ts`, and `meal-plan.ts`. The types are structurally compatible but TypeScript treats them as distinct — crossing boundaries with values may require explicit casting.
