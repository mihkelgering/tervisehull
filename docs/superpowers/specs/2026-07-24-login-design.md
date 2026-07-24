# Login (email + password) — design

Date: 2026-07-24

## Goal

A working login flow: a SvelteKit login page (email + password) that authenticates
against a real Postgres-backed `users` table via a Spring Boot session-cookie
login endpoint. Closes roadmap items #3 (Flyway), #5 (`users` table), #6 (login
endpoint), #7 (logout endpoint), and most of #9 (frontend login form).

Out of scope: signup/registration endpoint, password reset, rate-limiting,
production cross-site cookie hardening (`SameSite=None; Secure` — needed once
frontend/backend are on different Railway domains), the landing page itself
(#8, separate task).

## Backend

### Migrations (Flyway)

- Add `org.flywaydb:flyway-core` and `org.flywaydb:flyway-database-postgresql`
  to `backend/build.gradle`.
- `spring.jpa.hibernate.ddl-auto` changes from `update` to `validate` — Flyway
  owns schema from here on.
- `backend/src/main/resources/db/migration/V1__create_users_table.sql`:
  ```sql
  CREATE TABLE users (
      id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      email VARCHAR(255) NOT NULL UNIQUE,
      password_hash VARCHAR(255) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by BIGINT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_by BIGINT
  );
  ```
  (Identity column instead of UUID/`gen_random_uuid()` — avoids depending on the
  `pgcrypto` extension being enabled on the `postgres:16-alpine` image.
  `created_by`/`updated_by` are nullable, logical references to `users.id` —
  no FK constraint, since the first user and seed data have no acting user yet.
  See "Audit fields convention" below — every table gets these four columns
  from now on.)
- `V2__seed_test_user.sql`: inserts one dev/test user, `test@tervisehull.ee` /
  password `DevPassword123!`, as a bcrypt hash computed ahead of time and pasted
  into the migration as a literal. A comment in the migration marks it as
  dev-only seed data, not for production use. Credentials are also recorded in
  `wiki/backend.md`.

### Audit fields convention (project-wide, established here)

Every table gets four audit columns: `created_at`, `created_by`, `updated_at`,
`updated_by`. This is a standing convention (recorded in `wiki/backend.md` and
`CLAUDE.md`, not just here) — apply it to every future migration/entity.

- `BaseEntity.java` (`@MappedSuperclass`, in
  `ee.tervisehull.backend.common` or similar): fields `createdAt`, `createdBy`,
  `updatedAt`, `updatedBy`, annotated with Spring Data JPA auditing
  (`@CreatedDate`, `@CreatedBy`, `@LastModifiedDate`, `@LastModifiedBy`) plus
  `@EntityListeners(AuditingEntityListener.class)`.
- `@EnableJpaAuditing` on `BackendApplication`.
- `AuditorAware<Long>` bean resolves the acting user's id for `createdBy`/
  `updatedBy`. For this task, since we don't have Spring Security's
  `SecurityContext`, it reads from a request-scoped holder populated by a small
  `Filter` that looks up the `userId` session attribute (the same one `AuthController`
  sets on login) — returns `Optional.empty()` when there's no session (e.g. the
  login request itself, or unauthenticated requests), which leaves `created_by`/
  `updated_by` `NULL`.
- `User extends BaseEntity` — first entity to use it, sets the pattern for
  every entity added after this.

### Auth

- Add `org.springframework.security:spring-security-crypto` only (not full
  `spring-boot-starter-security`) — gives `BCryptPasswordEncoder` without pulling
  in a default security filter chain / login page / CSRF handling we'd have to
  fight with, since we're rolling session handling by hand for this scope.
- `User` JPA entity (`email`, `passwordHash`, extends `BaseEntity` for
  `id`/audit fields) + `UserRepository extends JpaRepository<User, Long>` with
  `findByEmail`.
- `AuthController`:
  - `POST /api/login` — body `{email, password}`. Looks up user by email,
    checks `BCryptPasswordEncoder.matches`. On success: `request.getSession(true)`,
    store `userId` as a session attribute, respond 200 `{email}`. On failure
    (no user, or bad password): 401 with a generic "invalid email or password"
    message — same message either way, no user-enumeration signal.
  - `POST /api/logout` — `request.getSession(false)`, if present `invalidate()`.
    Responds 200 regardless.
- CORS: a `WebMvcConfigurer` bean allowing origin `http://localhost:3000`,
  `allowCredentials(true)`, methods `GET,POST`, so the frontend's
  `credentials: 'include'` fetches work locally. Production origin is a follow-up
  (tracked in roadmap) once the frontend's deployed URL is known.

### Testing

- `AuthControllerTest` (`@SpringBootTest` + `MockMvc` or `@WebMvcTest` with a
  mocked repository): valid login → 200 + session cookie set; wrong password →
  401; unknown email → 401 (same message as wrong password).

## Frontend

- `src/lib/api.ts`: exports `login(email, password)` and `logout()`, wrapping
  `fetch` with `credentials: 'include'` against `PUBLIC_API_URL` (env var,
  default `http://localhost:8080` for dev via `.env`/Vite config).
- `src/routes/login/+page.svelte`: Svelte 5 runes-based component.
  - Fields: email (`type="email"`, `required`), password (`type="password"`,
    `required`). No client-side password complexity rules — server is the source
    of truth.
  - `$state` for form values, loading flag, error message.
  - On submit: call `login()`; disable submit button while in flight; on 401,
    show "Invalid email or password"; on success, `goto('/')`.

## Error handling

- Backend never reveals whether the failure was "no such user" vs "wrong
  password" — same 401 + message for both.
- Network/unexpected errors on the frontend show a generic "Something went
  wrong, try again" message rather than leaking raw fetch errors.

## Testing plan (frontend)

- No frontend test runner is currently configured (`wiki/frontend.md`) — manual
  verification via `npm run dev` + `npm run check` (type-checking) for this task.
  Adding a frontend test framework is out of scope here.

## Wiki / roadmap updates (after implementation)

- `wiki/roadmap.md`: mark #3, #5, #6, #7 `done`; #9 `done` (form + session
  handling); add the new open decisions (signup endpoint, production cookie
  settings) if not already listed.
- `wiki/backend.md`: add `/api/login`, `/api/logout` to the endpoint table; note
  Flyway is now in use; document the `users` table and the `BaseEntity`/audit
  fields convention.
- `wiki/frontend.md`: add `/login` route, note `src/lib/api.ts`.
- `wiki/log.md`: append entry.
