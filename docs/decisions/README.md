# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) for Mealie.

An ADR captures a single significant architectural choice — the context that
forced the choice, the alternatives considered, the option selected, and the
mechanism by which compliance will be confirmed. ADRs are immutable once
accepted: superseding decisions get a new ADR that references the old one.

The format is **canonical [MADR v4](https://adr.github.io/madr/)**. Use the
`document-decision` skill to scaffold new entries, or copy the structure of
[ADR-0000](0000-record-architecture-decisions.md).

## When to write an ADR

Write an ADR for changes that affect the **structure** of the system, such as:

- Introducing or replacing a framework, ORM, or persistence layer.
- Adding a new top-level module or cross-cutting boundary.
- Changing deployment topology or runtime model.
- Adopting (or dropping) a pattern that other code is expected to follow.
- Reversing or narrowing a previously-accepted ADR.

Routine bug fixes, refactors that preserve structure, and feature work that
fits within existing boundaries do **not** need an ADR.

## Index

| Number | Title                                                                           | Status   |
| ------ | ------------------------------------------------------------------------------- | -------- |
| 0000   | [Record architectural decisions](0000-record-architecture-decisions.md)         | accepted |
| 0001   | [Enforce a layered architecture and extract the scheduler→routes helper](0001-enforce-layered-architecture.md) | accepted |
