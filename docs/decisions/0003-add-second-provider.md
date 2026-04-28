---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Add a second LLM provider (Anthropic / Ollama) behind the AI Gateway via a provider abstraction

## Context and Problem Statement

ADR 0002 introduces `mealie.services.ai_gateway` as the sole egress to LLM providers and consolidates the scattered OpenAI surface (the SDK call site at `mealie/services/openai/openai.py`, the parser at `mealie/services/parser_services/openai/parser.py`, and the OpenAI use sites in `mealie/services/recipe/recipe_service.py`, `mealie/services/scraper/scraper_strategies.py`, and `mealie/routes/admin/admin_debug.py`). Today the application is hard-wired to OpenAI: 14 `OPENAI_*` environment keys live in `mealie/core/settings/settings.py:391-443`, and the SDK import only exists at one site after 0002 lands but the call shape (`AsyncOpenAI`, `ChatCompletion`) is still OpenAI-specific. Self-hosters increasingly want to point Mealie at Ollama (local, privacy-preserving) or Anthropic (different cost/quality envelope), and that is question 1 of `/tmp/system-overview.md` §7. The LikeC4 model already anticipates this — `llmProvider` (a `system`, tagged `#ai`) is described as "External; OpenAI / Ollama / Anthropic" and the `mealie.api.aiClients` component is described as "Provider adapters (OpenAI, Anthropic, Ollama)" — but no code or settings shape yet supports a second provider, and renaming `OPENAI_*` to `LLM_*` would break every existing user's `.env`.

## Decision Drivers

* **No vendor lock-in to OpenAI.** A second-provider switch must not require a fork or a code change at every call site.
* **Self-hosted Ollama support.** Privacy-sensitive deployments need a fully local provider; the Gateway must accept a non-cloud endpoint without an API key.
* **Backwards-compatible settings migration.** Existing `OPENAI_*` env vars must keep working with no `.env` edit; the rename to `LLM_*` is additive.
* **Single egress invariant from ADR 0002 stays intact.** Adding providers must not reintroduce direct SDK imports outside `mealie.api.aiGateway` / `mealie.api.aiClients`.
* **Per-deployment configurability, not per-call.** Operators pick a provider once via env; feature code stays provider-agnostic.

## Considered Options

* Keep single-provider lock-in (status quo after 0002, OpenAI only)
* Strategy-pattern provider registry inside the Gateway (pluggable `LLMClient` ABC, one impl per provider, selected at startup by `LLM_PROVIDER`)
* External LiteLLM proxy (Mealie keeps speaking the OpenAI dialect; LiteLLM translates to other providers)
* Per-call provider selection (each call site passes a `provider=` argument)

## Decision Outcome

Chosen option: "Strategy-pattern provider registry inside the Gateway", because it is the only option that satisfies all four primary drivers simultaneously. A small `LLMClient` ABC under `mealie.api.aiClients` lets us add Anthropic and Ollama without touching `mealie.api.aiGateway`'s public surface, the registry resolves the active provider once from settings (avoiding per-call branching), and Pydantic `validation_alias` on the renamed `LLM_*` settings keeps every `OPENAI_*` env var working unchanged. The other options each fail at least one driver — single-provider lock-in fails the no-vendor-lock-in driver outright; LiteLLM adds a separate process/network hop that self-hosters running Ollama on the same box do not want and shifts a security-critical egress out of the Mealie repo where ADR 0002's `import-linter` contract can no longer reach it; per-call provider selection scatters provider knowledge back across the service layer that 0002 just consolidated.

### Consequences

* Good, because the Gateway's public interface stays provider-agnostic — adding a third provider later is a new file in `mealie/services/ai_gateway/clients/`, not a cross-cutting change.
* Good, because legacy `OPENAI_*` env vars keep working via `validation_alias`, so existing users see no breakage on upgrade.
* Good, because the LikeC4 `llmProvider` external system already covers OpenAI / Ollama / Anthropic with a single `HTTPS` edge from `mealie.api.aiClients`, so the architecture model needs no change.
* Good, because import-linter contract 2 (the AI Gateway egress contract from ADR 0002) keeps its scope — provider SDKs (`anthropic`, `ollama`, `openai`) are all whitelisted only inside `mealie.api.aiClients`.
* Bad, because the Gateway's interface must reduce to a least-common-denominator capability set; provider-specific features (OpenAI structured outputs, Anthropic tool use, Ollama format hints) need explicit adapter logic or capability flags.
* Bad, because three SDKs in the dependency tree increase install size and supply-chain surface; we mitigate by making `anthropic` and `ollama` optional `pyproject.toml` extras.
* Neutral, because adding `LLM_*` aliases doubles the visible settings surface in docs until a future ADR deprecates the `OPENAI_*` names.

### Confirmation

Compliance is enforced by three mechanisms:

* **Contract test against a fake provider.** `tests/integration_tests/ai_gateway/test_provider_contract.py` exercises every Gateway method against an in-process fake `LLMClient` and asserts that no real SDK import is reached. The same test file parameterizes over each registered provider class to prove they all satisfy the ABC.
* **Settings-alias regression test.** `tests/unit_tests/test_config.py` adds a case that sets only `OPENAI_API_KEY` / `OPENAI_MODEL` (legacy form) and asserts the resulting `AppSettings` exposes the same values via the new `LLM_API_KEY` / `LLM_MODEL` attributes — and vice versa.
* **Import-linter contract from ADR 0002 stays green.** The existing `architecture.yml` workflow continues to forbid `openai` / `anthropic` / `ollama` imports outside `mealie.services.ai_gateway`. Adding Anthropic or Ollama means extending the contract's `ignore_imports` allowlist for the new client file, not relaxing the boundary.

## More Information

This ADR is a prerequisite consequence of ADR 0002 (introduce AI Gateway) and depends on it landing first. The `LLM_*` rename answers question 1 of `/tmp/system-overview.md` §7. LikeC4 elements affected: `mealie.api.aiGateway` (no diff — interface is provider-agnostic by construction), `mealie.api.aiClients` (gains Anthropic and Ollama adapter implementations; no model edit needed because the description already lists all three), `llmProvider` (no diff — already typed as "External; OpenAI / Ollama / Anthropic"). No new view or tag is required; the existing `aiSlice` view (`include element.tag == #ai`) renders the target shape unchanged. Revisit this ADR if a fourth provider category appears (e.g. AWS Bedrock as an aggregator) or if provider-specific capability divergence forces the Gateway interface to grow capability-detection methods.
