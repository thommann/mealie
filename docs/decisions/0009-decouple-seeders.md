---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Decouple repository seeders from `mealie.services`

## Context and Problem Statement

The canonical layer direction in the LikeC4 model is `mealie.api.services -> mealie.api.repos` (single edge at `docs/architecture/mealie.c4:37`). The reverse edge does not exist in the model. The Python import graph, however, contains a reverse violation: `mealie/repos/seed/seeders.py:12` imports `MultiPurposeLabelService` from `mealie.services.group_services.labels_service`, used at `seeders.py:21` only to construct a service instance the seeder then drives. This single import is the only `repos -> services` edge in `mealie/repos/seed/`; it is currently grandfathered in `pyproject.toml:216` (`mealie.repos.seed.seeders -> mealie.services.group_services.labels_service`) and blocks the layered import-linter contract from being tightened. ADR 0008 retires the parallel `query_filter` violations in `repository_generic` / `repository_recipes`; this ADR retires the seeder line so the two together fully delete the `repos -> services` grandfather block.

## Decision Drivers

* The LikeC4 model declares one direction (`services -> repos`); the implementation must match what the model and import-linter declare.
* Seeding runs once at boot from `mealie/db/init_db.py` and operates on a small, well-known set of writes — it does not need the full transactional / event-emitting service surface.
* `mealie.core.security` already owns password hashing; `init_users` therefore does not require any service-layer dependency once label seeding is unhooked.
* The grandfather block in `pyproject.toml` should shrink to zero; every line still present after ADR 0008 + ADR 0009 land would be unjustified.

## Considered Options

* Leave seeders coupled to `mealie.services` and keep the grandfather line indefinitely.
* Extract a thin `mealie.repos.seed.helpers` module that performs the narrow writes the seeder needs, calling the repository layer directly (chosen).
* Move seeding into `mealie.services` and have services orchestrate boot — i.e. invert the call site.
* Move seeding into Alembic data migrations.

## Decision Outcome

Chosen option: "Extract a thin `mealie.repos.seed.helpers` module", because it aligns the import graph with the LikeC4 model without introducing a new layer-crossing direction or coupling boot to migrations. The label-seeding path that `MultiPurposeLabelSeeder` currently borrows from `MultiPurposeLabelService` is a single repository write (`group_multi_purpose_labels.create`) plus a name-uniqueness check; reproducing that against `self.repos.group_multi_purpose_labels` directly removes the only `from mealie.services` import in `mealie/repos/`. Inverting boot orchestration into services (option 3) makes the grandfather problem worse — `services` would then call `repos` AND `db.init_db` would still be the entry point. Alembic data migrations (option 4) couple seeding to schema versioning, which is heavier than the bootstrap case warrants and conflicts with the locale-driven `foods/locales/*.json` resource loading already in `mealie/repos/seed/`.

### Consequences

* Good, because `from mealie.services` greps inside `mealie/repos/` will return zero hits, allowing the `mealie.repos.seed.seeders -> mealie.services.group_services.labels_service` line to be deleted from `pyproject.toml:216` in the same PR as the refactor.
* Good, because together with ADR 0008 (query_filter relocation) the entire `repos -> services` grandfather block disappears from the layered contract.
* Good, because the seeder becomes simpler — no `cached_property service` indirection, just direct repo calls.
* Bad, because the small slice of label-creation logic in `MultiPurposeLabelService` is duplicated rather than reused. The duplication is acceptable: the seed path is bootstrap-only and does not need event emission, audit hooks, or HTTP-shaped error translation.
* Bad, because a future change to label-creation invariants must be applied in two places. Mitigated by the fact that the seed helper performs strictly fewer operations than the service (no event bus dispatch, no permission checks).
* Neutral, because `init_users` continues to use `mealie.core.security` for password hashing — that edge is allowed by the layered contract.

### Confirmation

Compliance is enforced mechanically:

* `grep -rn "from mealie.services" mealie/repos/` must return zero hits. Verified locally and in CI via the `import-linter` job in `.github/workflows/architecture.yml`.
* The grandfather line `mealie.repos.seed.seeders -> mealie.services.group_services.labels_service` is removed from `pyproject.toml` (`[tool.importlinter]` `ignore_imports`, currently `pyproject.toml:216`) in the same PR as the refactor. Re-introducing the import will fail the layered contract.
* The seed integration path (`mealie/db/init_db.py` → `MultiPurposeLabelSeeder.seed`) remains covered by existing boot tests; a green `task py:check` run is the regression gate.

## More Information

* LikeC4 grounding: `mcp__likec4__find-relationships` between `mealie.api.repos` and `mealie.api.services` returns exactly one direct edge, `mealie.api.services -> mealie.api.repos`, defined at `docs/architecture/mealie.c4:37`.
* Concrete violation enumerated by `grep -rn "from mealie.services" mealie/repos/`:
  * `mealie/repos/seed/seeders.py:12` — owned by this ADR.
  * `mealie/repos/repository_generic.py:28`, `mealie/repos/repository_recipes.py:30` — owned by ADR 0008.
* Related ADRs: ADR 0001 (architecture-as-code stack), ADR 0007 (extract bootstrap wiring out of `db/`), ADR 0008 (relocate `query_filter` builder).
