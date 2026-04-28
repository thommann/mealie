---
status: "accepted"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Introduce `mealie.services.ai_gateway` as the sole egress to LLM providers

## Context and Problem Statement

Mealie's LLM surface today is scattered across five files (per `/tmp/system-overview.md` §6.2): `mealie/services/openai/openai.py` (lines 10-12 hold the only direct `import openai`, `from openai import AsyncOpenAI`, and `from openai.types.chat import ChatCompletion`), `mealie/services/parser_services/openai/parser.py:14`, `mealie/services/recipe/recipe_service.py:35`, `mealie/services/scraper/scraper_strategies.py:31`, and `mealie/routes/admin/admin_debug.py:11`, configured by 14 `OPENAI_*` keys in `mealie/core/settings/settings.py:391-443`. Adding a second provider (Anthropic, Ollama) under this shape means editing five call sites, four prompt locations, and renaming half the settings — work that no single PR can do safely. The LikeC4 model in `docs/architecture/mealie.c4` already names the target shape — `mealie.api.aiGateway` (lines 22-24) and `mealie.api.aiClients` (lines 25-27), both tagged `#ai`, with `mealie.api.services -> mealie.api.aiGateway -> mealie.api.aiClients -> llmProvider` as the only allowed egress chain. ADR 0001 chose LikeC4 + import-linter as the AaC stack; this ADR is the first concrete refactor that stack gates, and it must answer one question: where does the LLM SDK live?

## Decision Drivers

* A second LLM provider must be addable by writing one new client class without touching recipe, parser, scraper, or admin code.
* `import openai` (or `import anthropic`) outside one designated module must fail CI, not depend on review vigilance.
* The 14 `OPENAI_*` settings must be migratable to provider-neutral names behind a single owner, with a Pydantic `validation_alias` deprecation window for self-hosters' `.env` files.
* The LikeC4 element ids `mealie.api.aiGateway` and `mealie.api.aiClients` already exist in `docs/architecture/mealie.c4`; the Python module layout must catch up to the model so `architecture.yml` can enforce the boundary.
* The solution must stay in-process — Mealie ships as a single FastAPI container to self-hosters, and adding a deployment unit raises the operational tax for every user.

## Considered Options

* Status quo — leave the five direct call sites and 14 `OPENAI_*` settings in place
* Per-feature wrappers — one thin wrapper per consumer (recipe service, parser, scraper, admin_debug)
* Single in-process Gateway module — `mealie.services.ai_gateway` owns all SDK imports and provider adapters
* External proxy — run a LiteLLM/OpenRouter sidecar alongside the Mealie container

## Decision Outcome

Chosen option: "Single in-process Gateway module", because it is the only option that simultaneously (a) allows import-linter contract 2 to become enforceable end-to-end, (b) collapses provider-specific code to one location so adding Anthropic or Ollama is a one-file change, and (c) keeps Mealie a single-container deployment for self-hosters. `mealie.services.ai_gateway` becomes the single Python module permitted to import any LLM SDK. All other consumers (recipe, parser, scraper, admin debug) call it through a provider-agnostic interface. The module owns the provider adapters under `mealie.services.ai_gateway.clients` — the Python embodiment of the LikeC4 `mealie.api.aiClients` component. Future ADRs (0003 second provider, 0004 prompt asset format, 0005 PII redaction, 0006 eval harness) extend this module rather than reopening the egress decision.

### Consequences

* Good, because the AI surface area becomes greppable — one module path, one settings prefix path, one prompt directory, one set of telemetry hooks.
* Good, because import-linter contract 2 (`AI egress only via mealie.services.ai_gateway`, declared at `pyproject.toml:221-244`) becomes enforceable end-to-end once each call site is migrated and its `ignore_imports` line removed.
* Good, because ADRs 0003-0006 can land without re-litigating where the LLM SDK lives — they extend a module that already owns the boundary.
* Good, because the LikeC4 element ids `mealie.api.aiGateway`, `mealie.api.aiClients`, and `llmProvider` (cited verbatim from the MCP) match the Python module layout, so the model and the code agree.
* Bad, because migration touches five files plus 14 settings; contract 2's `ignore_imports` list grows to cover the in-flight call sites until each one moves, with `unmatched_ignore_imports_alerting = "none"` masking premature cleanup until the module exists.
* Bad, because the `OPENAI_*` env-var rename needs a Pydantic `validation_alias` deprecation window (system-overview §7.1) — self-hosters cannot be forced to rewrite `.env` files in a single release.
* Neutral, because choosing in-process over an external proxy means we own the provider-adapter code; revisitable in a future ADR if operational cost makes a sidecar worth the deployment-unit tax.

### Confirmation

Compliance is enforced by `.github/workflows/architecture.yml`:

* The `import-linter` job runs contract 2 (`AI egress only via mealie.services.ai_gateway`) at `pyproject.toml:221-244`. The contract bans `openai` and `anthropic` imports from `mealie.routes`, `mealie.repos`, `mealie.schema`, `mealie.db`, `mealie.services.recipe`, and `mealie.services.parser_services`. The single grandfather line this ADR is responsible for retiring is `"mealie.services.openai.openai -> openai"` (line 240). Each PR that migrates one of the five call sites must delete its corresponding `ignore_imports` line in the same diff; the ADR is fully discharged when that line is gone.
* The `likec4` job validates that `docs/architecture/mealie.c4` parses and that `mealie.api.aiGateway` and `mealie.api.aiClients` remain the only `#ai`-tagged components inside `mealie.api`. Adding a third `#ai`-tagged component without an ADR fails the job.

## Pros and Cons of the Options

### Status quo

* Good, because zero migration cost today.
* Bad, because second-provider work is blocked behind a five-file edit.
* Bad, because the `OPENAI_*` rename is impossible without a coordinated rip.
* Bad, because import-linter contract 2 stays permanently grandfathered, which makes the gate decorative.
* Bad, because ADRs 0003-0006 cannot land cleanly — every one of them would need to re-justify where the LLM SDK lives.

### Per-feature wrappers

* Good, because each refactor PR is small and isolated.
* Neutral, because it adds a layer without consolidating.
* Bad, because four wrappers mean four places to add an Anthropic adapter, four prompt directories, four redaction policies, four telemetry hooks.
* Bad, because the LikeC4 model has one `aiGateway` component, not four — adopting wrappers would require either editing the model to match the code or accepting permanent model/code drift.

### Single in-process Gateway module (chosen)

* Good, because one module owns the SDK, the prompts, the redaction policy, and the telemetry — adding a provider is a one-file change.
* Good, because the import-linter contract reduces to "only `mealie.services.ai_gateway` imports `openai`/`anthropic`", which is mechanically checkable.
* Good, because `mealie.api.aiGateway` and `mealie.api.aiClients` already exist in the LikeC4 model — the code catches up to the model rather than the reverse.
* Bad, because the migration is the biggest of the four options; contract 2 stays partially grandfathered until every call site moves.
* Neutral, because the module owns the provider-adapter code Mealie now maintains directly.

### External proxy (LiteLLM / OpenRouter sidecar)

* Good, because provider abstraction is delegated to a maintained third-party.
* Bad, because Mealie ships as a single container to self-hosters; an extra sidecar moves routing, auth, version-pinning, and telemetry out of the repo and onto the user.
* Bad, because PII redaction (ADR 0005, seeded by `OPENAI_SEND_DATABASE_DATA`) becomes harder to enforce — the proxy is opaque to our code.
* Bad, because failure modes multiply: a misconfigured sidecar is now a Mealie support burden.
* Neutral, because revisitable later if Mealie reaches a scale where an external gateway pays for its operational cost.

## More Information

This ADR is the foundation of the AI Gateway track. Direct sequels:

* `0003-add-second-provider.md` — Anthropic / Ollama via the Gateway's provider abstraction.
* `0004-prompt-asset-format.md` — externalised prompts under `mealie/services/ai_gateway/prompts/`.
* `0005-pii-redaction.md` — what recipe / household data may leave the Gateway; `OPENAI_SEND_DATABASE_DATA` (settings.py line ~430) is the policy seed.
* `0006-eval-harness.md` — Promptfoo or DeepEval CI gate scoped to the Gateway's outputs.

Architectural-debt ADRs `0007-0011` retire grandfather lines in import-linter contracts 1 and 3 and are independent of this decision; they progress in parallel.

The decision is realisable incrementally: each of the five call sites moves in its own PR, deletes its `ignore_imports` line, and the ADR is fully discharged when the last line is gone. Revisit if a future provider's SDK cannot reasonably be wrapped behind the Gateway interface, or if operational evidence ever makes the external-proxy option pay for itself.
