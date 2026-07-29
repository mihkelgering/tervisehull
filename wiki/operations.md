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

**Status: live.** Project `tervisehull` (workspace: Mihkel Gering's Projects),
environment `production`, three services, GitHub-connected to `main`:

- **Postgres** — `railway add --database postgres`. Internal-only, no public domain.
- **backend** — `https://backend-production-49fb.up.railway.app`. Root Directory
  `backend` (dashboard-only setting, no CLI flag for it), builds from
  `backend/railway.json` + `Dockerfile`, healthcheck `/actuator/health`.
  Variables: `SPRING_DATASOURCE_URL`/`USERNAME`/`PASSWORD` reference the
  Postgres service (`${{Postgres.PGHOST}}` etc), `SPRING_JPA_HIBERNATE_DDL_AUTO=validate`,
  `CORS_ALLOWED_ORIGINS=https://frontend-production-4c11.up.railway.app`.
- **frontend** — `https://frontend-production-4c11.up.railway.app`. Root
  Directory `frontend`. Variable: `PUBLIC_API_URL=https://backend-production-49fb.up.railway.app`.
  **Gotcha:** the domain's target port defaulted to 3000 (guessed from the
  Dockerfile's `EXPOSE 3000`), but `adapter-node` actually listens on
  whatever Railway injects as `PORT` (8080 in this environment) — this caused
  a 502 until the domain's target port was updated to match
  (`railway domain update <domain> --port 8080 --service frontend`). Check
  this again if the frontend 502s after a fresh domain generation.

Provisioned via the `railway` CLI (`brew install railway`, `railway login`,
`railway init`, `railway add --database postgres`,
`railway add --repo <owner>/<repo> --branch main --service <name>`,
`railway variable set ...`). **Root Directory has no CLI equivalent** —
set it in the dashboard (Service → Settings → Source → Root Directory) for
each of `backend`/`frontend`; setting it triggers a redeploy automatically.
Watch Paths (e.g. `backend/**`) were also set per service in the dashboard so
a commit to one directory doesn't redeploy the other.

## CI/CD

No pipeline exists yet (no `.github/workflows`). Planned: GitHub Actions running
tests + build, auto-deploy on push to `main`. See `roadmap.md`.
