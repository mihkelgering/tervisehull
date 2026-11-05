# Wiki log

Append-only. One line per wiki update: date, what changed, pages touched.

- 2026-07-24 — Initial wiki created (index, schema, architecture, backend,
  frontend, operations, roadmap), reflecting the repo at commit `2083428`
  (monorepo scaffold: Spring Boot hello endpoint + healthcheck, SvelteKit blank
  page, docker-compose, Railway docs). Roadmap populated from a work list
  provided by the user; purpose and target users left TBD.
- 2026-07-24 — Implemented email+password login: Flyway (via
  `spring-boot-starter-flyway`, not just `flyway-core` — Spring Boot 4
  modularized this) + `users` table with audit columns, `BaseEntity`/JPA
  auditing resolving the acting user from the session, `POST /api/login` +
  `/api/logout` (session cookie, bcrypt via `spring-security-crypto`), CORS
  for `localhost:3000`, frontend `/login` page + `src/lib/api.ts`. Verified
  against the real docker-compose stack (curl: session cookie set, 401 on
  wrong password, CORS preflight). Pages touched: backend.md, frontend.md,
  roadmap.md.
- 2026-07-29 — Added registration (POST /api/register, auto-login) and a
  session-check endpoint (GET /api/me). Rewrote the landing page (/) as a
  public marketing page with placeholder copy, added /register and
  /dashboard pages; login and registration now redirect to /dashboard.
  Verified against the real docker-compose stack (curl: register, duplicate
  409, /api/me reflecting session state, logout invalidation, login).
  Pages touched: backend.md, frontend.md, roadmap.md.
- 2026-07-29 — Provisioned Railway (project `tervisehull`: Postgres, backend,
  frontend, GitHub-connected to `main`) via the `railway` CLI. Made CORS
  allowed origins configurable (`CORS_ALLOWED_ORIGINS` env var) instead of
  hardcoded `localhost:3000`, needed for the deployed frontend. Fixed a 502
  caused by the frontend's Railway domain defaulting to target port 3000
  while `adapter-node` actually listens on the injected `PORT` (8080).
  Verified end-to-end against the live URLs (health, CORS preflight,
  registration with session cookie). Pages touched: roadmap.md, operations.md.
- 2026-11-05 - Added the standalone health knowledge database package, including
  schema, fixtures, source metadata, PostgreSQL setup and smoke checks. Documented
  its separation from the existing backend schema. Pages touched: database.md,
  index.md.
