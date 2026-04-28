---
name: add-scheduled-task
description: "
  Scaffold a new recurring background task using SchedulerRegistry and the session_context pattern.
  Use when adding new daily, hourly, or minutely background jobs.
  Do NOT use for one-off async operations (use BackgroundTasks instead) or for tasks that should run per-request.
---

## Before You Start

Read these files:
- `mealie/services/scheduler/scheduler_registry.py` — `SchedulerRegistry` with class-level task lists
- `mealie/services/scheduler/runner.py` — `repeat_every` decorator and task execution
- `mealie/services/scheduler/tasks/purge_group_exports.py` — simple daily task example
- `mealie/services/scheduler/tasks/create_timeline_events.py` — complex task with DB queries
- `mealie/services/scheduler/tasks/__init__.py` — where to export your task
- `mealie/app.py` — where schedulers start (daily/hourly/minutely tiers)

**Warning**: SchedulerRegistry state is global. If the app runs with multiple workers (`uvicorn --workers N`), every worker runs every task independently. The recommended deployment is single-worker. Tasks must be idempotent.

## Step 1: Create the task file

```python
# mealie/services/scheduler/tasks/{task_name}.py
import asyncio
from datetime import datetime, timezone

from mealie.core.root_logger import get_logger
from mealie.db.db_setup import session_context
from mealie.repos.repository_factory import get_repositories
from mealie.services.scheduler.scheduler_registry import SchedulerRegistry

logger = get_logger()


async def _{task_name}():
    """Task body — must be robust to errors."""
    async with session_context() as session:
        repos = get_repositories(session, group_id=None, household_id=None)  # or NOT_SET for full admin
        # For per-group tasks, query all groups and iterate:
        all_groups = repos.groups.get_all()
        for group in all_groups:
            try:
                group_repos = get_repositories(session, group_id=group.id, household_id=None)
                # ... do work ...
            except Exception as e:
                logger.error(f"Error processing group {group.id} in {task_name}: {e}")
                # Never let one group's failure stop other groups


# Register at module level — fires at scheduler startup
SchedulerRegistry.register_daily(_{task_name})   # choose: daily / hourly / minutely
```

**`session_context()` is an async context manager** that creates a new SQLAlchemy session per call and closes it in finally. Never hold a session open across multiple task iterations.

## Step 2: Handle timezone correctly

Note from `create_timeline_events.py`: The scheduler uses `tzlocal()` for determining "today". All other time operations should use UTC:

```python
from datetime import datetime, timezone
now_utc = datetime.now(timezone.utc)
```

The `DAILY_SCHEDULE_TIME_UTC` setting depends on `tzlocal()` — ensure the container's `TZ` env var matches the intended timezone.

## Step 3: Export from tasks/__init__.py

```python
# mealie/services/scheduler/tasks/__init__.py
from mealie.services.scheduler.tasks.{task_name} import _{task_name}  # noqa: F401
# The import is what triggers SchedulerRegistry.register_daily() to run
```

## Step 4: Ensure the module is imported in app.py

```python
# mealie/app.py — check that tasks/__init__.py is already imported
# The import chain: app.py → services/scheduler/ → tasks/__init__.py
# If tasks/__init__.py already imports everything, your new task is auto-included
# Verify by checking that SchedulerRegistry.daily_jobs contains your task after startup
```

## Step 5: Choose the right cadence

| Tier | Method | Use for |
|------|--------|----------|
| Minutely | `register_minutely()` | Webhook posting, near-real-time polling |
| Hourly | `register_hourly()` | Lockout resets, cache invalidation |
| Daily | `register_daily()` | Token purge, export cleanup, meal plan events |

**Minutely tier waits 5 minutes before its FIRST run** (`wait_first=True`). On fresh startup, minutely tasks don't fire immediately.

## Verify

```bash
# Test task runs without error:
uv run python -c "
import asyncio
from mealie.services.scheduler.tasks.{task_name} import _{task_name}
asyncio.run(_{task_name}())
print('Task completed')
"

uv run pytest tests/unit_tests/services_tests/scheduler/ -v
```

## Common Mistakes

1. **Module-level `last_ran` variable**: `post_webhooks.py` uses a module-level `last_ran = datetime.now()` set at import time, not first execution. If your task has similar sliding-window logic, initialize inside the function, not at module level.
2. **`purge_excess_files()` is never called**: A function exists in `purge_group_exports.py` but is NOT registered with the scheduler — it's dead code. Verify your registration actually runs by checking `SchedulerRegistry.daily_jobs` at startup.
3. **Multiple workers = multiple runs**: There is no distributed locking. Each uvicorn worker starts its own scheduler. Ensure all tasks are idempotent.
4. **f-string injection in query filter**: `create_timeline_events.py` uses f-string in `PaginationQuery.query_filter`. If your task does the same, ensure only server-controlled values are interpolated — never user input.
