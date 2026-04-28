---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Enforce a hard PII denylist on every AI Gateway egress payload

## Context and Problem Statement

Today the only control on what Mealie sends to OpenAI is a single boolean — `OPENAI_SEND_DATABASE_DATA: bool = True` at `mealie/core/settings/settings.py:412`, documented as "Sending database data may increase accuracy in certain requests, but will incur additional API costs". Any caller of `mealie.services.openai.OpenAIService` (recipe scraping at `mealie/services/scraper/scraper_strategies.py:31`, ingredient parsing at `mealie/services/parser_services/openai/parser.py:14`, recipe creation in `mealie/services/recipe/recipe_service.py:35`, admin debug at `mealie/routes/admin/admin_debug.py:11`) hands raw payloads — including free-text recipe `notes`, household member identifiers, and authenticated user objects — to the SDK with no field-level filter. ADR 0002 consolidates these call sites behind `mealie.services.ai_gateway`; before that consolidation merges, this ADR fixes what may legitimately cross the egress boundary `mealie.api.aiClients -> llmProvider` (LikeC4: `docs/architecture/mealie.c4:44`).

## Decision Drivers

* **GDPR Article 5(1)(c) data-minimization** — only the data necessary for the prompt may leave the Mealie process; current behaviour exfiltrates user emails and free-text notes whenever the flag is `True`.
* **Self-hosted operator flexibility** — some operators run a local Ollama or vLLM endpoint and want full payloads. The control must not force a one-size policy, but must not allow operators (or future contributors) to disable the PII denylist.
* **Auditability** — operators must be able to prove what left their box; the redacted payload must be logged exactly as transmitted.
* **Contributor blast radius** — a junior contributor adding a new prompt asset must not be able to leak PII by widening a payload schema; the gate must live in Gateway code, not in each prompt.

## Considered Options

* Ship-everything (status quo when `OPENAI_SEND_DATABASE_DATA` is `True`)
* Hard denylist enforced inside the Gateway
* Structured allowlist per prompt asset
* External DLP proxy (e.g., Microsoft Presidio as a sidecar)

## Decision Outcome

Chosen option: "Hard denylist enforced inside the Gateway", because it is the only option that ships in the same PR as the Gateway extraction (ADR 0002), is mechanically testable against a fake provider, and protects users even if a future prompt asset accidentally widens its payload schema. The denylist runs inside `mealie.services.ai_gateway` immediately before any provider adapter under `mealie.services.ai_gateway.clients` (the LikeC4 `mealie.api.aiClients` component) is invoked, so every egress path on the `mealie.api.aiClients -> llmProvider` edge is covered uniformly.

The denylisted JSON paths — applied recursively to any payload tree — are: `*.email`, `*.full_name`, `*.username`, `users[*].*` (except `id`), `households[*].name`, `households[*].members[*]`, `*.notes`, `*.note`, `group_id`, `household_id`, `*.subject` (OIDC sub claim), and any field tagged `audit.ip` in the source schema. The list is the seed set; the implementing PR may extend it but never narrow it without a new ADR.

The existing `OPENAI_SEND_DATABASE_DATA` setting at `mealie/core/settings/settings.py:412` is renamed `AI_GATEWAY_SEND_DATABASE_DATA` with a Pydantic `validation_alias` keeping the old name working for at least two minor releases. The flag's semantics narrow: it now controls only the *augmentation* allowlist (foods, units, labels) the Gateway may attach to a prompt, and has **no effect** on the denylist — the denylist runs unconditionally.

A structured per-prompt allowlist (option 3) is the longer-term shape and lands separately in ADR 0004's prompt-asset format. This ADR explicitly does not block on it, because waiting would leave the current ship-everything behaviour live for another release cycle.

### Consequences

* Good, because the egress contract becomes mechanically reviewable: any new field accidentally pulled through the Gateway either appears in the denylist (stripped) or in the captured test payload (caught in CI).
* Good, because the rename `OPENAI_* -> AI_GATEWAY_*` aligns the setting surface with the new module boundary introduced in ADR 0002 without breaking existing `.env` files.
* Good, because operators retain control of *augmentation* via the renamed flag, satisfying the self-hosted-flexibility driver.
* Good, because audit logging becomes accurate: the logged payload equals the transmitted payload, byte-for-byte, because redaction happens before serialization.
* Bad, because the denylist is by-name — a future schema that renames `notes -> recipe_notes` silently bypasses the rule unless the contributor remembers to update the path list. Mitigated by the per-prompt allowlist landing in ADR 0004.
* Bad, because some prompt accuracy may regress on the recipe-parse path that previously consumed free-text `notes`; the prompt-asset PR (ADR 0004) will need to declare any legitimate use of that field explicitly and accept the policy review.
* Neutral, because the renamed setting requires one entry in the deprecation notes; the alias keeps deployments working without intervention.

### Confirmation

Compliance is confirmed by `tests/integration_tests/ai_gateway/test_egress_redaction.py` (added by the implementing PR). The test registers a fake provider implementing the `mealie.services.ai_gateway.clients` interface that captures every outbound payload tree, then exercises the recipe-parse and ingredient-parse paths end-to-end against it. The test asserts, for every captured tree, that none of the denylisted JSON paths resolve to a non-null value, and runs the matrix `AI_GATEWAY_SEND_DATABASE_DATA={true,false}` and (via alias) `OPENAI_SEND_DATABASE_DATA={true,false}` to prove the flag does not influence the denylist. The test is added to the required matrix of `.github/workflows/architecture.yml` — the same workflow that gates the import-linter contracts — so a Gateway change that loosens redaction fails CI rather than slipping through review. Manual confirmation: changes that touch the denylist itself require a new ADR, enforced by a `CODEOWNERS` rule on `mealie/services/ai_gateway/redaction.py`.

## More Information

This decision is a sibling of ADR 0002 (introduces `mealie.services.ai_gateway` and removes the grandfather line `mealie.services.openai.openai -> openai` from import-linter contract 2) and a precursor to ADR 0004 (prompt-asset YAML format, which will host the per-prompt allowlist that supersedes the denylist's coverage of payload widening). The denylist is intentionally pessimistic at introduction — narrowing it in the future requires a new ADR and a corresponding test update; widening it is a normal PR.

Open question deferred to the implementing PR: whether to keep `OPENAI_SEND_DATABASE_DATA` working past the second deprecation window or hard-remove it once `AI_GATEWAY_*` is the documented name. The Pydantic `validation_alias` lets us defer that call without changing this ADR.
