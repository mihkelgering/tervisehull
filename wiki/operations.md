# Operations

## Local development

**Everything at once:**
```bash
docker compose up --build
```
- Frontend: http://localhost:3000
- Backend: http://localhost:8080/api/hello
- Health: http://localhost:8080/actuator/health
- Postgres: localhost:5432 (db/user/pass = `tervisehull`)

**Separately:**
```bash
docker compose up db          # Postgres only
cd backend && ./gradlew bootRun
cd frontend && npm install && npm run dev
```

## Environment variables

See `.env.example` at repo root for backend variables used by Railway
(`SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`,
`SPRING_JPA_HIBERNATE_DDL_AUTO`). `PORT` is provided by Railway/docker-compose, not
set manually.

## Railway deployment

Same repo → three separate services in one Railway project:

1. **PostgreSQL** — Railway plugin (New → Database → PostgreSQL).
2. **Backend** — Root Directory `backend`; builds from `backend/railway.json` +
   `Dockerfile`; healthcheck `/actuator/health`; datasource vars reference the
   Postgres plugin (`${{Postgres.PGHOST}}` etc).
3. **Frontend** — Root Directory `frontend`; builds from `frontend/railway.json` +
   `Dockerfile`; needs a `PUBLIC_API_URL`-style var once it talks to the backend.

Configure **Watch Paths** per service (e.g. `backend/**`) so a commit to one
directory doesn't redeploy the other.

**Status:** documented and ready to configure; whether the Railway services are
actually provisioned yet is tracked in `roadmap.md`.

## CI/CD

No pipeline exists yet (no `.github/workflows`). Planned: GitHub Actions running
tests + build, auto-deploy on push to `main`. See `roadmap.md`.
