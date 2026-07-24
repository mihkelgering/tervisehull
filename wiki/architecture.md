# Architecture

## Shape

Monorepo, two independently built/deployed services, no shared code between them.

```
/
├── backend/    Spring Boot 4 (Java 21, Gradle), PostgreSQL
├── frontend/   SvelteKit (adapter-node, TypeScript)
├── docker-compose.yml   Local dev: Postgres + backend + frontend together
└── .env.example         Backend env vars (Railway reference)
```

## Service boundaries

- **backend**: owns all persistent state (Postgres) and business logic. Exposes a
  JSON API under `/api/*`. No server-rendered pages.
- **frontend**: SvelteKit app, calls the backend API over HTTP. Runs as its own
  Node server in production (adapter-node), not statically hosted.
- **Postgres**: single database, backend-only access. No other service talks to it
  directly.

The two services communicate only over HTTP (frontend → backend `PUBLIC_API_URL`).
There is currently no shared package, no API client codegen, and no message queue.

## Deployment topology

Same repo, three separate Railway services (see `operations.md` for details):
1. PostgreSQL (Railway plugin)
2. Backend (root dir `backend/`, own Dockerfile + `railway.json`)
3. Frontend (root dir `frontend/`, own Dockerfile + `railway.json`)

Each service builds only from its own directory; watch paths can be configured so a
change to one doesn't redeploy the other.

## Not yet decided

- No auth/session architecture implemented yet (see `roadmap.md`).
- No migration tool wired up yet (Flyway/Liquibase planned, see `roadmap.md`).
- No CI/CD pipeline yet.
