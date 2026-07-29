# Backend

Spring Boot 4, Java 21, Gradle. Package root: `ee.tervisehull.backend`.

## Layout

```
backend/src/main/java/ee/tervisehull/backend/
├── BackendApplication.java   Spring Boot entry point
├── web/
│   └── HelloController.java  Sample REST controller
├── auth/
│   ├── AuthController.java   Login/logout/register/me endpoints
│   ├── LoginRequest.java     Request DTO (email, password)
│   ├── LoginResponse.java    Response DTO (email) — reused by register and me
│   └── RegisterRequest.java  Request DTO (email, password — Bean Validation)
├── user/
│   ├── User.java              JPA entity (extends BaseEntity)
│   └── UserRepository.java    Spring Data repository (findByEmail)
└── common/
    ├── BaseEntity.java        Audit fields (see convention below)
    ├── JpaAuditingConfig.java @EnableJpaAuditing + AuditorAware bean
    ├── CurrentUserHolder.java Request-scoped holder for the logged-in user id
    ├── CurrentUserFilter.java Populates CurrentUserHolder from the session
    └── CorsConfig.java        Allows the local frontend origin, with credentials
backend/src/main/resources/
├── application.properties    Server, datasource, JPA, actuator config
└── db/migration/             Flyway migrations (V1 users table, V2 seed user)
```

## Endpoints (current)

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET | `/api/hello` | Sample/health-check response with a timestamp | none |
| GET | `/actuator/health` | Spring Actuator health probe (used by Railway healthcheck) | none |
| POST | `/api/login` | Email+password login; creates a session cookie (`JSESSIONID`) | none (credentials in body) |
| POST | `/api/logout` | Invalidates the current session | session cookie |
| POST | `/api/register` | Email+password signup; creates the user and a session cookie (auto-login). 409 if email taken, 400 on validation failure (password &lt; 8 chars) | none (credentials in body) |
| GET | `/api/me` | Returns the logged-in user's email, or 401 if not logged in | session cookie |

## Configuration (`application.properties`)

- `server.port` — from `PORT` env var, defaults to `8080` locally.
- `spring.datasource.*` — from `SPRING_DATASOURCE_URL/USERNAME/PASSWORD`, defaults
  point at the local docker-compose Postgres (`localhost:5432/tervisehull`).
- `spring.jpa.hibernate.ddl-auto` — defaults to `validate`. Flyway owns schema
  management; Hibernate only validates entities against it.
- `management.endpoints.web.exposure.include=health,info` — actuator exposure for
  the Railway healthcheck.

## Data layer

Postgres, reached via the datasource config above. Schema is managed by **Flyway**
(`backend/src/main/resources/db/migration/`, Spring Boot 4's
`spring-boot-starter-flyway` module — plain `flyway-core` alone does not
autoconfigure migrations on this version).

### `users` table

Created by `V1__create_users_table.sql`, columns: `id` (identity), `email`
(unique), `password_hash` (bcrypt), plus the four audit columns below.
`V2__seed_test_user.sql` seeds one dev/test account: `test@tervisehull.ee` /
`DevPassword123!` — **dev-only, not for production**.

### Convention: audit fields on every table

**Every table gets four audit columns: `created_at`, `created_by`, `updated_at`,
`updated_by`.** This is a standing rule, not a per-table decision — apply it to
every new migration/entity, no exceptions unless explicitly decided otherwise.

Mechanism (implemented, see `common/` above): `BaseEntity` (`@MappedSuperclass`)
provides these four fields via Spring Data JPA auditing (`@CreatedDate`,
`@CreatedBy`, `@LastModifiedDate`, `@LastModifiedBy` + `@EnableJpaAuditing`), and
every JPA entity extends it (`User` is the first). `created_by`/`updated_by` are
nullable, logical references to `users.id` (no FK constraint, since not every
write has an acting user yet, e.g. seed data or unauthenticated requests). The
acting user id is resolved by `CurrentUserFilter` reading the `userId` session
attribute set at login into a request-scoped `CurrentUserHolder`, which
`JpaAuditingConfig`'s `AuditorAware` bean reads from.

**Self-created rows (no other acting user exists yet):** rather than leaving
`created_by`/`updated_by` `NULL`, self-reference the row's own id.
Self-registration (`AuthController.register`) does this in code: save once
(auditing leaves the fields `NULL` since there's no session yet), then
`user.setCreatedBy(user.getId())` / `setUpdatedBy(...)` and save again —
`BaseEntity` exposes setters for exactly this case (JPA auditing only
overwrites these fields when `AuditorAware` has a value, so a manually-set
value sticks). Seed/migration data does the equivalent in SQL, e.g.
`UPDATE users SET created_by = id, updated_by = id WHERE ...` after the
insert (see `V3__backfill_seed_user_created_by.sql`), or a
`WITH inserted AS (INSERT ... RETURNING id) UPDATE ... FROM inserted` in a
single statement for new seed rows going forward. **Never edit an
already-applied migration file to fix this retroactively** — Flyway
validates checksums of applied migrations on startup, so a follow-up
migration is required instead.

### Auth mechanism

Session-cookie based, no Spring Security (deliberately — only
`spring-security-crypto` for `BCryptPasswordEncoder`, to avoid a default
filter chain/login page/CSRF handling not needed at this stage). `POST
/api/login` checks the password hash and, on success, calls
`request.getSession(true)` and stores `userId`; the servlet container's
`JSESSIONID` cookie is the session token. `POST /api/logout` invalidates the
session. Both directions never distinguish "unknown email" from "wrong
password" in their response.

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
