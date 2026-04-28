---
name: add-event-type
description: "
  Add a new EventType to the Mealie event bus system, requiring changes in four files:
  the enum, the DB migration, the Pydantic schema, and optionally a new EventDocumentData subclass.
  Use when adding a new event that should trigger webhooks or Apprise notifications.
  Do NOT use for adding webhook URL formats or Apprise provider support.
---

## Before You Start

This is a multi-file change with NO automated sync — mismatches cause silent runtime failures (`AttributeError` on `getattr`). Read all four files first:

1. `mealie/services/event_bus_service/event_types.py` — `EventTypes` enum + `EventDocumentData` classes
2. `mealie/schema/household/group_events.py` — `GroupEventNotifierOptions` boolean fields
3. `mealie/db/models/household/events.py` — `GroupEventNotifierOptionsModel` ORM columns
4. A recent migration like `mealie/alembic/versions/` to see the column-add pattern

**The enum member name must EXACTLY match the schema field name.** `EventTypes.recipe_deleted` must correspond to a field `recipe_deleted: bool` on `GroupEventNotifierOptions`. `getattr(options, event_type.name)` will raise `AttributeError` if they don't match.

## Step 1: Add the EventTypes enum member

```python
# mealie/services/event_bus_service/event_types.py
class EventTypes(str, Enum):
    # ... existing members ...
    {new_event}: str = "{new_event}"  # e.g., recipe_comment_created = "recipe_comment_created"
```

If the event carries extra document data, add a class:

```python
class Event{NewEvent}Data(EventDocumentDataBase):
    # Extra fields beyond the base (entity_id, etc.)
    recipe_id: UUID4
    comment_id: UUID4
```

## Step 2: Add the boolean field to GroupEventNotifierOptions

```python
# mealie/schema/household/group_events.py
class GroupEventNotifierOptions(MealieModel):
    # ... existing fields ...
    {new_event}: bool = False  # field name MUST match EventTypes.{new_event}.name

class GroupEventNotifierOptionsSave(GroupEventNotifierOptions):
    # Save schema inherits all fields — no additional changes needed
    pass
```

## Step 3: Add the ORM column to the model

```python
# mealie/db/models/household/events.py
class GroupEventNotifierOptionsModel(SqlAlchemyBase, BaseMixins):
    # ... existing columns ...
    {new_event}: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False, server_default="0")
```

## Step 4: Generate the migration

```bash
task py:migrate -- "add {new_event} event type to notifier options"
```

Verify the generated migration:
- Has `batch_alter_table` wrapper
- Has `server_default='0'` or `server_default=sa.false()` on the new boolean column
- Downgrade removes the column

```python
# Generated migration should look like:
def upgrade():
    with op.batch_alter_table("group_event_notifier_options", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("{new_event}", sa.Boolean(), nullable=False, server_default=sa.false())
        )

def downgrade():
    with op.batch_alter_table("group_event_notifier_options", schema=None) as batch_op:
        batch_op.drop_column("{new_event}")
```

## Step 5: Publish the event in the controller

```python
# In the relevant controller (must extend BaseCrudController):
from mealie.services.event_bus_service.event_types import EventTypes, Event{NewEvent}Data

@router.post("/comment", response_model=CommentOut, status_code=201)
def create_comment(self, data: CreateComment):
    comment = self.mixins.create_one(data)
    self.publish_event(
        event_type=EventTypes.{new_event},
        document_data=Event{NewEvent}Data(
            operation=EventOperation.create,
            recipe_id=comment.recipe_id,
            comment_id=comment.id,
        ),
        group_id=self.group_id,
        household_id=self.household_id,
        message=self.t("notifications.comment-created"),
    )
    return comment
```

**Passing `household_id=None`** dispatches to all households in the group (N+1 query pattern — use sparingly).

## Step 6: Add to frontend notifier settings (if user-configurable)

If this event should be toggleable in the group notification settings UI, add the field to:
- `frontend/app/lib/api/types/household.ts` (auto-generated — run `task dev:generate`)
- The notifications settings page at `frontend/app/pages/household/notifiers.vue`

## Verify

```bash
uv run pytest tests/integration_tests/user_household_tests/test_group_notifications.py -v
uv run alembic --config mealie/alembic/alembic.ini check
```

## Common Mistakes

1. **Enum name / schema field mismatch**: `EventTypes.recipe_deleted` requires a field literally named `recipe_deleted` on `GroupEventNotifierOptions`. The check is `getattr(options, event_type.name)` — any casing difference silently errors.
2. **Missing `server_default` on boolean column**: Adding `NOT NULL` without `server_default` fails on databases with existing notifier rows.
3. **`test_message` and `webhook_task` are internal**: These are listed in `EventTypes` but not subscribable. Do NOT add them to `GroupEventNotifierOptions`.
4. **WebhookPublisher failures are silently swallowed**: `hard_fail=False` means a failing webhook URL produces no log output. Test event delivery with an actual webhook endpoint.
