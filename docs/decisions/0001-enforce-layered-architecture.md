---
status: "accepted"
date: 2026-05-03
decision-makers: Mealie maintainers
consulted: contributors active on the architecture documentation initiative
informed: Mealie contributors at large
---

# Enforce a layered architecture and extract the scheduler→routes helper

## Context and Problem Statement

The grimp import graph (`docs/architecture/grimp.dot`) and the building-block view in [`docs/arc42/05-building-block-view.md`](../arc42/05-building-block-view.md) describe a layered architecture (entry → middleware → routes → services → repos → db → schema → lang → core → pkgs), but the codebase contains 63 upward import edges that violate it. The single most damaging violation is `mealie/services/scheduler/tasks/delete_old_checked_shopping_list_items.py:7` importing `publish_list_item_events` from `mealie/routes/households/controller_shopping_lists.py:41` — a `services → routes` edge that drags the entire HTTP layer (147 transitive `mealie.*` modules including `fastapi`, `BaseCrudController`, `HttpRepo`, and every shopping-list pydantic schema) into a process that only needs to broadcast events. The helper itself is pure: it has no `self`, no router state, and only depends on schemas and event-bus types that already live below the services layer.

## Decision Drivers

* The scheduler runs in-process (`mealie/app.py:131-148`); pulling the routes layer into its import closure inflates startup time, memory, and the blast radius of any FastAPI/CBV change.
* `import-linter` is already a project dependency (`pyproject.toml:75-93`, `.import_linter_cache/`) but no layer contract is configured — we have the tooling to enforce direction without adopting anything new.
* The arc42 building-block view is the canonical description of module boundaries; divergence between it and the import graph erodes its usefulness as documentation.
* The cure must not perturb behaviour: shopping-list scheduled cleanup and the controller's bulk-delete endpoints must continue to publish identical event streams.

## Considered Options

* (a) Status quo — accept the `services → routes` edge and the 10 other upward-direction patterns in `grimp.dot`.
* (b) Extract the pure helper `publish_list_item_events` into the services layer; both the controller and the scheduler task import it from there. Add an `import-linter` layered contract (with a grandfathered ignore list for the remaining 62 violations) so new violations cannot land while the cleanup proceeds.
* (c) Move the consumer down a layer by relocating the scheduler task into `mealie.routes` (since it already depends on a route module).

## Decision Outcome

Chosen option: "(b) Extract the pure helper into the services layer and enforce direction via `import-linter`", because the helper is structurally a service-layer concern (it transforms a `ShoppingListItemsCollectionOut` into event-bus dispatches) that was placed in a controller module for proximity rather than ownership. Extraction is a mechanical move with no behavioural change, eliminates the only `services → routes` edge in the entire graph, and unblocks an enforceable contract. Option (c) is rejected because the scheduler is not an HTTP concern — relocating it into `mealie.routes` would entrench the inversion and force every other scheduler task to follow the same wrong direction.

### Consequences

* Good, because the scheduler task's import closure shrinks from 147 transitive `mealie.*` modules to whatever the services layer already loads, and the worst single-edge violation in `grimp.dot` is eliminated.
* Good, because an `import-linter` layered contract makes the layer order from arc42 §5 executable rather than aspirational, and the grandfathered list provides a visible burn-down of the remaining 62 violations.
* Bad, because the grandfathered ignore list lets known violations persist until the follow-up refactor lands; readers must not mistake the contract passing for "no violations exist".
* Neutral, because the helper's module path changes — every importer (currently the controller plus the scheduler task) must update its `from …` line, but the function signature and behaviour are unchanged.

### Confirmation

Compliance is confirmed by three mechanisms:

1. **Static contract** — a `[tool.importlinter]` `forbidden` contract in `pyproject.toml` declaring `mealie.services` may not import `mealie.routes`. Reintroducing such an edge fails CI with output of the form:

   ```
   services must not depend on routes BROKEN

   mealie.services is not allowed to import mealie.routes:

   -   mealie.services.scheduler.tasks.delete_old_checked_shopping_list_items ->
   mealie.routes.households.controller_shopping_lists (l.7)
   ```

   Remaining upward edges are listed in `ignore_imports`; that list must shrink to empty before this ADR is considered fully realised.
2. **CI gate** — `lint-imports` runs in the existing pre-commit / CI pipeline alongside `ruff` and `mypy`, blocking any PR that introduces a new edge against the contract.
3. **Snapshot diff** — `docs/architecture/grimp.dot` is regenerated and diffed in review; an unexpected new cross-layer edge surfaces as a documentation diff even when it slips past the linter (e.g. via a dynamic import).

## More Information

* Building-block view defining the layer order: [`docs/arc42/05-building-block-view.md`](../arc42/05-building-block-view.md).
* Import graph snapshot: [`docs/architecture/grimp.dot`](../architecture/grimp.dot).
* Source of the violation: `mealie/services/scheduler/tasks/delete_old_checked_shopping_list_items.py:7`.
* Target of the violation: `mealie/routes/households/controller_shopping_lists.py:41` (`publish_list_item_events`), also called from lines 124, 138, 148, 260, 282 of the same file.
* Follow-up: a tracking issue should enumerate the remaining 62 grandfathered edges (notably `schema → db` ×34 from Pydantic schemas importing ORM column types, and `core → repos/services` from auth providers) so the ignore list can go to zero.
