# Agent Notes — Mealie Architecture

The authoritative architecture model lives in [`mealie.c4`](./mealie.c4) (LikeC4 / Structurizr DSL). Architecture Decision Records live under [`decisions/`](./decisions/).

## LikeC4 MCP server

A LikeC4 MCP server is wired in the repo root `.mcp.json`. It exposes the model in this directory to AI agents so they can query elements, relationships, and views without re-parsing the DSL.

Example queries an agent can ask:

- "List every element tagged `#ai`."
- "Show all relationships into the `backend` container."
- "Which views include the `frontend` component?"

If the MCP server is not available, fall back to reading `mealie.c4` directly and treat it as the source of truth — rendered exports under `dist/` are derivative and may be stale.

## Conventions

- Edit `mealie.c4` as the single source of truth; regenerate exports, never hand-edit them.
- New significant decisions get an ADR under `decisions/` (MADR v4 format).
- Tag AI/LLM-touching elements with `#ai` so agents can scope queries.
