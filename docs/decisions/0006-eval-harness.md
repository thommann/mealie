---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Adopt Promptfoo as the eval harness gating AI Gateway prompt outputs in CI

## Context and Problem Statement

Once the AI Gateway (LikeC4 element `mealie.api.aiGateway`, target shape introduced by ADR 0002 and externalised into YAML prompt assets by ADR 0004) becomes the sole egress to `llmProvider` via `mealie.api.aiClients`, every recipe-scrape JSON, ingredient-parser response, and image alt-text generation flowing back through `mealie.api.services` to `mealie.api.routes` will be shaped by a prompt asset under version control. Today there is no mechanism to detect when an edit to a prompt YAML, a model swap (`OPENAI_MODEL` / future `LLM_MODEL`), or a provider switch silently changes the structured-output shape or quality — the only signal is downstream parsing errors or user reports. We need a fitness function that catches Gateway-output regressions on the PR that introduces them, scoped narrowly enough that it stays under PR-CI budget. The scope is **only** the Gateway's outputs (the `mealie.api.aiGateway → mealie.api.aiClients → llmProvider` slice); this ADR explicitly does not propose a general LLM regression suite covering, e.g., scheduler tasks or future agentic flows.

## Decision Drivers

* **Catch silent regressions on PRs that touch `mealie/services/ai_gateway/**` or its prompt assets** — a missing field or shape change in structured output must fail CI rather than reach users.
* **Stay under a PR-CI time budget of ~3 minutes** — the existing `architecture.yml` workflow runs in seconds; a multi-minute eval gate is acceptable, a multi-hour one is not.
* **Reuse the YAML prompt asset format from ADR 0004** — config duplication between prompts and eval cases would rot.
* **Deterministic-enough scoring** — model nondeterminism must not produce flaky CI; prefer schema-level and exact-match assertions, treat semantic-similarity scores as advisory.
* **Provider-agnostic** — must run against any provider the Gateway supports (OpenAI today; Anthropic / Ollama once ADR 0003 lands), not pin the harness to one SDK.
* **Low onboarding cost** — contributors editing a prompt asset must be able to add an eval case without learning a new framework.

## Considered Options

* No eval harness — rely on downstream unit tests and user reports
* Hand-rolled golden-output unit tests under `tests/unit_tests/services/ai_gateway/`
* Promptfoo with YAML configs colocated with the prompt assets (recommended)
* DeepEval, pytest-native with LLM-as-judge metrics
* Custom rolled harness inside `mealie/services/ai_gateway/eval/`

## Decision Outcome

Chosen option: "Promptfoo with YAML configs colocated with the prompt assets", because it is the only option that simultaneously matches ADR 0004's YAML-first prompt asset format (eval cases live next to the prompt they exercise), is provider-agnostic out of the box (OpenAI / Anthropic / Ollama / generic HTTP), supports the deterministic assertion types we actually need (`is-json`, `contains-json`, JSON-schema, exact match, regex) without requiring an LLM judge in the default path, and runs as a single CLI invocation that fits cleanly into a GitHub Actions job. DeepEval is the closest runner-up but its pytest-native, Python-class-based test definitions are a worse match for prompt-author ergonomics and lean harder on LLM-as-judge metrics, which we want to keep optional rather than central. A custom harness was rejected as undifferentiated work.

### Consequences

* Good, because every prompt asset under `mealie/services/ai_gateway/prompts/` gets a sibling `*.eval.yaml` describing fixtures and assertions — the gate is colocated with what it gates.
* Good, because adding a new prompt requires adding eval cases in the same PR — the convention is enforced by a directory-level lint, not human discipline.
* Good, because Promptfoo's caching and provider abstraction let local runs hit Ollama while CI hits a recorded-cassette or low-cost provider, keeping the gate cheap.
* Good, because schema-level assertions reuse the Pydantic structured-output schemas already defined under `mealie.schema.openai.*` (and successors after ADR 0002).
* Bad, because Promptfoo is a Node/TypeScript tool — Mealie's backend is Python, so we add a second runtime to the architecture-CI surface (the `frontend/` already requires Node, so the cost is incremental, not new).
* Bad, because deterministic assertions cover shape but not quality; prompt edits that produce technically-valid but worse outputs will pass the gate. We accept this — quality is observed downstream, the gate's job is to catch shape regressions.
* Neutral, because eval fixtures (sample recipe HTML, sample ingredient strings) become part of the repo and must be reviewed for PII (see ADR 0005 for the policy).

### Confirmation

A new GitHub Actions job `ai-gateway-eval` is added to `.github/workflows/architecture.yml`, gated on PRs that touch any of:

* `mealie/services/ai_gateway/**`
* `mealie/schema/openai/**` (and its successor after ADR 0002)
* `.github/workflows/architecture.yml` (self-test)

The job runs `npx promptfoo@<pinned> eval --config mealie/services/ai_gateway/prompts/eval.config.yaml` against a recorded-cassette provider for hermetic execution. Failure threshold: any assertion failure fails the job. The threshold and the cassette-recording procedure are documented in `mealie/services/ai_gateway/prompts/README.md` (created with the Gateway in ADR 0002). A scheduled live-provider run (weekly, against the production-equivalent provider) catches drift introduced by upstream model updates; failures on that run open a tracking issue rather than blocking PRs.

## Pros and Cons of the Options

### No eval harness

* Good, because zero CI-time cost.
* Bad, because every Gateway output regression reaches users before being noticed.
* Bad, because the AI Gateway's whole reason to exist (a single, reviewable contract) loses its enforcement story.

### Hand-rolled golden-output unit tests

* Good, because uses the existing pytest harness — no new tooling.
* Bad, because golden-output equality breaks under any benign nondeterminism (token order, whitespace, optional fields), producing flaky tests.
* Bad, because no built-in support for provider abstraction; switching providers requires rewriting every test.

### Promptfoo (chosen)

* Good, because YAML-first configuration matches ADR 0004's prompt asset format.
* Good, because first-class support for `is-json`, JSON-schema, regex, semantic-similarity, and LLM-as-judge assertions in the same config.
* Good, because provider abstraction covers OpenAI, Anthropic, Ollama, and generic HTTP — aligns with ADR 0003's multi-provider direction.
* Bad, because Node tool in a Python-primary repo (mitigated: frontend already requires Node).

### DeepEval

* Good, because pytest-native — Python developers can read and extend it without learning new tooling.
* Good, because rich metric library (faithfulness, answer relevancy, hallucination).
* Neutral, because eval definitions are Python classes — more flexible but harder to colocate with YAML prompt assets.
* Bad, because metric library leans on LLM-as-judge by default, which is the flakiest assertion class for PR CI.

### Custom rolled harness

* Good, because total control over assertion semantics and CI integration.
* Bad, because every harness feature (caching, provider abstraction, parallel execution, reporters) is undifferentiated work.
* Bad, because future contributors learn a project-local DSL with no transferable knowledge.

## More Information

Upstream prerequisites: ADR 0002 (introduce `mealie.api.aiGateway`), ADR 0004 (YAML prompt asset format). This ADR consumes both — Gateway-shaped outputs and YAML-shaped prompts are what make a colocated eval config tractable. ADR 0005 (PII redaction) governs what eval fixtures may contain. Revisit when ADR 0003 lands a second provider, to confirm that Promptfoo's provider abstraction handles the new client without harness changes.
