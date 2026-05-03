---
status: "accepted"
date: 2026-05-03
decision-makers: Mealie maintainers
consulted: contributors active on the architecture documentation initiative
informed: Mealie contributors at large
---

# Record architectural decisions

## Context and Problem Statement

The Mealie codebase has accumulated significant architectural choices — repository layering, async ORM adoption, group/household scoping, plugin and integration boundaries, frontend/backend split — but none of these are formally recorded. Future contributors (and returning maintainers) cannot reconstruct the *why* behind structural choices, which leads to either re-litigating settled questions or unintentionally undoing them. We need a lightweight, durable mechanism for capturing the rationale behind decisions that affect the structure of the system.

## Decision Drivers

* New contributors should be able to understand load-bearing structural choices without interviewing maintainers.
* The record must live next to the code so it is reviewed, versioned, and discoverable in the same workflow as source changes.
* The format must be stable and tool-agnostic so it survives churn in documentation tooling.
* Capturing a decision must be cheap enough that contributors actually do it during normal PR work.

## Considered Options

* (a) No formal records — keep relying on commit messages, PR descriptions, and tribal knowledge.
* (b) Free-form prose in `CONTRIBUTING.md` or a single architecture document.
* (c) MADR v4 Architectural Decision Records in `docs/decisions/`.

## Decision Outcome

Chosen option: "(c) MADR v4 ADRs in `docs/decisions/`", because it is the only option that produces immutable, individually-addressable records of *why* a structural choice was made, while remaining cheap to author and reviewable as part of normal PR flow. MADR v4 is a current, well-specified template with broad tooling support, which removes bikeshedding over format.

### Consequences

* Good, because every meaningful structural change leaves behind a durable, searchable rationale that survives author turnover.
* Good, because ADRs are versioned alongside the code they describe, so the history of a subsystem can be reconstructed from `git log` plus `docs/decisions/`.
* Good, because the MADR v4 template forces explicit articulation of alternatives and confirmation, which surfaces hidden assumptions during review.
* Bad, because authoring an ADR adds friction to PRs that change architecture, and contributors may resist the overhead.
* Bad, because poorly-written ADRs (missing alternatives, vague confirmation) can give a false sense of documentation while adding noise.

### Confirmation

Compliance is confirmed by two mechanisms:

1. **Review gate** — reviewers reject any PR introducing an architectural change (new top-level module, new external dependency category, new persistence pattern, new cross-cutting boundary, change to deployment topology) without an accompanying ADR in `docs/decisions/`.
2. **CI lint** — a CI check over `docs/decisions/*.md` enforces the canonical MADR v4 headings (`## Context and Problem Statement`, `## Considered Options`, `## Decision Outcome`) and required frontmatter fields (`status`, `date`, `decision-makers`). Files missing these fail the build.

## More Information

* Template and spec: https://adr.github.io/madr/ (MADR v4.0.0, 2024-09-17).
* Index of accepted ADRs: [`docs/decisions/README.md`](README.md).
* Authoring is supported by the `document-decision` skill bundled with this repo.
