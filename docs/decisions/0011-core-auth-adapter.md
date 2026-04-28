---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Promote auth-provider DB lookups out of `mealie.core` via a thin `auth_adapter` in services

## Context and Problem Statement

ADR 0001 adopted LikeC4 + import-linter as the Architecture-as-Code stack and treats `mealie.core` as a framework-agnostic leaf — settings, security primitives, exceptions, and the root logger — that nothing-app-specific reaches into. The LikeC4 model agrees: a query against `mealie.api.core` (declared at `docs/architecture/mealie.c4:19`) returns zero outgoing relationships and a single incoming edge from `mealie.api.services -> mealie.api.core` (line 41). The Python import graph contradicts that picture: `mealie/core/security/providers/auth_provider.py:8`, `credentials_provider.py:10-13`, `ldap_provider.py:10-11`, and `openid_provider.py:10-11` all import from `mealie.repos.all_repositories`, `mealie.db.models.users.users`, and (for credentials) `mealie.services.user_services.user_service`. Without a refactor, any layered import-linter contract for the AI Gateway track requires permanent `ignore_imports` exemptions for the security-critical providers — exactly the kind of carve-out that ADR 0001 was meant to prevent.

## Decision Drivers

* `mealie.core` must be a sink — zero outgoing edges from `mealie.api.core` in the LikeC4 model, enforced by an import-linter `independence` contract that forbids `mealie.core` from importing `mealie.repos`, `mealie.db`, or `mealie.services`.
* OIDC and LDAP wiring must be visible in the layered diagram — a `mealie.api.services.authAdapter` element appears in `mealie.c4` and is referenced by the auth slice view, so reviewers and agents see the authentication flow without reading code.
* ADR 0001's AaC promise (agents and humans read architecture from the C4 source) collapses if the largest known cross-layer importer is hidden under a permanent ignore.
* `AuthProvider` ABC semantics observed by `mealie.routes.auth.auth` must not change — existing OIDC, LDAP, and credentials flows continue to work without behavioural drift.

## Considered Options

* Leave providers in `mealie.core` with a permanent `ignore_imports` entry in import-linter.
* Extract a thin `mealie.services.auth_adapter` exposing `get_user_by_email(...)`, `get_user_by_username(...)`, `update_login_attempts(...)`, etc.; providers depend on an adapter protocol declared in core, the adapter implementation lives in services and owns repo access.
* Move the entire `mealie.core.security.providers.*` package to `mealie.services.auth.providers`.
* Extract `mealie.repos.auth_lookup` and have providers (still in core) import it.

## Decision Outcome

Chosen option: "Extract a thin `mealie.services.auth_adapter`", because it is the only option that keeps the `AuthProvider` strategy/ABC in core (where it belongs as a security primitive with no DB, no app wiring) while moving every database-touching call out of core. Providers receive an `AuthLookupAdapter` protocol via constructor injection; the concrete implementation in `mealie.services.auth_adapter` becomes the single module that touches `repos`/`db` for authentication purposes, restoring `mealie.core` as a true sink in both the LikeC4 model and the Python import graph.

### Consequences

* Good, because `mealie.core` becomes a true sink — the four `ignore_imports` exemptions for `mealie.core.security.providers.*` can be removed from `pyproject.toml` and the import-linter `independence` contract for core becomes real rather than performative.
* Good, because the OIDC/LDAP/credentials flow shows up in `mealie.c4` as `routes -> authAdapter -> repos` instead of the current invisible `core -> repos` shortcut, so reviewers and AI agents reading the model can trace authentication end-to-end.
* Good, because the adapter is a natural test seam — integration tests can inject a fake `AuthLookupAdapter` instead of patching `get_repositories`, which the current providers force.
* Bad, because every concrete provider gains a constructor parameter; call sites in `mealie/routes/auth/auth.py` and `mealie/core/dependencies/dependencies.py` must be updated in lockstep with the extraction.
* Bad, because this churn lands in security-critical code (ADR 0001 explicitly lists `mealie/core/security/providers/` as a security hotspot), so the PR will need careful review and a green test pass on both SQLite and PostgreSQL.
* Neutral, because the existing `LDAP_*` and `OIDC_*` settings under `mealie.core.settings` are unaffected — only the lookup path changes, not the configuration surface.

### Confirmation

* The four `ignore_imports` lines covering `mealie.core.security.providers.* -> mealie.{repos,db,services}` are removed from `pyproject.toml` in the same PR that lands the adapter.
* A new import-linter `independence` contract is added to `pyproject.toml` `[tool.importlinter]` declaring that `mealie.core` may not import any of `mealie.repos`, `mealie.db`, `mealie.services`. The contract is run by the `import-linter` job in `.github/workflows/architecture.yml` (the workflow introduced in ADR 0001).
* The `likec4` job in the same workflow validates that the new `mealie.api.services.authAdapter` element resolves and that the auth-slice view renders without errors.

## Pros and Cons of the Options

### Leave providers in core with a permanent `ignore_imports`

* Good, because zero code churn and no behavioural risk.
* Bad, because it defeats the purpose of ADR 0001 — the layered contract becomes performative if its largest violator is permanently exempted, and every future contributor sees the exemption as license to add more.
* Bad, because the auth flow stays invisible in the LikeC4 model (no edge between `core` and `repos` is allowed), so the diagram and the code permanently disagree.

### Extract a thin `mealie.services.auth_adapter` (chosen)

* Good, because it cleanly separates the strategy/ABC primitive (which belongs in core) from the DB-bound lookup (which belongs in services).
* Good, because the adapter protocol is a natural dependency-injection seam for testing without monkeypatching `get_repositories`.
* Neutral, because two modules now exist where one did — the protocol declaration in `mealie.core.security` and the implementation in `mealie.services.auth_adapter`.
* Bad, because every provider call site needs updating in a single PR; partial migration would leave the codebase in a worse state than today.

### Move the entire `mealie.core.security.providers.*` package to `mealie.services.auth.providers`

* Good, because it is the simplest mechanical refactor — `git mv` plus updating imports.
* Bad, because the `AuthProvider` ABC and password-hashing helpers are genuine primitives with no DB or service-layer dependencies; moving them out of core fragments the security primitives across two modules.
* Bad, because the strategy code does not need to know anything about `repos` or `db`; this option moves more code than the layering violation actually requires.

### Extract `mealie.repos.auth_lookup` and have providers (still in core) import it

* Good, because the lookup logic gets a single home in `repos` rather than being duplicated across providers.
* Bad, because providers in `mealie.core` would still import `mealie.repos`, which is the same layering violation as today — just renamed. The independence contract for `core` would still need an exemption.

## More Information

`docs/architecture/mealie.c4` currently has no `authAdapter` component and no `auth` boundary inside `mealie.api.core`. This ADR's implementation PR must add a `mealie.api.services.authAdapter` component, plus relationships `routes -> authAdapter` and `authAdapter -> repos`, and either a new auth-slice view or an extension to the existing component view that surfaces the authentication flow. The MCP query performed at decision time confirmed that `mealie.api.core` has zero outgoing relationships in the model — the diagram is already correct in intent; the code is the side that must change.

Affected concrete code paths in scope: `mealie/core/security/providers/auth_provider.py:8`, `credentials_provider.py:10-13`, `ldap_provider.py:10-11`, `openid_provider.py:10-11`. Out of scope for this ADR but related: `mealie/core/dependencies/dependencies.py:17-18` also imports `mealie.db.db_setup` and `mealie.repos.all_repositories`; that violation is a candidate for ADR 0007's bootstrap-extraction work.

Related decisions: ADR 0007 (extract bootstrap wiring out of `mealie.db.init_db`) and ADR 0008 (relocate `services.query_filter.builder` to `mealie.pkgs`) are sibling architectural-debt ADRs targeting the same import-linter cleanup. When all three land, the layered import-linter contract from ADR 0001 can drop every grandfather exemption.
