---
status: "accepted"
date: 2026-04-28
decision-makers: AI Gateway track lead (thomas.mannhart@bbv.ch)
consulted:
informed: Mealie contributor community
---

# Adopt LikeC4, MADR ADRs, and import-linter as the Architecture-as-Code stack for the AI Gateway track

## Context and Problem Statement

The AI Gateway track needs to consolidate Mealie's currently scattered OpenAI surface — `mealie/services/openai/`, the parser at `mealie/services/parser_services/openai/parser.py`, the `OpenAIRecipeService` in `mealie/services/recipe/recipe_service.py`, and fourteen `OPENAI_*` environment variables defined in `mealie/core/settings/settings.py` — into a single egress component with a stable, reviewable contract. Before any consolidation work begins, we need an architecture documentation approach that (a) lets AI coding agents and human reviewers query the intended structure, (b) lets CI mechanically reject changes that violate it, and (c) imposes minimal ceremony so that contributors actually keep it current. There is no existing architecture documentation in this repository, so this ADR also bootstraps the convention.

## Decision Drivers

* **Agent-queryability** — agents working in this repo must be able to read the architecture as text/code, not extract it from rendered diagrams.
* **CI-enforceable boundaries** — the AI Gateway must remain the only module that talks to the OpenAI SDK; this needs to be enforced automatically, not by review vigilance.
* **Low ceremony** — diagram and decision authoring must fit into a normal PR; tooling that requires a separate server or GUI gets abandoned.
* **Consolidation target is concrete** — the chosen stack must be able to express the current scattered OpenAI surface and the target single-egress shape in the same model so drift is visible.
* **Plain-text, diff-reviewable artifacts** — diagrams and decisions live in git alongside the code they describe.

## Considered Options

* Wiki pages (GitHub Wiki / Confluence)
* PlantUML diagrams checked into `docs/`
* Structurizr DSL with Structurizr Lite as the renderer
* LikeC4 + MADR ADRs + import-linter (chosen)

## Decision Outcome

Chosen option: "LikeC4 + MADR ADRs + import-linter", because it is the only option that satisfies all three primary drivers simultaneously: LikeC4 is a plain-text C4 DSL that agents and humans can read and grep, MADR gives decisions a parseable, immutable shape next to the code, and import-linter turns the boundaries declared in the C4 model into a CI gate at the Python import graph. The other options each fail at least one driver — wikis are not diff-reviewable, PlantUML expresses pictures rather than a queryable model, and Structurizr Lite requires running a separate server which raises ceremony.

### Consequences

* Good, because the architecture (LikeC4 source) and decisions (MADR files) live in the same repo as the code, so drift is visible in PR diffs.
* Good, because import-linter encodes the AI Gateway boundary as executable contracts — a stray `import openai` outside the gateway fails CI rather than slipping through review.
* Good, because LikeC4's text DSL is directly readable by AI coding agents without OCR or diagram parsing.
* Good, because MADR v4 is a small, well-known standard; new contributors do not need to learn a bespoke decision format.
* Bad, because contributors must learn LikeC4 syntax and the import-linter contract format before changing module boundaries.
* Bad, because three tools (LikeC4, MADR conventions, import-linter) must be kept in sync; a boundary change requires updating the C4 model, an ADR, and the import-linter contracts together.
* Neutral, because rendered C4 exports (SVG/PNG) are committed for review convenience but are not the source of truth — the `.c4` file is.

### Confirmation

Compliance is enforced by `.github/workflows/architecture.yml` (introduced in Step 9 of the AI Gateway track bootstrap). The workflow runs two jobs that must pass for any PR touching the AI-Gateway track:

* `import-linter` — validates the Python import graph against the contracts in `pyproject.toml` (`[tool.importlinter]`), in particular that only the AI Gateway module imports the OpenAI SDK.
* `likec4` — validates that `docs/architecture/*.c4` parses and that the model is internally consistent.

A PR that adds a new dependency on the OpenAI SDK from outside the gateway, or that lets the LikeC4 model drift out of parse-validity, fails CI and cannot merge.

## Pros and Cons of the Options

### Wiki pages

* Good, because zero tooling overhead — anyone can edit.
* Bad, because content lives outside git, so it is invisible to PR review and to AI agents working in the repo.
* Bad, because there is no machine-checkable link from a wiki page to the code it describes; drift is undetectable.
* Bad, because no path to CI enforcement.

### PlantUML in `docs/`

* Good, because plain-text source lives in git.
* Good, because broad tooling support and familiar to many contributors.
* Neutral, because rendering requires a Java runtime or a hosted server.
* Bad, because PlantUML expresses pictures, not a queryable model — there is no notion of a "component" or "container" that tooling can validate against the code.
* Bad, because no native path to import-graph enforcement.

### Structurizr DSL + Structurizr Lite

* Good, because Structurizr DSL is a true C4 model (not just a diagram), so structure is queryable.
* Good, because mature, well-documented, and the canonical C4 tooling.
* Neutral, because the DSL is a separate language to learn.
* Bad, because Structurizr Lite requires running a Java server to view diagrams locally, which raises ceremony for casual contributors.
* Bad, because there is no first-class Python import-graph enforcement story; we would still need import-linter as a second tool, with no shared model.

### LikeC4 + MADR + import-linter (chosen)

* Good, because LikeC4 is a text-first C4 DSL with a CLI renderer — no server required.
* Good, because MADR v4 is the current ADR standard and parses cleanly with frontmatter; tooling and humans both read it.
* Good, because import-linter contracts express the same boundaries the C4 model declares, so the model and the code are mechanically linked.
* Good, because all three tools run in plain CI (the `architecture.yml` workflow) with no external services.
* Bad, because LikeC4 is younger than Structurizr; the format may evolve and require migration.
* Bad, because boundary changes require coordinated updates across three artefacts (C4 source, ADR, import-linter contract).

## More Information

This ADR establishes the convention for the AI Gateway track and, by extension, for any future architecture documentation in this repository. ADR `0002` onward will document the concrete consolidation decisions (single egress module, env-var rationalisation, etc.) and will be authored using the same `/document-decision` workflow so that format and depth stay consistent. Revisit this ADR if LikeC4 development stalls or if Mealie upstream adopts a different architecture-as-code stack project-wide.
