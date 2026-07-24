# Roadmap

## Purpose

TBD — to be filled in.

## Target users

TBD — to be filled in.

## Initial work list

Status inferred from current repo state (see linked pages) as of 2026-07-24.

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | Repo + monorepo structure | done | See `architecture.md`. |
| 2 | Backend setup: Spring Boot skeleton, healthcheck endpoint | done | `GET /actuator/health`, `GET /api/hello`. See `backend.md`. |
| 3 | Postgres: local Docker container, connection from backend, Flyway/Liquibase migrations from the start | in progress | Container + datasource connection exist (`docker-compose.yml`, `application.properties`). **Flyway/Liquibase not yet added** — schema is currently managed via `ddl-auto=update`. |
| 4 | Docker: Dockerfile for both services, docker-compose for local dev | done | `backend/Dockerfile`, `frontend/Dockerfile`, root `docker-compose.yml`. |
| 5 | Backend: `users` table + migration | todo | No migration tool yet (blocks this — see #3). |
| 6 | Backend: login endpoint (email + password), session cookie | todo | No auth code exists yet. |
| 7 | Backend: logout endpoint (session clear) | todo | Depends on #6. |
| 8 | Frontend: landing page | todo | `+page.svelte` is currently a scaffold with no real content. |
| 9 | Frontend: login form + session handling (cookie automatic, `fetch` with `credentials: include`) | todo | Depends on #6. |
| 10 | Railway: provision two services, add env vars | in progress | Deployment process documented in `operations.md`; actual provisioning status unconfirmed — confirm and update this row. |
| 11 | CI/CD: GitHub Actions — test + build + auto-deploy on `main` | todo | No `.github/workflows` in the repo yet. |

## Suggested next order

Given the dependencies above: #3 (add Flyway/Liquibase) unblocks #5, which unblocks
#6 and #7 (auth), which unblocks #9 (frontend login). #8 (landing page) and #11
(CI/CD) are independent and can happen anytime.

## Open decisions

- Migration tool choice: Flyway vs Liquibase — not yet decided.
- Session mechanism details (cookie store: in-memory, DB-backed, or Spring Session
  + Redis?) — not yet decided.
- Domain model beyond `users` — not yet defined (depends on Purpose above).
