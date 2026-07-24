# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Wiki

The `wiki/` folder is a living knowledge base. Keep it up to date as the codebase evolves:

- **Before starting a feature:** read the relevant wiki pages to understand current state
- **After completing work:** update any pages that are now out of date (new endpoints, changed domain model, new routes, etc.)

See `wiki/schema.md` for the maintenance workflow (ingest/query/lint) and `wiki/index.md` for the page catalog.

## Architecture

Monorepo with two independently built/deployed services and no shared code between them — see `wiki/architecture.md` for the full picture.

- **backend/** — Spring Boot 4 (Java 21, Gradle), package root `ee.tervisehull.backend`. Owns all persistent state (Postgres) and exposes a JSON API under `/api/*`. No server-rendered pages.
- **frontend/** — SvelteKit (`adapter-node`, TypeScript). Calls the backend over HTTP; runs as its own Node server in production, not statically hosted.
- **Postgres** — single database, backend-only access.

Schema management currently relies on `spring.jpa.hibernate.ddl-auto=update` (see `backend/src/main/resources/application.properties`) — no Flyway/Liquibase migrations are wired in yet, which will need to change before the `users` table lands (see `wiki/roadmap.md`).

Each service has its own `Dockerfile` and `railway.json` and deploys as a separate Railway service from the same repo; deployment details are in `wiki/operations.md`.

## Commands

**Backend** (run from `backend/`):
```bash
./gradlew bootRun                       # run locally (needs Postgres: `docker compose up db` from repo root)
./gradlew test                          # run all tests
./gradlew test --tests "ClassName"      # run a single test class
./gradlew bootJar                       # build -> build/libs/backend-0.0.1-SNAPSHOT.jar
```

**Frontend** (run from `frontend/`):
```bash
npm install
npm run dev              # local dev server
npm run build             # build -> build/ (started with `node build`)
npm run check              # svelte-kit sync + svelte-check (type checking)
```
No frontend test script exists yet.

**Everything together** (from repo root):
```bash
docker compose up --build   # Postgres + backend + frontend
```
Frontend on :3000, backend on :8080 (`/api/hello`, `/actuator/health`), Postgres on :5432 (db/user/pass = `tervisehull`).
