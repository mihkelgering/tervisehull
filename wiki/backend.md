# Backend

Spring Boot 4, Java 21, Gradle. Package root: `ee.tervisehull.backend`.

## Layout

```
backend/src/main/java/ee/tervisehull/backend/
├── BackendApplication.java   Spring Boot entry point
└── web/
    └── HelloController.java  Sample REST controller
backend/src/main/resources/
└── application.properties    Server, datasource, JPA, actuator config
```

## Endpoints (current)

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET | `/api/hello` | Sample/health-check response with a timestamp | none |
| GET | `/actuator/health` | Spring Actuator health probe (used by Railway healthcheck) | none |

No other endpoints exist yet. No users table, no auth endpoints — see `roadmap.md`.

## Configuration (`application.properties`)

- `server.port` — from `PORT` env var, defaults to `8080` locally.
- `spring.datasource.*` — from `SPRING_DATASOURCE_URL/USERNAME/PASSWORD`, defaults
  point at the local docker-compose Postgres (`localhost:5432/tervisehull`).
- `spring.jpa.hibernate.ddl-auto` — defaults to `update`. Comment in the file notes
  this should become `validate` once Flyway/Liquibase migrations are introduced.
- `management.endpoints.web.exposure.include=health,info` — actuator exposure for
  the Railway healthcheck.

## Data layer

Postgres, reached via the datasource config above. **No migration tool
(Flyway/Liquibase) is wired into `build.gradle` yet** — `ddl-auto=update` is doing
schema management for now. This is called out as needed in `roadmap.md`.

## Build & run

```bash
cd backend
./gradlew bootRun          # run locally (needs Postgres up, e.g. `docker compose up db`)
./gradlew bootJar          # -> build/libs/backend-0.0.1-SNAPSHOT.jar
./gradlew test
```

## Ingest note

When adding an endpoint, a table, or an auth mechanism: update the tables above,
and update `roadmap.md`'s status for the matching item.
