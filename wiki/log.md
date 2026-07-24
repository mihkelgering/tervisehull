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
