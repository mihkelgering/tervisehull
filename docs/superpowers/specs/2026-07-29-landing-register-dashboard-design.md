# Landing page, registration, dashboard — design

Date: 2026-07-29

## Goal

Closes roadmap item #8 (frontend landing page) plus two new items it depends
on: a registration flow and a minimal post-login dashboard. The landing page
becomes a public marketing page (placeholder copy — real product
description is TBD, see "Copy" below) linking to `/login` and `/register`.
After login or registration, the user lands on `/dashboard`.

Out of scope: real marketing copy (Purpose/Target users still TBD in
`wiki/roadmap.md`), email verification, password-strength meter beyond a
minimum length, conditional "you're already logged in" state on the landing
page, real dashboard content/features.

## Backend

### `POST /api/register`

- New `RegisterRequest` record: `email` (`@NotBlank @Email`), `password`
  (`@NotBlank @Size(min = 8)`), validated via `@Valid` (Jakarta Bean
  Validation — `spring-boot-starter-validation` is already a dependency).
  Validation failures fall through to Spring's default 400 response; no
  custom error formatting for this pass.
- In `AuthController`: if `userRepository.findByEmail(email)` is present,
  return 409 `{"message": "Email already registered"}`. Otherwise hash the
  password with the same `BCryptPasswordEncoder` used by login, save a new
  `User`, then **auto-login**: `request.getSession(true)`, set `userId`,
  same as the login flow. Respond 200 with `LoginResponse(email)` (reused,
  same shape as login's response).

### `GET /api/me`

- In `AuthController`: reads `userId` from the session
  (`request.getSession(false)`), same pattern as logout. If no session or no
  `userId` attribute: 401 `{"message": "Not logged in"}`. Otherwise look up
  the user by id via `userRepository.findById` and return 200
  `{"email": ...}` (or 401 if the id somehow doesn't resolve to a user —
  defensive, shouldn't happen in practice).

### Testing

- `AuthControllerTest` (existing file) gets new test methods:
  registering a new email succeeds and creates a session (reuse the
  session-assertion pattern from the login test); registering an existing
  email (the seeded `test@tervisehull.ee`) returns 409; `/api/me` with no
  session returns 401; `/api/me` after a successful login (via `MockMvc`
  session propagation — `MvcResult`'s request session reused across calls)
  returns 200 with the right email.

## Frontend

### API client (`src/lib/api.ts`)

Add two functions alongside the existing `login`/`logout`:

- `register(email, password): Promise<LoginResult>` — `POST /api/register`,
  `credentials: 'include'`. On 409 throws a new `EmailTakenError`. On other
  non-ok throws a generic `Error`.
- `me(): Promise<LoginResult>` — `GET /api/me`, `credentials: 'include'`. On
  401 throws a new `NotLoggedInError`. Used by the dashboard to check session
  state on load.

### Landing page (`src/routes/+page.svelte`)

Rewritten from the SvelteKit scaffold to a static public marketing page:
- Hero section: placeholder headline + subheadline, both wrapped in an HTML
  comment noting they're placeholders pending the real product description
  (see `wiki/roadmap.md`).
- 3 placeholder feature blurbs (heading + one sentence each), same
  placeholder marking.
- CTA buttons/links to `/login` and `/register`.
- No auth-check, no redirect — purely static/public.

### Registration page (`src/routes/register/+page.svelte`)

Mirrors the structure of the existing `src/routes/login/+page.svelte`:
email + password fields (`required`), loading state, error message on
failure (`EmailTakenError` → "That email is already registered"; other
errors → "Something went wrong, try again"). On success: `goto('/dashboard')`.

### Dashboard page (`src/routes/dashboard/+page.svelte`)

On mount (`$effect` or top-level `onMount`), calls `me()`:
- On success: shows "Welcome, `{email}`" and a logout button. Logout button
  calls `logout()` then `goto('/')`.
- On failure (`NotLoggedInError`): `goto('/login')`.
While the `me()` check is in flight, render a plain "Loading…" text (no flash
of dashboard content before the redirect fires).

### Login page (`src/routes/login/+page.svelte`)

One-line change: success redirect target changes from `goto('/')` to
`goto('/dashboard')`.

## Error handling

- `/api/register` 409 on duplicate email is an intentional, expected
  exception to the "don't leak which emails exist" rule that governs login —
  registration UX requires telling the user the email is taken.
- `/api/me` 401 is the expected/normal response for "not logged in", not an
  error condition — the dashboard treats it as a routing signal, not
  something to show an error message for.

## Wiki / roadmap updates (after implementation)

- `wiki/roadmap.md`: mark #8 `done`, with an explicit sub-note that landing
  page copy is placeholder and needs to be revisited once Purpose/Target
  users are filled in (new item, not just a footnote, so it isn't lost) —
  same treatment for the dashboard's placeholder content. Add two new rows:
  registration flow (done) and dashboard (done, placeholder content).
- `wiki/backend.md`: add `/api/register` and `/api/me` to the endpoints
  table.
- `wiki/frontend.md`: add `/register` and `/dashboard` routes; note the new
  `register`/`me` exports on the API client; note login's redirect target
  changed to `/dashboard`.
- `wiki/log.md`: append entry.
