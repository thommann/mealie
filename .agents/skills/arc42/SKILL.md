---
name: arc42
description: >
  Write, edit, or review chapters of an arc42 architecture documentation. Use when user says
  'write arc42', 'update the architecture documentation', 'fill out chapter 5', 'arc42 chapter',
  'architecture docs', or 'document our building blocks'. Do NOT use for ADRs (use
  document-decision — ADRs belong inside arc42 chapter 9) or user-facing feature docs
  (use document-feature).
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# arc42 — write or update architecture chapters

arc42 is a lightweight architecture documentation template with 12 chapters. Each chapter has a defined purpose; filling them in order produces a coherent architecture document a newcomer can read end-to-end.

## Before You Start

- The arc42 template (https://docs.arc42.org or a local copy under `docs/arc42/`).
- `docs/arc42/` or equivalent — the project's existing arc42 tree. Find with `find . -type d -name 'arc42*'`.
- Root `CLAUDE.md` Architecture section — often duplicates chapter 5 content; sync as you edit.

If the project has no arc42 tree yet, confirm with the user that arc42 is the right framework before creating one. Alternatives: C4 model, minimal `ARCHITECTURE.md`, or a single page in the docs site.

## The 12 chapters and what goes where

| # | Chapter | What belongs here | Quality criterion |
|---|---|---|---|
| 1 | Introduction and Goals | Top 3 business goals, top 3 quality attributes, key stakeholders | Any newcomer understands WHY this system exists in 5 minutes |
| 2 | Constraints | Technical, organizational, and regulatory constraints imposed from outside | Reader knows which rules are non-negotiable |
| 3 | Context and Scope | System boundary: users, external systems, their interactions | Clear line between "our system" and "not our system" |
| 4 | Solution Strategy | The 5–10 load-bearing architectural decisions, with 1-line rationale each | Reader grasps the shape without reading chapters 5–10 |
| 5 | Building Block View | Static structure: components and their relationships, at multiple zoom levels | A dev knows which component owns a given concern |
| 6 | Runtime View | Sequence diagrams for 3–5 important scenarios | Reader understands dynamic behavior for critical flows |
| 7 | Deployment View | Where the software runs, in what topology | On-call engineer knows what's where |
| 8 | Cross-cutting Concepts | Patterns applied across the system (auth, logging, error handling, i18n) | One place to learn "how we do X" |
| 9 | Architecture Decisions | ADRs — each an immutable record | Decisions are traceable with their context |
| 10 | Quality Requirements | Measurable quality attributes with scenarios | Quality goals are testable |
| 11 | Risks and Technical Debt | Known risks, debt items, mitigations | Team and sponsors see what's parked and why |
| 12 | Glossary | Terms with precise definitions | Ambiguous language has a single meaning |

## Step 1: find the project's arc42 tree

```bash
find . -type d -name 'arc42*' -not -path '*/node_modules/*'
# Common: docs/arc42/  OR  documentation/arc42/
```

Inside the tree, you usually find one file per chapter: `01-introduction.md` … `12-glossary.md`. Some projects use full chapter names in filenames.

## Step 2: pick the chapter

Ask: what is the user asking for, or what did this PR change?

- **Business-goal shift** → chapter 1.
- **New external dependency or boundary change** → chapter 3.
- **A load-bearing decision** → chapter 4 (summary) + chapter 9 (full ADR via `document-decision`).
- **New major component or refactored structure** → chapter 5.
- **New critical user flow** → chapter 6.
- **Infra change** → chapter 7.
- **New pattern applied codebase-wide** → chapter 8.
- **A decision recorded** → chapter 9.
- **Quality goal changed or measured** → chapter 10.
- **New risk discovered** → chapter 11.

## Step 3: write or edit

### Writing discipline per chapter

**Chapter 1** — avoid aspirational prose. "We want to be the best" is not a goal; "p99 latency under 500ms for tier-1 queries" is.

**Chapter 4** — 5–10 decisions, one line of rationale each. If you're writing paragraphs here, move them into ADRs (chapter 9) and summarize.

**Chapter 5** — use diagrams (Mermaid, PlantUML, SVG). Text alone loses the structure. Label every component and arrow.

**Chapter 6** — sequence diagrams. Three to five scenarios is enough; more dilutes. Pick scenarios that exercise chapter 5's interactions.

**Chapter 7** — include a real deployment diagram with the actual hosts/containers/services, not an idealized one.

**Chapter 8** — one subsection per concern: auth, logging, config, error handling, i18n, caching. Name files if a concern has a canonical implementation (`src/lib/errors/index.ts`).

**Chapter 9** — one file per ADR, linked from the chapter index. Use `document-decision` for the ADR body.

**Chapter 10** — quality scenarios in the form "when X happens, system responds with Y within Z." Non-testable quality goals are wishes.

**Chapter 11** — risks have likelihood + impact + mitigation. "Might become slow" is not a risk — "if monthly active users exceed 100k, database writes will bottleneck; mitigation: shard user table" is.

**Chapter 12** — one line per term, ordered alphabetically.

### General editing discipline

- **Link between chapters.** Chapter 5 references chapter 4's decisions. Chapter 6 references chapter 5's components. Chapter 11 references the chapters whose risks it tracks.
- **Keep each chapter self-contained at the top.** A reader jumping directly to chapter 7 should still orient themselves.
- **No orphan chapters.** If a chapter has < 30 lines and wouldn't grow, it's not worth its own file — fold it into an adjacent chapter.

## Step 4: keep CLAUDE.md in sync

The root `CLAUDE.md` "Architecture" section is a condensed summary of arc42 chapters 3–5. When you edit those chapters substantially, re-scan `CLAUDE.md` for drift:

```bash
bash validation/validate-claude-md.sh CLAUDE.md
```

## Verify

```bash
# The edited chapter has the right section structure
# (most chapters have sub-headings like ### Building blocks, ### Interfaces)
grep -c '^##\? ' docs/arc42/<chapter>.md
# Expected: several — chapter content has subsections.

# Links between chapters resolve
grep -oE '\[([^]]+)\]\(([^)]+\.md[^)]*)\)' docs/arc42/<chapter>.md | while read link; do
  # Relative path check
  target=$(echo "$link" | sed -E 's/.*\(([^)]+)\).*/\1/' | cut -d'#' -f1)
  [ -n "$target" ] && [ ! -f "docs/arc42/$target" ] && echo "BROKEN: $link"
done

# Docs site builds (project-specific command)
```

## Common Mistakes

| Mistake | Correction |
|---|---|
| Filling every chapter because the template has 12 | Chapters are optional if empty. Better to have 8 load-bearing chapters than 12 skeleton-filled ones. |
| Treating chapter 4 and chapter 9 as the same | Chapter 4 is a summary (5–10 one-liners). Chapter 9 is ADRs (full immutable records). Both exist. |
| Chapter 5 with no diagram | The static structure is a diagram first, prose second. Add one (Mermaid or PlantUML). |
| Quality goals as adjectives | "Fast" is not a quality goal. Write it as a scenario: "when user clicks X, UI responds within 100ms at p95". |
