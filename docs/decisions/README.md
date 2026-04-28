# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) in [MADR](https://adr.github.io/madr/) format. Each file is numbered sequentially as `NNNN-kebab-case-title.md` (e.g. `0001-record-architecture-decisions.md`). Once merged, ADRs are immutable — supersede an existing decision by adding a new ADR that references the prior one rather than editing history.

## Index

| # | Title | Status |
|---|-------|--------|
| 0001 | [Adopt LikeC4, MADR ADRs, and import-linter as the AaC stack](0001-adopt-c4-and-adrs.md) | accepted |
| 0002 | [Introduce `mealie.services.ai_gateway` as the sole egress to LLM providers](0002-introduce-ai-gateway.md) | accepted |
| 0003 | [Add a second LLM provider (Anthropic / Ollama) behind the AI Gateway via a provider abstraction](0003-add-second-provider.md) | proposed |
| 0004 | [Externalise LLM prompts as YAML assets under the AI Gateway](0004-prompt-asset-format.md) | proposed |
| 0005 | [Enforce a hard PII denylist on every AI Gateway egress payload](0005-pii-redaction.md) | proposed |
| 0006 | [Adopt Promptfoo as the eval harness gating AI Gateway prompt outputs in CI](0006-eval-harness.md) | proposed |
| 0007 | [Extract bootstrap wiring out of `mealie.db.init_db` into a dedicated `mealie.bootstrap` module](0007-extract-bootstrap-wiring.md) | proposed |
| 0008 | [Relocate `QueryFilterBuilder` from `mealie.services.query_filter` to `mealie.pkgs.query_filter`](0008-relocate-query-filter-builder.md) | proposed |
| 0009 | [Decouple repository seeders from `mealie.services`](0009-decouple-seeders.md) | proposed |
| 0010 | [Scheduler task callbacks own their logic in `mealie.services` and must not import from `mealie.routes`](0010-scheduler-task-ownership.md) | proposed |
| 0011 | [Promote auth-provider DB lookups out of `mealie.core` via a thin `auth_adapter` in services](0011-core-auth-adapter.md) | proposed |
