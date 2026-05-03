---
name: system-overview
description: >
  Generate a SYSTEM_OVERVIEW.md that orients a senior engineer new to an unfamiliar
  codebase, with a Mermaid architecture diagram, a sequence diagram for data flow,
  and a legacy-pattern assessment. Use when user says 'give me a system overview',
  'onboard me on this repo', 'walk me into this legacy codebase', 'document the
  high-level architecture', or 'create a SYSTEM_OVERVIEW.md'. Do NOT use for code
  walkthroughs (use explain), persistent architecture chapters (use arc42), or ADRs
  (use document-decision).
allowed-tools: Read, Grep, Glob, Bash, Write
---

# System Overview — first-pass orientation for an unfamiliar codebase

Produces a single `SYSTEM_OVERVIEW.md` at the repo root. The audience is a senior engineer who has never seen the code. The output is a draft for human review, not a finished architecture document.

**Source.** Prompt structure adapted from Aaron Sumner, *"My go-to prompt for legacy code exploration,"* https://leftofthe.dev/2025/11/09/legacy-code-overview-llm (2025-11-09), which in turn borrows from Alex Chesser, *"Attention Is the New Big-O,"* https://alexchesser.medium.com/attention-is-the-new-big-o-9c68e1ae9b27 (2025-08-19).

## Before You Start

- Root `README.md` — the project's own framing. Match its vocabulary.
- Root `CLAUDE.md` (or `AGENTS.md`) — repo-specific guardrails the human authors put down.
- Top-level entry points — `main.py`, `app/`, `src/index.ts`, `cmd/`, `Dockerfile`, `docker-compose.yml`. Read them before claiming what the system *is*.

## Step 1: orient with the file tree

```bash
tree -L 2 -I 'node_modules|.git|.venv|__pycache__|dist|build'
find . -maxdepth 2 -name 'README*' -not -path '*/node_modules/*'
```

Identify: language(s), top-level directories, framework markers (`pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`, `pom.xml`).

## Step 2: locate the entry points and external boundaries

```bash
# HTTP / RPC entry points
grep -rln "FastAPI\|express()\|http.HandleFunc\|@RestController\|@SpringBootApplication" \
  --include='*.py' --include='*.ts' --include='*.js' --include='*.go' --include='*.java' .

# External integrations (DB, cache, queues, third-party APIs)
grep -rEn "psycopg|sqlalchemy|redis|kafka|amqp|boto3|requests\.|httpx\.|fetch\(" \
  --include='*.py' --include='*.ts' --include='*.js' . | head -30
```

Every external integration is a node in your container diagram.

## Step 3: write `SYSTEM_OVERVIEW.md` with the canonical structure

Use exactly the headings below. They come from the source prompt; preserve them so the output is recognisable across teams that adopt this skill.

```markdown
# System Overview

> Audience: a senior engineer new to this system. Drafted by an LLM, requires human review.

## CORE ANALYSIS (Required)

- Tools, frameworks, and design patterns used across the repository
- Data models and API design
- Mermaid architecture diagram of the system and its dependencies at a high level

## SYSTEM DESIGN (Required)

- File-by-file explanation of the central modules and how they link
- Mermaid sequence diagram for the primary data flow
- Mermaid flowcharts for any complex branching flows

## LEGACY ASSESSMENT (If applicable)

- Inconsistencies in architectural patterns
- Deviations from language or framework conventions
- Distinctions between old and new architectural approaches
```

### Optional extensions (lecture-specific, not in the source prompt)

If your project uses these conventions (the lecture/coursework variant adds them), append:

- **Cross-cutting concerns** — auth, logging, config, error handling — one paragraph each, with file references.
- **Technical-concern hotspots** — files or modules with high churn, high cyclomatic complexity, or long-standing TODOs.
- **Open questions for human architects** — the things you could not determine from the code alone. List them; do not guess.
- **Citations rule.** Every claim cites at least one `path/to/file.ext:line` reference.
- **UNVERIFIED tag.** Any inference not directly supported by a file you read is prefixed `UNVERIFIED:` so reviewers can triage.

## Step 4: anchor every claim to a file

Bad: "The system uses an event bus."
Good: "Events are published via `EventBus.publish` in `app/events/bus.py:42` and consumed by handlers registered in `app/events/registry.py:18-31`."

If you cannot cite a file, either find one or mark the sentence `UNVERIFIED:`.

## Step 5: render and sanity-check the Mermaid

```bash
# If mmdc is available
npx -y @mermaid-js/mermaid-cli -i SYSTEM_OVERVIEW.md -o /tmp/overview.svg
```

Or paste the diagram into https://mermaid.live to confirm it parses. A broken diagram is worse than no diagram.

## Verify

- `SYSTEM_OVERVIEW.md` exists at the repo root.
- All three required sections (`CORE ANALYSIS`, `SYSTEM DESIGN`, `LEGACY ASSESSMENT`) are present.
- At least one Mermaid block parses.
- Every assertion has a file reference, or is prefixed `UNVERIFIED:`.
- The first paragraph names the language, framework, and primary external dependencies.

## Common Mistakes

- **Claiming patterns from file names.** A file called `repository.py` may not implement the Repository pattern. Open it. If you cannot verify, write `UNVERIFIED:`.
- **A flat module list pretending to be an architecture.** Sequence and dependency *between* modules is the value; the list is not. Add at least one Mermaid diagram showing edges.
- **Skipping the `LEGACY ASSESSMENT` because the code "looks fine."** If you found zero inconsistencies in 30 minutes of reading, you read too quickly. Cite the conventions you checked against, even if the verdict is "consistent."
- **Embellishing past the source prompt without flagging it.** If you add the optional extensions (hotspots, open questions, UNVERIFIED rule), say so in the document header so reviewers know which sections are the canonical Sumner/Chesser shape and which are local additions.
