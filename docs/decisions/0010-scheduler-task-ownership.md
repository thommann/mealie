---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Scheduler task callbacks own their logic in `mealie.services` and must not import from `mealie.routes`

## Context and Problem Statement

Mealie's recurring background work runs through `SchedulerRegistry` (`mealie/app.py:27`) with task callables aggregated in `mealie/services/scheduler/tasks/__init__.py`. The package docstring declares these are registered "as a post-startup task", and the eight tasks shipped today (`create_mealplan_timeline_events`, `delete_old_checked_list_items`, `post_group_webhooks`, `purge_*`, `locked_user_reset`) are wired in via that aggregator. The architecture model (`docs/architecture/mealie.c4`) places this work under the LikeC4 component `mealie.api.services`, with the canonical inbound edge being `mealie.api.routes -> mealie.api.services` (verified via `find-relationships`, `mealie.c4:36`). There is no edge in the opposite direction.

The aggregator pattern hides import direction from quick review, and the layer is in fact already breached: `mealie/services/scheduler/tasks/delete_old_checked_shopping_list_items.py:7` does `from mealie.routes.households.controller_shopping_lists import publish_list_item_events`. That import inverts the layer (`services -> routes`) and makes the task callback structurally dependent on the HTTP layer it should be feeding. As we tighten the layered import-linter contracts during the AI Gateway track, this kind of latent inversion will start failing CI in surprising places unless we declare an explicit rule and clean up the existing case. Question 2 of `/tmp/system-overview.md` §7 raised this directly; the CLAUDE.md "APScheduler = multiple processes = multiple runs" caveat is a separate but adjacent operational concern that is **not** addressed here.

## Decision Drivers

* The architecture model (`mealie.c4:36`) declares `routes -> services` as a one-way edge; any `services -> routes` import contradicts the documented shape and must be either removed or re-expressed in the model.
* `mealie.routes` is a thin HTTP wrapper around `mealie.services`. A service module importing a route handler is always a sign that shared logic was left in the route by accident — pulling it back across the layer hides the smell instead of fixing it.
* Dynamic task loading via `mealie/services/scheduler/tasks/__init__.py` makes layer violations easy to overlook in review; the rule must be enforced statically by CI, not by vigilance.
* import-linter contracts must remain readable — adding ten per-task contracts to cover scheduler edges would make `pyproject.toml` unmaintainable.

## Considered Options

* Allow ad-hoc imports from `mealie.routes` in scheduler tasks (status quo)
* Forbid `mealie.services -> mealie.routes` outright via an import-linter `forbidden` contract; relocate any shared helper a task currently imports from a route into a service module (chosen)
* Move the scheduler out of `mealie.services` into a top-level `mealie.scheduler` package so it can import from any layer
* Extract a thin "task contract" interface in `mealie.schema` that routes and tasks both depend on

## Decision Outcome

Chosen option: "Forbid `mealie.services -> mealie.routes` outright via an import-linter `forbidden` contract; relocate any shared helper a task currently imports from a route into a service module", because it is the only option that both matches the documented model edge in `mealie.c4` and is enforceable statically. The status quo option leaves the inversion in place and ensures the next aggregated task to be added will reintroduce the same smell. Hoisting the scheduler to a top-level `mealie.scheduler` package would solve the contract problem mechanically but legitimises the inversion at the cost of a brand-new top-level layer that the C4 model does not have. Putting a "task contract" interface in `mealie.schema` over-engineers the eight callbacks we actually have and pushes behaviour into the schema layer, which is meant to hold DTOs.

The concrete cleanup is small: `mealie/services/scheduler/tasks/delete_old_checked_shopping_list_items.py:7` imports `publish_list_item_events` from `mealie.routes.households.controller_shopping_lists`. That helper moves into `mealie.services.household_services` (or a peer service module) and the route imports it from there; the task imports it from the same service location. No public API changes.

### Consequences

* Good, because the architecture model (`mealie.c4`) and the Python import graph agree — `services -> routes` is forbidden in both.
* Good, because the rule is enforced by CI (import-linter via `architecture.yml`), not by reviewer attention to the dynamic-import aggregator.
* Good, because the `delete_old_checked_list_items` cleanup pulls genuinely shared logic (`publish_list_item_events`) into the service layer where its other caller (the route) can also reach it without crossing layers.
* Bad, because contributors adding new scheduled tasks must now resist the (sometimes convenient) habit of reaching into a route module to reuse glue code; some glue must be relocated or duplicated into services.
* Bad, because the rule does not directly address the multi-worker scheduler concern from CLAUDE.md — that requires a separate ADR (proposed `0014` or similar) on leader election or single-worker deployment.
* Neutral, because the dynamic re-export in `tasks/__init__.py` continues to work unchanged; the contract operates on the underlying module imports, not on the aggregator surface.

### Confirmation

A new import-linter `forbidden` contract is added to `pyproject.toml` under `[tool.importlinter]`:

```toml
[[tool.importlinter.contracts]]
name = "scheduler tasks must not import from mealie.routes"
type = "forbidden"
source_modules = ["mealie.services"]
forbidden_modules = ["mealie.routes"]
```

The contract is exercised by the `import-linter` job in `.github/workflows/architecture.yml` (introduced in Step 9 of the AI Gateway track bootstrap). Closing this ADR requires zero `ignore_imports` lines for the contract — i.e. the `delete_old_checked_shopping_list_items.py` cleanup must land in the same PR that adds the contract, otherwise the contract goes in red. The LikeC4 model already encodes the corresponding edge direction (`mealie.c4:36`); no model change is needed.

## More Information

- LikeC4 element ids touched: `mealie.api.services`, `mealie.api.routes` (verified via `find-relationships`, source `docs/architecture/mealie.c4:36`).
- Concrete violation to clean up: `mealie/services/scheduler/tasks/delete_old_checked_shopping_list_items.py:7`.
- Open question this ADR closes: `/tmp/system-overview.md` §7, item 2 ("Should the scheduler's dynamic imports be exempted from layered import-linter rules?") — answer: no, no exemption; fix the one offender instead.
- Out of scope: APScheduler multi-worker behaviour (CLAUDE.md "APScheduler = multiple processes = multiple runs"). A separate ADR should record the deployment constraint or migrate to leader-elected scheduling.
