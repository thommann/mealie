---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Extract bootstrap wiring out of `mealie.db.init_db` into a dedicated `mealie.bootstrap` module

## Context and Problem Statement

The LikeC4 model (`docs/architecture/mealie.c4`) declares the canonical layered direction `mealie.api.repos -> mealie.api.db` and `mealie.api.services -> mealie.api.repos`/`mealie.api.services -> mealie.api.schema`; it does **not** declare any edge from `mealie.api.db` outward. The Python import graph contradicts the model: `mealie/db/init_db.py` lines 17-23 import `mealie.repos.all_repositories`, `mealie.repos.repository_factory`, `mealie.repos.seed.init_users`, `mealie.schema.household.household`, `mealie.schema.user.user`, `mealie.services.group_services.group_service`, and `mealie.services.household_services.household_service` to seed the first-run group, household, and admin user. This is a direct inversion of the declared layering and is currently grandfathered as five `ignore_imports` lines under contract 1 in `pyproject.toml` (lines 200-205, owned by this ADR per the comment on line 200). The inversion is documented in `/tmp/system-overview.md` §6.3 and called out as Open Question 4 in §7. The decision is *where* the seeding logic should live so that `mealie.db` can stop importing higher layers and the grandfather lines can be deleted.

## Decision Drivers

* The `routes -> services -> repos -> db` layering must hold at the Python import-graph level so that `import-linter` can enforce it without exemptions.
* `mealie.db` is intended to host ORM models and Alembic plumbing only; pulling the service layer into it makes `db` non-extractable as a low-level package and makes the dependency graph cyclic at the package level.
* Bootstrap-time-only coupling is "safe at runtime" (init runs once before the app accepts traffic) but still blocks the contract — a tool that approves cycles for runtime safety is a tool we cannot trust on the next refactor.
* New contributors must not be required to understand which layered violations are "fine because bootstrap" versus which are real bugs; the import-linter contract should be unconditional.
* Seed operations need access to repos and to two service classes (`GroupService`, `HouseholdService`) for password hashing and household creation — the chosen home must be allowed to import both.

## Considered Options

* Leave `mealie/db/init_db.py` as-is with permanent `ignore_imports` entries
* Extract a new top-level `mealie.bootstrap` module that owns first-run seeding and is invoked from the FastAPI lifespan (chosen)
* Move first-run seeding into Alembic data migrations
* Inline the minimal seed logic directly into `mealie/app.py` lifespan

## Decision Outcome

Chosen option: "Extract a new top-level `mealie.bootstrap` module", because it is the only option that simultaneously (a) restores the layered direction in the import graph, (b) keeps `mealie.db` ignorant of higher layers as the LikeC4 model already asserts, and (c) preserves the existing seed semantics (idempotent, runs after Alembic, uses `GroupService` and `HouseholdService` for tenant-correct creation). `mealie.bootstrap` is allowed to import `db`, `repos`, `schema`, and `services` — that is its job as a composition root for first-run state, mirroring the role `mealie.app` already plays for runtime wiring. `mealie/db/init_db.py` is reduced to Alembic upgrade orchestration and `mealie/db/fixes/*` invocation; the `default_user_init`, `GroupService.create_group`, and `HouseholdService.create_household` calls move into `mealie.bootstrap`. The lifespan in `mealie/app.py` then calls `init_db.main()` followed by `mealie.bootstrap.seed_first_run()`.

### Consequences

* Good, because the five grandfather lines (`pyproject.toml` lines 201-205) can be deleted in the same PR that lands `mealie.bootstrap`, and the `routes -> services -> repos -> db` contract becomes unconditional.
* Good, because the LikeC4 model and the Python import graph agree — `mealie.api.db` has no outgoing edges to siblings in either source.
* Good, because future debt closure ADRs (0009 seeders, 0011 core-auth-adapter) inherit a known-good "composition root" pattern to follow.
* Bad, because there is now a new top-level package contributors must learn; "where does first-run seeding live" stops being answered by `db/init_db.py` and starts being answered by `bootstrap/`.
* Bad, because the lifespan in `mealie/app.py` gains one more call site, marginally increasing startup-sequence complexity (Alembic → fixes → bootstrap seed → scheduler).
* Neutral, because the runtime behaviour is unchanged — the same functions run in the same order; only the importing module changes.

### Confirmation

The `import-linter` job in `.github/workflows/architecture.yml` enforces compliance. This ADR is confirmed closed when the following five lines are deleted from `pyproject.toml` (`[[tool.importlinter.contracts]]` "Layered architecture") in the same PR as the refactor:

```
"mealie.db.init_db -> mealie.repos.all_repositories",
"mealie.db.init_db -> mealie.repos.repository_factory",
"mealie.db.init_db -> mealie.repos.seed.init_users",
"mealie.db.init_db -> mealie.services.group_services.group_service",
"mealie.db.init_db -> mealie.services.household_services.household_service",
```

After deletion, `uv run lint-imports` must pass on a clean checkout. The LikeC4 model already reflects the target shape (`docs/architecture/mealie.c4`: `repos -> db` at line 39, no `db -> *` edges), so no `.c4` change is required by this ADR.

## Pros and Cons of the Options

### Leave `mealie/db/init_db.py` as-is with permanent `ignore_imports`

* Good, because zero refactor cost.
* Bad, because it permanently encodes a layering violation in the build configuration; future readers cannot distinguish "real exemption" from "tech debt we forgot".
* Bad, because it contradicts the LikeC4 model — the source-of-truth diagram and the source-of-truth import graph diverge.

### Extract a new top-level `mealie.bootstrap` module (chosen)

* Good, because it gives seeding an honest home that is allowed by layering to import both repos and services.
* Good, because it lets the layered contract become unconditional, which is a precondition for trusting future layered contracts (ADRs 0008-0011).
* Neutral, because `mealie.bootstrap` is one more package to learn; the cost is paid once.
* Bad, because the move touches `mealie/app.py` lifespan ordering — a small but real risk surface during the refactor.

### Move first-run seeding into Alembic data migrations

* Good, because it reuses Alembic's existing run-once semantics.
* Bad, because Alembic data migrations are required to use inline `sa.table()` stubs and may not import live ORM models or services (per `mealie/CLAUDE.md` "Alembic Migration Rules" §3); password hashing via `GroupService` cannot run inside a migration.
* Bad, because it conflates schema change with seed data — a schema-only downgrade would have to drop seeded rows.

### Inline minimal seed logic directly into `mealie/app.py` lifespan

* Good, because it avoids creating a new package.
* Bad, because `mealie/app.py` is already a churn hotspot (per `/tmp/system-overview.md` §6.4) and the composition root for the FastAPI app — adding ~80 lines of seed logic to it makes the entrypoint harder to reason about.
* Bad, because it does not solve the problem at the right altitude: `mealie.app` is the runtime composition root, not the bootstrap composition root, and conflating the two makes both harder to test in isolation.

## More Information

This ADR is one of five debt-retirement ADRs (0007-0011) seeded by `/tmp/system-overview.md` §6 and §7. Each owns a distinct block of `ignore_imports` lines in `pyproject.toml`; closing an ADR means deleting its block in the same PR. Order of execution is independent — 0007 has no prerequisites and unblocks reviewers' confidence that the layered contract is real before later refactors land.

LikeC4 elements affected (verbatim from `mcp__likec4__find-relationships`): `mealie.api.db`, `mealie.api.repos`, `mealie.api.services`, `mealie.api.schema`. Confirmed direct relationships in the model: `mealie.api.repos -> mealie.api.db` (`mealie.c4:39`), `mealie.api.services -> mealie.api.repos` (`mealie.c4:37`), `mealie.api.services -> mealie.api.schema` (`mealie.c4:38`). No `mealie.api.db -> *` relationship exists in the model — this ADR makes the Python import graph match.
