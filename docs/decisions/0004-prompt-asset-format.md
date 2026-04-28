---
status: "proposed"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Externalise LLM prompts as YAML assets under the AI Gateway

## Context and Problem Statement

The current LLM prompt surface lives as plain `.txt` files under `mealie/services/openai/prompts/` (six files: `general/transcribe-audio.txt`, `general/debug.txt`, `recipes/parse-recipe-video.txt`, `recipes/parse-recipe-ingredients.txt`, `recipes/scrape-recipe.txt`, `recipes/parse-recipe-image.txt`) loaded by name through `OpenAIService.get_response(prompt_name=..., ...)`. The prompt body is the *entire* file content; there is no place to pin a model, declare which response schema the prompt expects, version a prompt for A/B comparison, or attach metadata such as the locale or the originating ADR. Once `mealie.services.ai_gateway` (LikeC4 element id `mealie.api.aiGateway`, source `docs/architecture/mealie.c4:22`) becomes the sole egress to LLM providers (ADR 0002), it owns the prompt registry; this ADR fixes the on-disk format for those assets before the Gateway code lands. Operator override via `OPENAI_CUSTOM_PROMPT_DIR` (`mealie/core/settings/settings.py`) must keep working.

## Decision Drivers

* **Diff-reviewable without parsing Python** — prompt edits should land in PRs as text-only diffs that a non-Python reviewer can read.
* **Per-prompt model and response-schema pinning** — different prompts target different models (text vs. audio vs. vision) and different Pydantic response schemas; the asset must declare both so the Gateway does not need a Python dispatch table.
* **Versionable in place** — prompt experiments need a version field on the asset so two variants can coexist and the Gateway can route by id+version, without renaming files or losing history.
* **Agent-editable without touching service code** — a coding agent improving a prompt must not have to modify `mealie/services/ai_gateway/` Python to do so.
* **`OPENAI_CUSTOM_PROMPT_DIR` override stays simple** — operators currently drop replacement files into a directory; the new format must keep that single-directory-shadow model rather than introducing a registry service or DB table.

## Considered Options

* Keep Python-string prompts (status quo: `.txt` whose content is the prompt body)
* Jinja2 templates in `.j2` files with side-car JSON for metadata
* YAML with templated body (chosen)
* Markdown with YAML frontmatter
* External prompt-registry service (e.g. PromptLayer, Langfuse)

## Decision Outcome

Chosen option: "YAML with templated body", because it is the only option that satisfies all five drivers in one file: prompt body, model hint, response-schema reference, version, and locale live in the same YAML document, which diff-reviewers and agents both read natively, and `OPENAI_CUSTOM_PROMPT_DIR` continues to work as a single-directory shadow tree (`<dir>/recipes/parse-recipe-ingredients.yaml` overrides the bundled asset of the same id). Each asset has the shape:

```yaml
id: recipes.parse-recipe-ingredients
version: 1
model: ${OPENAI_MODEL}            # operator-overridable; defaults to settings
response_schema: mealie.schema.openai.OpenAIIngredients
locale: en
body: |
  Parse ingredient strings into components. ...
```

The Gateway loads every `*.yaml` under `mealie/services/ai_gateway/prompts/` (and the override directory) at startup, indexes by `(id, version)`, and exposes `gateway.get_prompt(id, version=None)`. Templated body interpolation is restricted to a small set of named placeholders supplied by the caller — no arbitrary Python expressions.

### Consequences

* Good, because every prompt is a single self-describing artefact: a reviewer reading `parse-recipe-ingredients.yaml` sees the model, the schema, the version, and the body without cross-referencing Python.
* Good, because `response_schema` lives next to the prompt, eliminating the current pattern where the caller (`mealie/services/openai/openai.py` consumers) has to know which schema goes with which prompt.
* Good, because adding a v2 of a prompt is `cp v1.yaml v2.yaml; bump version:` — no file renames, no service-code edits.
* Good, because operator override under `OPENAI_CUSTOM_PROMPT_DIR` keeps the same "drop a file with the matching path" UX users already know.
* Bad, because every existing `.txt` prompt has to be migrated to YAML in the same PR that introduces the loader; this is a one-time cost.
* Bad, because YAML's significant whitespace makes long multi-paragraph prompt bodies marginally more error-prone to edit than `.txt` (mitigated by `body: |` block-literal style and the loader test below).
* Neutral, because the YAML schema itself becomes a public contract — changing required fields means versioning the loader, not just the assets.

### Confirmation

Compliance is enforced by two CI hooks added in the same PR that introduces the loader:

* `tests/unit_tests/services/ai_gateway/test_prompt_assets.py` — round-trips every YAML asset through the loader, asserts that `id`, `version`, `model`, `response_schema`, and `body` parse, and that `response_schema` resolves to an importable `mealie.schema.openai.*` class.
* `task py:check` — adds a YAML schema-lint step (`check-jsonschema --schemafile mealie/services/ai_gateway/prompts/_schema.json mealie/services/ai_gateway/prompts/**/*.yaml`) wired into the existing pre-commit and `architecture.yml` workflow.

A prompt PR that ships malformed YAML, an unknown response schema, or a missing required field fails CI rather than reaching review.

## Pros and Cons of the Options

### Keep Python-string prompts (`.txt`)

* Good, because zero migration cost.
* Good, because operators already understand the `.txt` shadow model.
* Bad, because there is no place to pin model, schema, or version — every caller has to carry that knowledge in Python.
* Bad, because diffs are body-only; reviewers cannot tell from the file which model or schema a change targets.

### Jinja2 `.j2` + side-car JSON

* Good, because Jinja2 is a familiar template engine.
* Neutral, because templating power exceeds what the Gateway needs.
* Bad, because metadata in a side-car JSON splits a single concept across two files; renames must stay in lockstep.
* Bad, because Jinja2 is a runtime dependency we do not currently take, and its expression sandbox is broader than the named-placeholder set we want.

### Markdown with YAML frontmatter

* Good, because Markdown bodies render cleanly in GitHub.
* Neutral, because contributors already write Markdown.
* Bad, because Markdown headings and lists in the body collide with prompt content that often contains literal `#` and `-` characters; escaping rules become a footgun.
* Bad, because parsing Markdown frontmatter requires an extra dependency (`python-frontmatter`) for marginal benefit over plain YAML.

### External prompt-registry service

* Good, because version history, A/B testing, and analytics come for free.
* Bad, because Mealie is self-hosted; a mandatory external dependency is incompatible with the deployment model.
* Bad, because operator override semantics (`OPENAI_CUSTOM_PROMPT_DIR`) cannot map cleanly onto a remote registry without inventing a sync protocol.

## More Information

This ADR is the on-disk-format companion to ADR 0002 (introduce AI Gateway) and ADR 0003 (add second provider). It deliberately does not specify the Gateway's loader API — that lives with the Gateway implementation — only the asset format. ADR 0005 (PII redaction) governs which placeholders may be filled with recipe/household data; the body templating contract here intentionally stays narrow so 0005's policy is enforced at fill time, not at parse time. When `mealie.c4` grows, a `prompts` sub-component may be added under `mealie.api.aiGateway` to make the asset layer queryable in LikeC4; that diff is out of scope for this ADR.
