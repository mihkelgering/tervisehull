# tervisehull

Monorepo where the backend and frontend are built and deployed independently.

The standalone [health knowledge database](db/README.md) is available under `db/`,
with its schema, demonstration data and separate PostgreSQL setup. It is independent
of the backend's existing users database and migration history.

```
/
├── backend/            # Spring Boot 4 (Java 21, Gradle), PostgreSQL, Dockerfile
├── frontend/           # SvelteKit (adapter-node, TypeScript), Dockerfile
├── docker-compose.yml  # Local dev: Postgres + backend + frontend
├── .env.example        # Backend environment variables (for Railway)
└── .gitignore
```

## Prerequisites

- Java 21, Gradle (or use the `./gradlew` wrapper)
- Node 22+
- Docker + Docker Compose

## Local development

### Everything at once (Docker Compose)

```bash
docker compose up --build
```

- Frontend: http://localhost:3000
- Backend:  http://localhost:8080/api/hello
- Health:   http://localhost:8080/actuator/health
- Postgres: localhost:5432 (db/user/pass = `tervisehull`)

### Separately (without Docker)

**Database:**
```bash
docker compose up db
```

**Backend:**
```bash
cd backend
./gradlew bootRun
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
```

## Building separately

```bash
# Backend -> backend/build/libs/backend-0.0.1-SNAPSHOT.jar
cd backend && ./gradlew bootJar

# Frontend -> frontend/build/ (Node server, started with `node build`)
cd frontend && npm ci && npm run build
```

Each has its own `Dockerfile`, so they can also be built as separate containers:

```bash
docker build -t tervisehull-backend ./backend
docker build -t tervisehull-frontend ./frontend
```
## Wiki

The `wiki/` folder is a living knowledge base. Keep it up to date as the codebase evolves:

- **Before starting a feature:** read the relevant wiki pages to understand current state
- **After completing work:** update any pages that are now out of date (new endpoints, changed domain model, new routes, etc.)


## Railway deployment

Same repo → **three separate services** in one Railway project.

1. **PostgreSQL** — add a `Postgres` plugin to the Railway project (New → Database → PostgreSQL).

2. **Backend service**
   - New → GitHub Repo → select this repo
   - Settings → **Root Directory**: `backend`
   - Build: Railway picks up `backend/railway.json` + `Dockerfile` automatically
   - Variables (reference the Postgres plugin):
     ```
     SPRING_DATASOURCE_URL=jdbc:postgresql://${{Postgres.PGHOST}}:${{Postgres.PGPORT}}/${{Postgres.PGDATABASE}}
     SPRING_DATASOURCE_USERNAME=${{Postgres.PGUSER}}
     SPRING_DATASOURCE_PASSWORD=${{Postgres.PGPASSWORD}}
     SPRING_JPA_HIBERNATE_DDL_AUTO=validate
     CORS_ALLOWED_ORIGINS=<frontend's public URL>
     ```
   - Healthcheck path (already in railway.json): `/actuator/health`
   - `PORT` is provided by Railway.

3. **Frontend service**
   - New → GitHub Repo → same repo
   - Settings → **Root Directory**: `frontend`
   - Build: `frontend/railway.json` + `Dockerfile`
   - `PORT` is provided by Railway (adapter-node listens on it).
   - Variable: `PUBLIC_API_URL=<backend's public URL>`.
   - After generating the domain, double-check Settings → Networking →
     target port matches what `adapter-node` actually listens on (the
     injected `PORT`) — it can default to the Dockerfile's `EXPOSE` value
     instead and cause a 502.

Each service builds only from its own directory — a commit to one directory
won't redeploy the other if you configure Settings → **Watch Paths**
(e.g. `backend/**` on the backend service).

See `wiki/operations.md` for this project's actual deployed URLs and setup notes.
