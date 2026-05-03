## Architecture docs

- arc42 chapters live in `docs/arc42/`. Use the `arc42` skill for authoring rules.

## Architecture decisions

- All architectural decisions live in docs/decisions/. Read the latest 3–5 before proposing structural changes.

## Architecture model

- LikeC4 sources in `docs/architecture/*.c4`.
- Query via the `likec4` MCP server before proposing structural changes — do not re-derive from source.
- Use the `likec4-dsl` skill for authoring; structural code changes must update the matching `.c4` view in the same commit.
