# Roadmap

## Purpose

TBD — to be filled in.

## Target users

TBD — to be filled in.

## Initial work list

Status inferred from current repo state (see linked pages) as of 2026-07-24.

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | Repo + monorepo structure | done | See `architecture.md`. |
| 2 | Backend setup: Spring Boot skeleton, healthcheck endpoint | done | `GET /actuator/health`, `GET /api/hello`. See `backend.md`. |
| 3 | Postgres: local Docker container, connection from backend, Flyway/Liquibase migrations from the start | done | Flyway in use (`spring-boot-starter-flyway`); `V1__create_users_table.sql`. See `backend.md`. |
| 4 | Docker: Dockerfile for both services, docker-compose for local dev | done | `backend/Dockerfile`, `frontend/Dockerfile`, root `docker-compose.yml`. |
| 5 | Backend: `users` table + migration | done | Includes all four audit columns from the start. See `backend.md`. |
| 6 | Backend: login endpoint (email + password), session cookie | done | `POST /api/login`, bcrypt via `spring-security-crypto`. See `backend.md`. |
| 7 | Backend: logout endpoint (session clear) | done | `POST /api/logout`. |
| 8 | Frontend: landing page | done | Public marketing page at `/` with placeholder copy — **needs the real product description, see "Pending content" below.** |
| 9 | Frontend: login form + session handling (cookie automatic, `fetch` with `credentials: include`) | done | `/login` route + `src/lib/api.ts`. Redirects to `/dashboard` on success. |
| 10 | Railway: provision two services, add env vars | done | Project `tervisehull`: Postgres + `backend` + `frontend` services, GitHub-connected (`main` branch), Root Directory set per service, public domains generated. All services online — see `operations.md`. |
| 11 | CI/CD: GitHub Actions — test + build + auto-deploy on `main` | in progress | Only `db-smoke.yml` (standalone `db/` smoke test) so far; backend/frontend test + build and deploy still todo. See `operations.md`. |
| 12 | Backend + frontend: registration flow | done | `POST /api/register` (auto-login on success, 409 if email taken), `/register` page. See `backend.md`. |
| 13 | Frontend: dashboard | done | `/dashboard`, auth-gated via `GET /api/me`. Placeholder content only ("Welcome, `{email}`" + logout) — **needs real dashboard content, see "Pending content" below.** |

## Pending content

Two pages exist with placeholder-only content, both blocked on the same
missing input — the product description (Purpose/Target users above are
still TBD):

- **Landing page copy** (`frontend/src/routes/+page.svelte`) — hero
  headline/subheadline and three feature blurbs are all `[PLACEHOLDER]`.
- **Dashboard content** (`frontend/src/routes/dashboard/+page.svelte`) —
  currently just a welcome message + logout button.

Once Purpose/Target users are filled in above, both pages need a follow-up
task to replace the placeholder content.

## Suggested next order

With auth, registration, and a basic dashboard in place: #11 (CI/CD) is the
main independent remaining item. The "Pending content" work above is blocked
on product description input, not on other engineering work.

## Planned: health knowledge database integration

Status: **todo**. The standalone schema exists (`database.md`, decisions in
`decisions.md`); nothing below is implemented in the backend yet.

**Integration and migrations**
- Bring the schema in as forward Flyway migrations (`V4+`); don't reuse version
  numbers or blindly baseline the bootstrap scripts. Decide first: one `users`
  table (backend's), identifier mapping, module ownership. (Audit columns are
  already in place on every table.)
- Prefer CSV-based import scripts over handwritten seed SQL; keep every row
  traceable to workbook sheet and original ID.
- Population descriptor and pharmacogenomic tables only after privacy/compliance
  approval.

**Backend modules** (by domain): `auth`, `users`, `profile`, `content`, `evidence`,
`rules` (incl. match engine), `search`, `review`, `audit`.

**Target matching flow**
1. Resolve entries through the selected search lane (aliases, EE products).
2. Store the selected/raw item in `user_profile_items`.
3. Expand published EE products to their published active ingredients.
4. Expand concepts through approved `concept_relationships` (`is_a` descendants).
5. Find eligible rules whose required participants are all present; each
   participant must map to a distinct saved item.
6. Evaluate approved rule conditions; unmet or missing values → no match unless
   the condition explicitly allows unknowns.
7. Apply approved risk modifiers from flags, conditions, current observations and
   MVP measurements; numeric checks are exact-unit only (mismatch logged, not
   converted).
8. Return risk label + escalation, approved copy, personal relevance flags,
   timing context, approved sources and a GP/pharmacist prompt.

Requirements for the public service beyond the eligibility view: usable
participant concepts, complete copy in the user's locale, approved substantive
evidence, all ingredient mappings usable for product matches, cycle-safe
descendant expansion. An empty result never establishes safety — report
unmatched items and unsupported rules as coverage. Demo rules are excluded.

**API surface (MVP)**
- Profile: `GET/PUT /api/me/profile/demographics`; CRUD on
  `/api/me/profile/items`, `/observations`; `GET/POST` on `/conditions`,
  `/measurements`.
- Search: `GET /api/search/profile-entry?entryType=…&q=…` (`/api/search/all`
  as admin/debug fallback); `GET /api/risk-levels`.
- Interactions: `POST /api/me/interactions/check`, `GET /api/me/interactions/summary`.
- Editor/admin: rules CRUD + `submit-review`/`approve`/`publish`/`retire`,
  evidence sources CRUD, review task decisions, `POST /api/admin/import/workbook`
  (import and user/permission management admin-only).

**Workbook import order**: risk levels → profile risk factors → concepts →
measurement types → aliases → products/aliases/ingredients (brand candidates stay
candidates) → evidence sources → rules → participants → conditions and their
sources → rule sources → timing → modifiers (+ conditions, sources) → copy →
review tasks. Imported rows default to non-public statuses.

**Content normalization before production**
- Merge duplicate substances (warfarin, levothyroxine, ciprofloxacin).
- Decide group rules vs ingredient rules (statins, tetracyclines,
  bisphosphonates, NSAIDs, SSRIs/SNRIs).
- Split broad non-drug groups (calcium supplement vs calcium-rich food, iron,
  magnesium, zinc, antacid, potassium supplement / salt substitute / rich food).
- Verify brand aliases against Ravimiregister / Estonian SPC/PIL.
- Every evidence source needs an `evidence_grade` before publication; consolidate
  the known duplicate article; review the 270 `search_only` sources.
- Write real English copy (current `en` rows are Estonian placeholders).

**Open product questions**
- Diagnosis input: free-text autocomplete, short risk-factor questions, or both?
- Blood pressure UI: one combined systolic/diastolic form or two fields?

**Schema stop rule**: further schema design stops once an external review rates
the model ≥9/10 for MVP fitness; after that, changes go into implementation tasks.

## Technical ideas

- **Audit fields on every table** (implemented, standing rule — see
  `backend.md`): every table gets `created_at`, `created_by`, `updated_at`,
  `updated_by`. Mechanism: `BaseEntity.java` (`@MappedSuperclass`) provides
  these four fields via Spring Data JPA auditing; every entity extends it
  (`User` is the first). Apply whenever a new table/entity is added — no
  exceptions unless explicitly decided otherwise.

## Open decisions

- ~~Migration tool choice~~ — resolved: Flyway.
- ~~Session mechanism~~ — resolved for now: plain servlet `HttpSession`
  (`JSESSIONID`), no Spring Security, no Redis. Revisit if the app needs to
  scale beyond one backend instance (in-memory sessions don't survive across
  instances without sticky sessions or a shared session store).
- Domain model beyond `users` — not yet defined (depends on Purpose above).
- ~~No signup/registration endpoint~~ — resolved: `POST /api/register`.
- No email verification on signup.
- Registration still leaks some user-enumeration signal via the distinct 409
  status code on duplicate email (message text was made vaguer, but the
  status code differs from success). Full fix (identical response either
  way, notify existing users by email) needs an email-sending flow that
  doesn't exist yet.
- Production cross-site cookie hardening (`SameSite=None; Secure`) and CORS
  origin — ~~resolved~~: `CorsConfig` now reads allowed origins from
  `CORS_ALLOWED_ORIGINS` (comma-separated), set to the deployed frontend's
  Railway URL in production. `SameSite=None; Secure` cookie hardening is
  still open, though frontend and backend are both HTTPS on Railway's own
  domains so `SameSite=Lax` may already work — needs verifying with a real
  cross-site login in production.
- No rate-limiting on login attempts.
