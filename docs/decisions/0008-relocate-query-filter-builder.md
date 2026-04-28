---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Relocate `QueryFilterBuilder` from `mealie.services.query_filter` to `mealie.pkgs.query_filter`

## Context and Problem Statement

The repository layer imports `QueryFilterBuilder` from the service layer at `mealie/repos/repository_generic.py:28` (`from mealie.services.query_filter.builder import QueryFilterBuilder`). This inverts Mealie's canonical layering — `routes → services → repos → db` (see `mealie/CLAUDE.md` "Layer Responsibilities") — by adding a `repos → services` edge. The Pydantic schema layer reverses the same way: `mealie/schema/cookbook/cookbook.py:14` and `mealie/schema/meal_plan/plan_rules.py:12` both import `QueryFilterBuilder, QueryFilterJSON` from `mealie.services.query_filter.builder`. Three layers (`schema`, `repos`, `services`) currently form a cycle around what is, on inspection, a pure utility — it parses filter DSL strings into SQLAlchemy `ColumnElement` predicates and contains no business logic, no IO, and no domain state.

This is documented as a known problem in `/tmp/system-overview.md` §6.3 ("Layering inversions / cycle risk") and as open question 3 in §7. The LikeC4 model (`docs/architecture/mealie.c4`) currently shows only the canonical `mealie.api.services -> mealie.api.repos` edge; it does not expose the inverted `mealie.api.repos -> mealie.api.services` edge that the code actually contains, and `mealie.pkgs` is not modeled as a component at all (verified via `mcp__likec4__search-element` "pkgs" → 0 results). Closing this debt is a prerequisite for tightening the layered import-linter contract — the contract currently carries `mealie.services.query_filter -> mealie.repos.repository_generic` and `mealie.services.query_filter -> mealie.schema.*` as `ignore_imports` grandfather lines, masking real boundary breaks.

## Decision Drivers

* **Layered architecture invariant** — `repos` and `schema` must not import from `services`. The import-linter contract should enforce this without grandfather lines.
* **Reusability** — `mealie.pkgs.*` is the framework-agnostic utility namespace (per `CLAUDE.md` "Internal libs" — `cache`, `i18n`, `img`, `safehttp`, `stats`); a parser/builder utility belongs there, not under `services`.
* **No domain coupling** — `query_filter.builder` depends only on SQLAlchemy primitives and `mealie.schema.response.query_search.SearchFilter`; it has no service-layer dependencies, so the move is mechanical.
* **Single ADR closes one grandfather line** — each architectural-debt ADR in the Step 10 backlog (0007–0011) corresponds to exactly one `ignore_imports` line that gets deleted in the same PR that lands the move.
* **LikeC4 model accuracy** — the C4 model must reflect the actual import graph after the move; `mealie.pkgs` needs to be added as a modeled component.

## Considered Options

* Leave `QueryFilterBuilder` under `mealie.services.query_filter` and keep a permanent `ignore_imports` line in import-linter
* Move to `mealie.repos.query_filter` (host inside the only consumer that still needs it after schema is fixed)
* Move to `mealie.pkgs.query_filter` (chosen)
* Inline the builder at every call site

## Decision Outcome

Chosen option: "Move to `mealie.pkgs.query_filter`", because it is the only option that (a) closes the grandfather line cleanly without trading one inversion for another, (b) keeps the builder reusable across `repos`, `schema`, and any future module without re-introducing a layer crossing, and (c) honors the `mealie.pkgs` charter as the framework-agnostic utility home that already houses other cross-cutting helpers (`cache`, `safehttp`, `stats`).

The other options each fail at least one driver: leaving it under `services` permanently legitimizes the inversion and means the import-linter contract never tightens; moving it to `mealie.repos.query_filter` would still leave `mealie.schema.cookbook` and `mealie.schema.meal_plan` importing from `repos` (a fresh layering inversion); inlining is infeasible because the builder carries non-trivial parser state and is exercised by a dedicated test suite.

The LikeC4 model `docs/architecture/mealie.c4` must be updated as part of the same PR: add a `pkgs` component to the `api` container (alongside `routes`, `services`, `repos`, `schema`, `db`, `core`) and add the relationship `repos -> pkgs`. The `schema -> pkgs` edge will be added by ADR 0011's companion work or noted in the same PR if it lands first.

### Consequences

* Good, because the `repos -> services` and `schema -> services` grandfather lines in `pyproject.toml`'s `[tool.importlinter]` block are removed in the same PR, restoring the canonical layer order at the contract level.
* Good, because `mealie.pkgs.query_filter` becomes available to any future module (e.g., a CLI tool or a search-export utility) without dragging in the service layer.
* Good, because the move is mechanical — the builder has no service-layer dependencies — and the existing tests under `tests/unit_tests/services/test_query_filter.py` move with it under their new path.
* Bad, because the move is a breaking change for any third-party tooling or fork that imports `mealie.services.query_filter.builder` directly. Mitigation: a thin shim (`mealie/services/query_filter/builder.py` re-exporting from `mealie.pkgs.query_filter.builder`) can be kept for one release with a `DeprecationWarning`, then deleted in the following release.
* Bad, because `mealie.pkgs` was previously fully modeled as having no incoming edges from siblings (verified in `/tmp/system-overview.md` §2 notes); after this move, `repos -> pkgs` and `schema -> pkgs` become real edges. The C4 model and `architecture.yml` workflow must be updated atomically with the code move.
* Neutral, because no runtime behavior changes — the builder's class, public API, and SQL output are identical before and after the move.

### Confirmation

Compliance is enforced by `.github/workflows/architecture.yml` (introduced in Step 9 of the AI Gateway track bootstrap):

* The `import-linter` job parses `pyproject.toml` `[tool.importlinter]` contracts. The PR landing this ADR deletes the `ignore_imports` lines `mealie.services.query_filter -> mealie.repos.repository_generic`, `mealie.services.query_filter -> mealie.schema.cookbook.cookbook`, and `mealie.services.query_filter -> mealie.schema.meal_plan.plan_rules` (or the equivalent forward-direction grandfather entries currently allowing `repos -> services` and `schema -> services`). Any future re-introduction of an import from `mealie.services` into `mealie.repos` or `mealie.schema` fails the job.
* The `likec4` job validates that `docs/architecture/mealie.c4` parses and that the model is internally consistent after `pkgs` is added as a component and `repos -> pkgs` is added as a relationship.
* `task py:check` (ruff + mypy + pytest) must pass on the move PR with the relocated test module.

## More Information

* Supersedes nothing; extends the architecture-as-code stack established by ADR 0001.
* Related debt ADRs in the same backlog: 0007 (extract bootstrap wiring), 0009 (decouple seeders), 0010 (scheduler task ownership), 0011 (core auth adapter). Each closes one `ignore_imports` line.
* Source evidence:
  * `mealie/repos/repository_generic.py:28` — `repos -> services` import.
  * `mealie/schema/cookbook/cookbook.py:14`, `mealie/schema/meal_plan/plan_rules.py:12` — `schema -> services` imports of the same builder.
  * `mealie/services/query_filter/{builder,keywords,operators}.py` — current location.
  * `mealie/pkgs/{cache,i18n,img,safehttp,stats}/` — sibling utilities that establish the `pkgs` precedent.
* LikeC4 element ids cited from `mcp__likec4__read-element`: `mealie.api.services`, `mealie.api.repos`. `mealie.pkgs` is not yet a modeled element — this ADR's companion PR adds it.
* When to revisit: if a future feature requires `query_filter` to call into a service (e.g., dynamic filter operators driven by a domain registry), this ADR's premise — that the builder is a pure utility — no longer holds, and a successor ADR should re-evaluate placement.
