# Open Questions — Architecture Walkthrough

> Output of Step 3d (three-perspective walkthrough). Each item is a place where the
> three artifacts (LikeC4 model in `docs/architecture/`, arc42 chapters in `docs/arc42/`,
> `SYSTEM_OVERVIEW.md`) disagree about the system. These feed Step 4 (ADR-0001).
>
> Walkthrough date: 2026-05-03. Conducted against `docs/architecture/{spec,model,views}.c4`,
> `docs/architecture/grimp.dot`, `docs/arc42/{01,03,05}-*.md`, and `SYSTEM_OVERVIEW.md`.
> The LikeC4 dev server (`npx likec4 serve`) was not used as the LikeC4 MCP could not
> resolve the project (workspace path expanded literally as `${workspaceFolder}`); the
> walkthrough was driven from source files instead. **This is itself an open question
> (Q9 below).**

## Outside-in (SystemContext + Container)

**Anchor.** `views.c4` (`system_context`, `containers`); `model.c4` lines 4–15, 465–496;
`docs/arc42/03-context-and-scope.md`; `SYSTEM_OVERVIEW.md` architecture diagram.

### Q1. The system boundary disagrees on what is "inside" Mealie

`model.c4` declares **six containers** inside `mealie`: `frontend`, `backend`,
`database`, `alembic`, `nltkData`, `scheduler` (lines 17, 21, 467, 471, 473, 475).
`docs/arc42/03` puts `database` inside the Mealie boundary but treats LDAP / OIDC /
SMTP / Apprise / webhooks as external; it does *not* surface `alembic`, `nltkData`,
or a separate `scheduler` container at all. `SYSTEM_OVERVIEW.md` shows the database
as the terminus of `ORM --> DB`, treats Alembic as a startup *task* inside
`mealie.db`, and does not draw NLTK data or a scheduler container at all.

Three views, three different container sets. **Decide:** is "Mealie" the deployed
process (`frontend` + `backend` only, with DB / Alembic / NLTK as adjacent technical
choices) or the deployment unit (everything that ships in the Docker image)? ADR-0001.

### Q2. `scheduler` is modelled as a container but described as in-process

`model.c4:475-476` has `scheduler = container 'In-process scheduler'` with edges
`backend -> scheduler 'Hosts'` and `scheduler -> backend 'Invokes scheduled tasks'`.
`SYSTEM_OVERVIEW.md` LEGACY ASSESSMENT explicitly flags the scheduler as
**in-process inside the same uvicorn worker** (`mealie/app.py:131-148`). arc42/05
correctly lists the scheduler as part of `mealie.services` (a building block
*inside* the backend), not a peer container.

C4 conventions say a container is a separately deployable / runnable unit. An
asyncio scheduler running on the FastAPI event loop is not. Either demote the
LikeC4 element from `container` to `component` of `backend`, or rename it to
something that doesn't promise process isolation.

### Q3. `frontend -> backend` direction omits the production reverse edge

`model.c4:490` has the single edge `mealie.frontend -> mealie.backend`. In
production (`PRODUCTION=true`), `mealie/app.py:179-180` mounts the SPA's static
bundle into the FastAPI app — i.e. the backend *serves* the frontend's HTML/JS.
`SYSTEM_OVERVIEW.md` captures this with a dashed `Browser -. served when
PRODUCTION .-> SPA` edge. arc42/03 also shows this in prose
("`mealie/app.py:179-180`"). The LikeC4 container view collapses dev (separate
Nuxt server) and prod (bundled) into one wrong-shaped relationship.

### Q4. Actors disagree

`model.c4:5` declares one actor — `user`. `docs/arc42/03-context-and-scope.md`
distinguishes **Self-hosting end user** (uses the SPA) and **Integrator**
(API client with long-lived token). arc42/01 §1.3 lists three stakeholder
roles, including Integrators. The LikeC4 model has no Integrator actor and no
edge from anything to `mealie.backend` representing direct API access from
non-browser clients other than `user -> mealie.backend 'Direct API access'`
(model.c4:480), which conflates the two.

## Building blocks (arc42/05 + Component view + grimp.dot)

**Anchor.** `views.c4` (`components_backend`, `code_*`); `model.c4:498-1856`;
`docs/architecture/grimp.dot`; `docs/arc42/05-building-block-view.md`.

### Q5. arc42/05 lists ten building blocks; the LikeC4 model declares twelve

arc42/05 §5.2 prose covers: `app/main`, `routes`, `services`, `repos`, `db`,
`schema`, `core`, `middleware`, `lang`, `pkgs` — ten blocks (counting
`app`+`main` as one). `model.c4` declares **twelve components** under
`mealie.backend`: `app`, `assets`, `core`, `db`, `lang`, `main`, `middleware`,
`pkgs`, `repos`, `routes`, `schema`, `services` — i.e. it splits `app`/`main`
and adds `assets` (which is a Jinja templates / static-bundle namespace, not
mentioned anywhere in arc42/05 or `SYSTEM_OVERVIEW.md`). Either `assets` and
the `app`/`main` split deserve prose, or they should be folded.

### Q6. No explicit component-level edges; component view is fully inferred

`grep -cE '^  mealie\.backend\.[a-z_]+ -> mealie\.backend\.[a-z_]+' docs/architecture/model.c4`
returns **0**. Every relationship in the `components_backend` view is *inferred*
by LikeC4 from collapsing the ~1300 module-level edges in lines 498–1856. By
contrast `docs/arc42/05-building-block-view.md` draws a Mermaid with **17
hand-curated component edges** (`Entry -> Middleware/Routes/Services/DB/Core`,
`Routes -> Schema/Services/Repos/Core/Lang`, etc.). The two views are
maintained from the same source-of-truth import graph but will visually diverge
the first time anyone edits one without re-running the generator. Decide whether
the arc42 Mermaid is generated, deleted, or replaced by an embedded LikeC4 link.

### Q7. `SYSTEM_OVERVIEW.md` flags `mealie.pkgs` boundary as informal — LikeC4 does not

`SYSTEM_OVERVIEW.md` LEGACY ASSESSMENT calls out: "Mix of `mealie.pkgs` and
ad-hoc utilities … criteria for what becomes a 'pkg' vs stays a service helper
is unverified." arc42/05 §5.2 repeats the concern. The LikeC4 model neither
tags this nor encodes the constraint anywhere. If `pkgs` is supposed to have
*no* inbound dependency from `routes`, `repos`, or `db`, that's exactly the
kind of rule that belongs in `import-linter` *and* should be visible as a
constraint in the model — neither exists today.

## Drift (`SYSTEM_OVERVIEW.md` LEGACY ASSESSMENT)

**Anchor.** `SYSTEM_OVERVIEW.md` lines 145–166.

### Q8. arc42/05 §5.3 promises LikeC4 cross-references that were never added

Line 127 of `docs/arc42/05-building-block-view.md`:
> "For LikeC4 model views of these same building blocks: see `docs/architecture/`
> (cross-references to be added once Step 3c is complete)."

Step 3c *did* land (the LikeC4 sources exist and validate). The cross-refs were
never added back. The arc42 chapter therefore points to a file that points
nowhere back.

### Q9. The LikeC4 dev server is unreachable via MCP

`docs/architecture/likec4.config.json` exists, but `mcp__likec4__list-projects`
returned a single `default` project rooted at the literal path
`/home/thomas/Projects/mealie/${workspaceFolder}/` (variable not expanded) with
**zero source files**. Either the MCP needs project-id wiring (`name: "mealie"`
in `likec4.config.json`), or the server-launch instructions in the playbook
(`npx -y likec4 serve docs/architecture`) need to be added to the project README
so future agents don't fall back to reading `.c4` files line by line as we did.

### Q10. UNVERIFIED items in `SYSTEM_OVERVIEW.md` are not echoed anywhere else

`SYSTEM_OVERVIEW.md` lines 181–187 enumerate six explicitly unverified claims
(import-linter contracts location, SSE bulk-import path, `auto_init` typing
behaviour, Group → Household evolution order, scheduler safety with `WORKERS>1`,
test reliance on import-time `get_app_settings()`). None of these surface in
arc42 or in the LikeC4 model as `metadata` / `tag` markers. Either resolve them
or carry them forward as ADRs / tagged risks so they don't get re-discovered
on the next walkthrough.

---

## Disposition

These ten questions are the input set for **Step 4 / ADR-0001**. Suggested
grouping for the ADR:

- **ADR-0001 candidate:** "What counts as a Container in the Mealie LikeC4 model"
  — resolves Q1, Q2, Q3.
- **Follow-up ADR:** Actor taxonomy (Q4) — likely a smaller ADR or a model-only
  fix.
- **Follow-up ADR:** Building-block inventory & component-edge generation
  strategy (Q5, Q6, Q8) — almost certainly one ADR plus a script.
- **Process / tooling fixes (no ADR needed):** Q7 (import-linter contract), Q9
  (MCP wiring), Q10 (unverified-claims tracking).
