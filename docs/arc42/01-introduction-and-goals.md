# 1. Introduction and Goals

Mealie is a self-hosted recipe manager, meal planner, and shopping-list application. The backend is a Python 3.12 FastAPI monolith (`mealie/app.py:115`); the frontend is a Nuxt 4 / Vue / Vuetify SPA (`frontend/package.json:21-39`). Persistence runs on SQLAlchemy 2.x with Alembic migrations against SQLite (default, WAL pragma) or PostgreSQL (`mealie/db/db_setup.py:16-50`, `pyproject.toml:46-49`).

## 1.1 Requirements Overview

Mealie ingests recipes (manual entry, URL scraping via `recipe-scrapers` or OpenAI — `mealie/services/scraper/scraper.py:25-45`), organises them within a two-level tenancy (Group → Household — `mealie/db/models/recipe/recipe.py:21-46`), and exposes them through a REST API mounted at `/api` (`mealie/routes/__init__.py:5-32`). It plans meals, builds shopping lists, fans out events to Apprise notifiers and group webhooks (`mealie/services/event_bus_service/event_bus_service.py:1-40`), and ships the SPA from the same process when `PRODUCTION=true` (`mealie/app.py:179-180`).

## 1.2 Quality Goals

The top three quality attributes are stated as testable scenarios. Adjective-only goals ("fast", "secure") are deliberately avoided.

| # | Quality attribute | Scenario |
|---|---|---|
| Q1 | **Tenant isolation** | Given two groups A and B, when a request authenticated as a member of A queries any recipe, meal-plan, or shopping-list endpoint under `/api`, the response contains zero rows belonging to B. Enforced by `get_repositories(session, group_id=..., household_id=...)` (`mealie/repos/all_repositories.py:8-11`) and exercised by `tests/multitenant_tests/`. |
| Q2 | **Self-host portability** | A fresh install must boot to a usable login screen on either SQLite or PostgreSQL with no manual schema setup. On startup, `init_db.main()` runs Alembic migrations and seeds the default group / household / user (`mealie/app.py:60-69`, `mealie/db/init_db.py:30-45`). |
| Q3 | **Deterministic dependency upgrades** | Every third-party version bump arrives as an isolated, reviewable change. Enforced by exact pinning (`add-bounds = "exact"`, `pyproject.toml:124`) plus Renovate (`renovate.json` at repo root). |

## 1.3 Stakeholders

| Role | Concern |
|---|---|
| **Self-hosting end user** | Wants Mealie to install via Docker on a home server, survive restarts, back up by copying a single SQLite file or running `pg_dump`, and keep their household's data private. Drives Q1 and Q2. |
| **Maintainers / core contributors** | Own the FastAPI monolith, the `@controller` CBV pattern (`mealie/routes/_base/controller.py:20-30`), the 47-revision Alembic history (`mealie/alembic/versions/`), and the lint/type/import-linter toolchain (`pyproject.toml:75-93`). Drive Q3 and architectural consistency. |
| **Integrators** | Consume the REST API at `/api` and react to event-bus payloads via Apprise targets or group webhooks (`mealie/services/event_bus_service/publisher.py:1-30`). Concerned with API stability and event payload schemas. |
