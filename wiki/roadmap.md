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
| 3 | Postgres: local Docker container, connection from backend, Flyway/Liquibase migrations from the start | done | Flyway in use (`spring-boot-starter-flyway`); `V1__create_users_table.sql`. See `backend.md`. |
| 4 | Docker: Dockerfile for both services, docker-compose for local dev | done | `backend/Dockerfile`, `frontend/Dockerfile`, root `docker-compose.yml`. |
| 5 | Backend: `users` table + migration | done | Includes all four audit columns from the start. See `backend.md`. |
| 6 | Backend: login endpoint (email + password), session cookie | done | `POST /api/login`, bcrypt via `spring-security-crypto`. See `backend.md`. |
| 7 | Backend: logout endpoint (session clear) | done | `POST /api/logout`. |
| 8 | Frontend: landing page | todo | `+page.svelte` is currently a scaffold with no real content. |
| 9 | Frontend: login form + session handling (cookie automatic, `fetch` with `credentials: include`) | done | `/login` route + `src/lib/api.ts`. No auth-aware layout/redirect-if-logged-in yet. |
| 10 | Railway: provision two services, add env vars | in progress | Deployment process documented in `operations.md`; actual provisioning status unconfirmed — confirm and update this row. |
| 11 | CI/CD: GitHub Actions — test + build + auto-deploy on `main` | todo | No `.github/workflows` in the repo yet. |

## Suggested next order

With auth in place: #8 (landing page, ideally auth-aware — redirect to `/login`
if no session) and #11 (CI/CD) are the two independent remaining items.

## Technical ideas

- **Audit fields on every table** (implemented, standing rule — see
  `backend.md`): every table gets `created_at`, `created_by`, `updated_at`,
  `updated_by`. Mechanism: `BaseEntity.java` (`@MappedSuperclass`) provides
  these four fields via Spring Data JPA auditing; every entity extends it
  (`User` is the first). Apply whenever a new table/entity is added — no
  exceptions unless explicitly decided otherwise.

## Open decisions

- ~~Migration tool choice~~ — resolved: Flyway.
- ~~Session mechanism~~ — resolved for now: plain servlet `HttpSession`
  (`JSESSIONID`), no Spring Security, no Redis. Revisit if the app needs to
  scale beyond one backend instance (in-memory sessions don't survive across
  instances without sticky sessions or a shared session store).
- Domain model beyond `users` — not yet defined (depends on Purpose above).
- No signup/registration endpoint — only the seeded dev user exists.
- Production cross-site cookie hardening (`SameSite=None; Secure`) and CORS
  origin — needed once frontend/backend are deployed to different Railway
  domains; current `CorsConfig` only allows `http://localhost:3000`.
- No rate-limiting on login attempts.
