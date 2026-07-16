# tervisehull

Monorepo, kus backend ja frontend on eraldi builditavad ja deployitavad.

```
/
├── backend/            # Spring Boot 4 (Java 21, Gradle), PostgreSQL, Dockerfile
├── frontend/           # SvelteKit (adapter-node, TypeScript), Dockerfile
├── docker-compose.yml  # Lokaalne dev: Postgres + backend + frontend
├── .env.example        # Backendi keskkonnamuutujad (Railway jaoks)
└── .gitignore
```

## Eeldused

- Java 21, Gradle (või kasuta `./gradlew` wrapperit)
- Node 22+
- Docker + Docker Compose

## Lokaalne arendus

### Kõik korraga (Docker Compose)

```bash
docker compose up --build
```

- Frontend: http://localhost:3000
- Backend:  http://localhost:8080/api/hello
- Health:   http://localhost:8080/actuator/health
- Postgres: localhost:5432 (db/user/pass = `tervisehull`)

### Eraldi (ilma Dockerita)

**Andmebaas:**
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

## Buildimine eraldi

```bash
# Backend -> backend/build/libs/backend-0.0.1-SNAPSHOT.jar
cd backend && ./gradlew bootJar

# Frontend -> frontend/build/ (Node server, käivitub `node build`)
cd frontend && npm ci && npm run build
```

Mõlemal on oma `Dockerfile`, seega saab ka eraldi konteineriteks ehitada:

```bash
docker build -t tervisehull-backend ./backend
docker build -t tervisehull-frontend ./frontend
```

## Railway deploy

Sama repo → **kolm eraldi teenust** samas Railway projektis.

1. **PostgreSQL** — lisa Railway projekti `Postgres` plugin (New → Database → PostgreSQL).

2. **Backend teenus**
   - New → GitHub Repo → vali see repo
   - Settings → **Root Directory**: `backend`
   - Build: Railway leiab `backend/railway.json` + `Dockerfile` automaatselt
   - Variables (viita Postgres pluginale):
     ```
     SPRING_DATASOURCE_URL=jdbc:postgresql://${{Postgres.PGHOST}}:${{Postgres.PGPORT}}/${{Postgres.PGDATABASE}}
     SPRING_DATASOURCE_USERNAME=${{Postgres.PGUSER}}
     SPRING_DATASOURCE_PASSWORD=${{Postgres.PGPASSWORD}}
     SPRING_JPA_HIBERNATE_DDL_AUTO=update
     ```
   - Healthcheck path (juba railway.json-is): `/actuator/health`
   - `PORT` annab Railway ise.

3. **Frontend teenus**
   - New → GitHub Repo → sama repo
   - Settings → **Root Directory**: `frontend`
   - Build: `frontend/railway.json` + `Dockerfile`
   - `PORT` annab Railway ise (adapter-node kuulab seda).
   - Kui frontend peab backendiga rääkima, lisa muutuja backendi avaliku URL-iga
     (nt `PUBLIC_API_URL`) ja kasuta seda SvelteKitis.

Iga teenus buildib ainult oma kaustast — commit ühte kausta ei re-deploy'i teist,
kui seadistad Settings → **Watch Paths** (nt backend teenusel `backend/**`).
