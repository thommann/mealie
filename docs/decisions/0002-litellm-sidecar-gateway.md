---
status: "accepted"
date: 2026-05-03
decision-makers: Mealie maintainers
consulted: contributors active on the AI-assisted features
informed: Mealie contributors at large
---

# Route LLM traffic through a LiteLLM sidecar behind a thin in-process gateway

## Context and Problem Statement

Every domain caller imports the provider SDK directly (or through a thin
wrapper). Today `mealie.services.openai.openai` constructs `AsyncOpenAI`
and is the sole importer of the `openai` package, but feature code in
`mealie.services.recipe.recipe_service`, `mealie.services.parser_services.openai.parser`,
`mealie.services.scraper.scraper_strategies`, and `mealie.routes.admin.admin_debug`
all reach the provider through that single wrapper without any abstraction
above the SDK boundary (see `docs/architecture/llm.view.c4`). This couples
the codebase to one provider, makes fallback impossible without code
changes, and pushes rate-limit handling into every caller — `RateLimitError`
is caught and re-raised in two places in the wrapper, and again in scraper
strategies and recipe services. Provider routing, retries, and observability
have no single home.

## Decision Drivers

* **Provider portability** — swapping or A/B-testing OpenAI, Anthropic, a
  local Ollama instance, or Azure OpenAI must not require touching feature
  code.
* **Fallback policy** — when the primary provider is rate-limited or
  unavailable, requests should fail over to a secondary without a code
  deploy.
* **Rate-limit handling outside the application** — backoff, retries, and
  per-key budgets belong in infrastructure, not in `recipe_service` or
  `scraper_strategies`.
* **Consistent observability** — one place to capture latency, token
  counts, cost, and error rates across every LLM call site.

## Considered Options

* (a) Keep direct SDK calls — every feature continues to depend on the
  `openai` package through `mealie.services.openai`.
* (b) Write a custom in-process gateway — extend the existing wrapper into
  a fully-featured router with provider adapters, retry/fallback logic,
  and metrics, all in Python.
* (c) Run [LiteLLM](https://docs.litellm.ai/) as a sidecar exposing an
  OpenAI-compatible endpoint; callers use a thin in-process gateway
  (still `mealie.services.openai`, repointed) that talks to the sidecar
  via the `openai` SDK with `OPENAI_BASE_URL` set to the sidecar.

## Decision Outcome

Chosen option: "(c) LiteLLM sidecar with a thin in-process gateway",
because it is the only option that puts provider routing, fallback, and
rate-limit handling in a separately-deployable component while keeping
the application code as a single OpenAI-compatible client. Option (a)
fails every driver. Option (b) reinvents what LiteLLM already does
(provider adapters for 100+ models, fallback chains, budgets, callbacks)
and would entrench LLM-platform code inside an application whose
domain is recipes.

### Consequences

* Good, because one place — the sidecar's `config.yaml` — defines provider
  routing, retries, and fallbacks; application code is unaware which
  provider served a request.
* Good, because adding a new provider does not change application code:
  it is a sidecar configuration change.
* Good, because rate-limit and retry behaviour can be tuned without a
  Mealie release.
* Bad, because the dev and prod topology gain an extra container, which
  must be documented in the deployment guide and the Docker Compose
  examples.
* Neutral, because the gateway module becomes the single point of failure
  for LLM features; mitigate with a sidecar health check (`/health/readiness`)
  surfaced through the existing admin debug endpoint and a CI smoke test.

### Confirmation

Compliance is confirmed by two mechanisms:

1. **Static contract** — a `[tool.importlinter]` `forbidden` contract in
   `pyproject.toml` declaring that no module outside
   `mealie.services.openai` may import any provider SDK (`openai`,
   `anthropic`, `litellm`, `google.generativeai`, `cohere`). The
   contract is enforced by `lint-imports` in the same CI job that
   already runs ADR-0001's layering contract. Reintroducing a direct
   SDK import in a feature module fails CI.
2. **Smoke test** — a CI job posts to one LLM-backed route (the existing
   admin debug endpoint, `POST /api/admin/debug/openai`) against a
   LiteLLM sidecar configured with a stub provider, and asserts a 2xx.
   The job exercises the full path: route → in-process gateway →
   sidecar HTTP → stub provider response.

## More Information

* Baseline call-path view: [`docs/architecture/llm.view.c4`](../architecture/llm.view.c4)
  (every code path that currently reaches the provider SDK).
* Existing wrapper that becomes the in-process gateway:
  `mealie/services/openai/openai.py`.
* Settings consumed at gateway construction:
  `mealie/core/settings/settings.py:391-443` (`OPENAI_*`). After this
  ADR, `OPENAI_BASE_URL` points at the sidecar; provider keys move to
  the sidecar's environment.
* Layering contract this builds on: [ADR-0001](0001-enforce-layered-architecture.md).
