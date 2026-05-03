---
name: document-decision
description: >
  Create an Architecture Decision Record (ADR) in canonical MADR v4 format capturing
  the why behind a significant technical choice. Use when user says 'document this
  decision', 'create an ADR', 'record architecture decision', 'why did we choose X',
  'document the rationale', or when adding major dependencies, new frameworks, or
  changing fundamental patterns. Do NOT use for user-facing feature docs (use
  document-feature) or syncing existing docs (use update-doc).
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Document a decision — write an ADR

Create an ADR so future readers (including future you) understand why a technical choice was made. An ADR is immutable once accepted — it records the decision and its context at the moment of decision. New information gets a new ADR that references (and possibly supersedes) the old one.

This skill produces **canonical MADR v4** (Markdown Architectural Decision Records, version 4.0.0, released 2024-09-17 — the current standard). Spec: https://adr.github.io/madr/ — template source: https://github.com/adr/madr/blob/develop/template/adr-template.md.

## Before You Start

- The project's existing ADR directory — common locations: `docs/adr/`, `docs/decisions/`, `docs/arc42/decisions/`, `architecture/decisions/`, or `adr/`. Find it with `find . -type d -name 'adr*' -o -name 'decisions'`.
- Any template file in that directory — often `template.md` or `0000-template.md`. **If a project template exists, follow it instead of the canonical MADR template** — projects sometimes pin a specific subset of optional sections.
- Existing ADRs — browse 2–3 well-written ones to match the project's voice and depth.

If the project has no ADR directory yet, ask the user where ADRs should live before creating the first one.

## Step 1: analyze the change

```bash
git diff main...HEAD
git diff --stat main...HEAD
```

Identify:

- What was chosen?
- What were the alternatives considered?
- What forces (constraints, quality attributes, risks) pulled toward each alternative?
- What will change now, and what could change later as a result?
- **How will compliance be confirmed?** (MADR v4 elevated this — see `### Confirmation` in Step 4.)

If you're writing the ADR before the code change, do the same analysis against the planned approach.

## Step 2: check for existing ADRs on the topic

```bash
# Find ADRs covering adjacent ground
grep -rli "{topic-keyword}" <adr-dir>/ 2>/dev/null
```

If one exists:

- **Covers the same ground** — update it rather than creating a duplicate.
- **Covers related but different ground** — reference it in the new ADR's **Context and Problem Statement**.
- **Contradicts this decision** — mark the old one's frontmatter as `status: "superseded by ADR-NNNN"` and reference it in your new **Context and Problem Statement**.

## Step 3: name the file

Two common conventions:

- **Numbered:** `NNNN-short-slug.md` (e.g., `0042-adopt-postgres-rls.md`). Number is monotonic; pad to 4 digits. This is MADR's default.
- **Dated:** `YYYY_MM_DD_short_slug.md` (e.g., `2026_04_20_adopt_postgres_rls.md`).

Follow whatever the project already uses. Look at the filenames of existing ADRs to copy the pattern.

## Step 4: write the ADR (canonical MADR v4)

Use the template below verbatim. Drop optional sections (marked with the HTML comment `<!-- This is an optional element. Feel free to remove. -->`) only when they genuinely add no value — `### Confirmation` in particular should almost always be kept (the MADR spec itself notes "although we classify this element as optional, it is included in many ADRs").

```markdown
---
status: "{proposed | rejected | accepted | deprecated | superseded by ADR-0123}"
date: {YYYY-MM-DD}
decision-makers: {list everyone involved in the decision}
consulted: {subject-matter experts with two-way communication}
informed: {kept up-to-date with one-way communication}
---

# {short title, representative of solved problem and found solution}

## Context and Problem Statement

{Describe the context and problem in two to three sentences, or as an illustrative
story. You may articulate the problem as a question. Make the scope explicit by
naming the structural architecture elements affected (components, connectors,
modules). Link to issues, collaboration boards, prior ADRs.}

<!-- This is an optional element. Feel free to remove. -->
## Decision Drivers

* {decision driver 1 — a desired quality, faced concern, constraint, or force}
* {decision driver 2}
* …

## Considered Options

* {title of option 1}
* {title of option 2}
* {title of option 3}
* …

## Decision Outcome

Chosen option: "{title of option 1}", because {justification — e.g., only option
that meets a k.o. criterion, resolves a specific force, comes out best in the
pros/cons analysis below}.

<!-- This is an optional element. Feel free to remove. -->
### Consequences

* Good, because {positive consequence — improvement of one or more desired qualities}
* Bad, because {negative consequence — compromising one or more desired qualities}
* …

<!-- Strongly recommended even though MADR marks it optional. -->
### Confirmation

{How will compliance with this ADR be confirmed? Is there an automated or manual
fitness function? E.g., a code review, a test with ArchUnit, a CI check, a
periodic audit. Name the mechanism and where it lives.}

<!-- This is an optional element. Feel free to remove. -->
## Pros and Cons of the Options

### {title of option 1}

{example | description | pointer to more information}

* Good, because {argument a}
* Good, because {argument b}
* Neutral, because {argument c}
* Bad, because {argument d}

### {title of option 2}

* Good, because {argument a}
* Neutral, because {argument b}
* Bad, because {argument c}

<!-- This is an optional element. Feel free to remove. -->
## More Information

{Additional evidence/confidence for the outcome; team agreement; when/how the
decision should be realised; if/when it should be revisited; links to related
decisions and resources.}
```

### Writing discipline

- **Heading names are exact.** `Context and Problem Statement`, `Decision Drivers`, `Considered Options`, `Decision Outcome`, `Consequences`, `Confirmation`, `Pros and Cons of the Options`, `More Information`. MADR-aware tooling parses on these names.
- **Heading levels are exact.** `Consequences` and `Confirmation` are `###` under `## Decision Outcome`, not top-level.
- **Frontmatter field names are exact.** `decision-makers` (hyphenated, plural), not `deciders`. `status` value is a quoted string when it contains spaces (e.g., `status: "superseded by ADR-0123"`).
- **Bullet voice is "Good, because …" / "Bad, because …" / "Neutral, because …".** Not "Pros:" / "Cons:".
- **Context is specific.** "We need to scale" → "Request latency at the 95th percentile has exceeded 500ms as traffic doubled; adding more replicas of the current stack costs $X/month."
- **Drivers are verifiable.** "Ease of use" is not a driver — "junior engineers onboard in under a week" is.
- **Decision names the trade-off.** If there's no trade-off, the decision isn't worth an ADR.
- **Confirmation is concrete.** Name the test file, the CI job, the review gate. "We will review this" is not confirmation.

## Step 5: update the ADR index

Most ADR directories have an `index.md` or `README.md` listing every ADR. Add an entry:

```markdown
| {Number/Date} | [{Title}]({filename}) | {Status} |
```

## Verify

```bash
# The file exists where expected
ls <adr-dir>/{NNNN-slug.md OR YYYY_MM_DD_slug.md}

# Required MADR v4 sections are present (Context, Considered Options, Decision Outcome)
grep -E '^## (Context and Problem Statement|Considered Options|Decision Outcome)$' <adr-dir>/<filename> | wc -l
# Expected: 3

# Confirmation sub-section is present (strongly recommended)
grep -q '^### Confirmation$' <adr-dir>/<filename> && echo "OK" || echo "MISSING — add unless intentionally omitted"

# Frontmatter uses canonical field names
head -10 <adr-dir>/<filename> | grep -E '^(status|date|decision-makers|consulted|informed):'

# The index references it
grep -q "{slug}" <adr-dir>/README.md <adr-dir>/index.md 2>/dev/null
```

## Common Mistakes

| Mistake | Correction |
|---|---|
| Using `Context` instead of `Context and Problem Statement` | Heading name is exact in MADR v4. |
| Using `Decision` instead of `Decision Outcome` | Same. |
| Promoting `Consequences` and `Confirmation` to `##` level | They are `###` sub-elements of `## Decision Outcome`. |
| Frontmatter field `deciders` | Renamed to `decision-makers` in MADR v4. |
| Listing pros/cons as `Pros:` / `Cons:` | Use `* Good, because …` / `* Bad, because …` / `* Neutral, because …` bullets. |
| Omitting `### Confirmation` | MADR v4 elevated this; almost every meaningful ADR has a confirmation mechanism. State it. |
| Writing an ADR for a decision with no real trade-off | Skip it. ADRs document choices with alternatives. |
| `Context and Problem Statement` that restates the decision | Context is the situation. If context and decision sound the same, the context isn't concrete enough. |
| Consequences listed only as `Good, because …` | Every decision has trade-offs. If you can't name a `Bad, because …`, you haven't thought hard enough. |
| Duplicating an existing ADR because you didn't search | Step 2 is mandatory. Duplicate ADRs fragment institutional memory. |
