# Landing Page, Registration, Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/` into a public marketing landing page (placeholder copy), add a registration flow (`POST /api/register`, `/register` page), and a minimal auth-gated dashboard (`GET /api/me`, `/dashboard` page) that login and registration redirect to.

**Architecture:** Backend adds two endpoints to the existing `AuthController` — `/api/register` (creates a user, auto-logs in via the same session mechanism as `/api/login`) and `/api/me` (session → email lookup, used by the frontend to gate the dashboard). Frontend adds `register`/`me` to the existing `src/lib/api.ts` client, a `/register` page mirroring `/login`, a `/dashboard` page that checks `me()` on mount and redirects to `/login` on failure, and rewrites `/` from the SvelteKit scaffold to a static public page.

**Tech Stack:** Same as the existing login feature — Spring Boot 4.1.0 (Java 21, Gradle), `spring-boot-starter-validation` (already a dependency, adds Bean Validation for the new `RegisterRequest`), `spring-security-crypto`. SvelteKit (Svelte 5 runes).

## Global Constraints

- No new Gradle dependencies needed — `spring-boot-starter-validation` is already present.
- `/api/register` duplicate-email 409 is an intentional exception to the "don't leak which emails exist" rule (that rule still applies to `/api/login`).
- Password minimum length for registration: 8 characters (`@Size(min = 8)`), enforced server-side via Bean Validation. No other complexity rules.
- Landing page copy is explicitly placeholder — mark it clearly (e.g. `[PLACEHOLDER]`) and note in `wiki/roadmap.md` that it needs the real product description.
- Backend tests require `docker compose up -d db` from repo root first (same as existing tests — no embedded test database).
- Frontend has no test runner configured; verification is `npm run check` plus manual/curl end-to-end checks.
- Svelte components use runes mode (`$state`, `onsubmit={...}`), matching the existing `login/+page.svelte`.

---

## Task 1: `POST /api/register`

**Files:**
- Create: `backend/src/main/java/ee/tervisehull/backend/auth/RegisterRequest.java`
- Modify: `backend/src/main/java/ee/tervisehull/backend/auth/AuthController.java`
- Modify: `backend/src/test/java/ee/tervisehull/backend/auth/AuthControllerTest.java`

**Interfaces:**
- Consumes: `UserRepository.findByEmail(String): Optional<User>`, `UserRepository.save(User): User` (from `JpaRepository`), `User(String email, String passwordHash)` constructor, `BCryptPasswordEncoder` (already a field on `AuthController`).
- Produces: `POST /api/register` (body `{"email":..., "password":...}` → 200 `{"email":...}` + session cookie on success; 409 `{"message":"Email already registered"}` if the email exists; 400 on validation failure e.g. password under 8 chars). Task 3 (frontend `api.ts`) calls this by path and shape.

- [ ] **Step 1: Add `@Transactional` to the test class**

The new tests insert real rows into the dev Postgres database; without a rollback they'd collide on re-run. Modify `backend/src/test/java/ee/tervisehull/backend/auth/AuthControllerTest.java`, add these two imports:

```java
import org.springframework.mock.web.MockHttpSession;
import org.springframework.transaction.annotation.Transactional;
```

and change the class declaration from:

```java
@SpringBootTest
@AutoConfigureMockMvc
class AuthControllerTest {
```

to:

```java
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AuthControllerTest {
```

- [ ] **Step 2: Write the failing tests**

Add these three test methods to `AuthControllerTest` (inside the class, alongside the existing ones):

```java
	@Test
	void registeringNewEmailCreatesSession() throws Exception {
		MvcResult result = mockMvc.perform(post("/api/register")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"newuser@tervisehull.ee\",\"password\":\"SomePassword123\"}"))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"email\":\"newuser@tervisehull.ee\"}"))
			.andReturn();

		assertNotNull(result.getRequest().getSession(false));
	}

	@Test
	void registeringExistingEmailReturns409() throws Exception {
		mockMvc.perform(post("/api/register")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"test@tervisehull.ee\",\"password\":\"SomePassword123\"}"))
			.andExpect(status().isConflict())
			.andExpect(content().json("{\"message\":\"Email already registered\"}"));
	}

	@Test
	void registeringWithShortPasswordReturns400() throws Exception {
		mockMvc.perform(post("/api/register")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"shortpw@tervisehull.ee\",\"password\":\"short\"}"))
			.andExpect(status().isBadRequest());
	}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
docker compose up -d db
cd backend
./gradlew test --tests "ee.tervisehull.backend.auth.AuthControllerTest"
```

Expected: the 3 new tests FAIL (404 — `/api/register` doesn't exist), the 4 existing tests still PASS.

- [ ] **Step 4: Write `RegisterRequest`**

Create `backend/src/main/java/ee/tervisehull/backend/auth/RegisterRequest.java`:

```java
package ee.tervisehull.backend.auth;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RegisterRequest(
	@NotBlank @Email String email,
	@NotBlank @Size(min = 8) String password
) {
}
```

- [ ] **Step 5: Add the `/register` endpoint to `AuthController`**

In `backend/src/main/java/ee/tervisehull/backend/auth/AuthController.java`, add these imports:

```java
import jakarta.validation.Valid;
```

and add this method (e.g. after `login`):

```java
	@PostMapping("/register")
	public ResponseEntity<?> register(@Valid @RequestBody RegisterRequest registerRequest, HttpServletRequest request) {
		if (userRepository.findByEmail(registerRequest.email()).isPresent()) {
			return ResponseEntity.status(409).body(Map.of("message", "Email already registered"));
		}

		User user = userRepository.save(
			new User(registerRequest.email(), passwordEncoder.encode(registerRequest.password())));

		HttpSession session = request.getSession(true);
		session.setAttribute("userId", user.getId());

		return ResponseEntity.ok(new LoginResponse(user.getEmail()));
	}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd backend
./gradlew test --tests "ee.tervisehull.backend.auth.AuthControllerTest"
```

Expected: PASS (7 tests: 4 existing + 3 new).

- [ ] **Step 7: Commit**

```bash
git add backend/src/main/java/ee/tervisehull/backend/auth/RegisterRequest.java \
  backend/src/main/java/ee/tervisehull/backend/auth/AuthController.java \
  backend/src/test/java/ee/tervisehull/backend/auth/AuthControllerTest.java
git commit -m "feat(backend): add registration endpoint"
```

---

## Task 2: `GET /api/me`

**Files:**
- Modify: `backend/src/main/java/ee/tervisehull/backend/auth/AuthController.java`
- Modify: `backend/src/test/java/ee/tervisehull/backend/auth/AuthControllerTest.java`

**Interfaces:**
- Consumes: `UserRepository.findById(Long): Optional<User>` (from `JpaRepository`).
- Produces: `GET /api/me` (200 `{"email":...}` if a valid session exists, 401 `{"message":"Not logged in"}` otherwise). Task 5's dashboard page calls this directly.

- [ ] **Step 1: Write the failing tests**

Add these two test methods to `AuthControllerTest`:

```java
	@Test
	void meWithoutSessionReturns401() throws Exception {
		mockMvc.perform(get("/api/me"))
			.andExpect(status().isUnauthorized());
	}

	@Test
	void meAfterLoginReturnsEmail() throws Exception {
		MockHttpSession session = new MockHttpSession();

		mockMvc.perform(post("/api/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"test@tervisehull.ee\",\"password\":\"DevPassword123!\"}")
				.session(session))
			.andExpect(status().isOk());

		mockMvc.perform(get("/api/me").session(session))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"email\":\"test@tervisehull.ee\"}"));
	}
```

Add the missing static import to the top of the file:

```java
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
docker compose up -d db
cd backend
./gradlew test --tests "ee.tervisehull.backend.auth.AuthControllerTest"
```

Expected: the 2 new tests FAIL (404 — `/api/me` doesn't exist), the 7 existing tests still PASS.

- [ ] **Step 3: Add the `/me` endpoint to `AuthController`**

Add this import:

```java
import org.springframework.web.bind.annotation.GetMapping;
```

and add this method:

```java
	@GetMapping("/me")
	public ResponseEntity<?> me(HttpServletRequest request) {
		HttpSession session = request.getSession(false);
		Object userId = session != null ? session.getAttribute("userId") : null;

		if (!(userId instanceof Long id)) {
			return ResponseEntity.status(401).body(Map.of("message", "Not logged in"));
		}

		return userRepository.findById(id)
			.<ResponseEntity<?>>map(user -> ResponseEntity.ok(new LoginResponse(user.getEmail())))
			.orElseGet(() -> ResponseEntity.status(401).body(Map.of("message", "Not logged in")));
	}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd backend
./gradlew test --tests "ee.tervisehull.backend.auth.AuthControllerTest"
```

Expected: PASS (9 tests).

- [ ] **Step 5: Run the full backend suite**

```bash
./gradlew test
```

Expected: PASS (all tests across all classes).

- [ ] **Step 6: Commit**

```bash
git add backend/src/main/java/ee/tervisehull/backend/auth/AuthController.java \
  backend/src/test/java/ee/tervisehull/backend/auth/AuthControllerTest.java
git commit -m "feat(backend): add GET /api/me session-check endpoint"
```

---

## Task 3: Frontend API client — `register` and `me`

**Files:**
- Modify: `frontend/src/lib/api.ts`

**Interfaces:**
- Consumes: `POST /api/register` and `GET /api/me` from Tasks 1–2 (exact shapes above).
- Produces: `register(email: string, password: string): Promise<LoginResult>` (throws `EmailTakenError` on 409), `me(): Promise<LoginResult>` (throws `NotLoggedInError` on 401), for Tasks 4–5's pages to import from `$lib/api`.

- [ ] **Step 1: Add the new error classes and functions**

In `frontend/src/lib/api.ts`, after the existing `InvalidCredentialsError` class, add:

```typescript
export class EmailTakenError extends Error {
	constructor() {
		super('That email is already registered');
	}
}

export class NotLoggedInError extends Error {
	constructor() {
		super('Not logged in');
	}
}
```

After the existing `login` function, add:

```typescript
export async function register(email: string, password: string): Promise<LoginResult> {
	const response = await fetch(`${API_URL}/api/register`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		credentials: 'include',
		body: JSON.stringify({ email, password })
	});

	if (response.status === 409) {
		throw new EmailTakenError();
	}

	if (!response.ok) {
		throw new Error('Something went wrong, try again');
	}

	return response.json();
}

export async function me(): Promise<LoginResult> {
	const response = await fetch(`${API_URL}/api/me`, {
		method: 'GET',
		credentials: 'include'
	});

	if (response.status === 401) {
		throw new NotLoggedInError();
	}

	if (!response.ok) {
		throw new Error('Something went wrong, try again');
	}

	return response.json();
}
```

- [ ] **Step 2: Verify it type-checks**

```bash
cd frontend
npm run check
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/api.ts
git commit -m "feat(frontend): add register/me to API client"
```

---

## Task 4: Registration page

**Files:**
- Create: `frontend/src/routes/register/+page.svelte`

**Interfaces:**
- Consumes: `register(email, password): Promise<LoginResult>` and `EmailTakenError` from `$lib/api` (Task 3).
- Produces: the `/register` route, redirecting to `/dashboard` on success (Task 5 must exist for this redirect to land somewhere real — Task 5 can be done before or after this one, order doesn't block compilation, but do Task 5 before manual verification in Task 6).

- [ ] **Step 1: Write the registration page**

Create `frontend/src/routes/register/+page.svelte`:

```svelte
<script lang="ts">
	import { goto } from '$app/navigation';
	import { register, EmailTakenError } from '$lib/api';

	let email = $state('');
	let password = $state('');
	let loading = $state(false);
	let errorMessage = $state('');

	async function handleSubmit(event: SubmitEvent) {
		event.preventDefault();
		errorMessage = '';
		loading = true;

		try {
			await register(email, password);
			await goto('/dashboard');
		} catch (error) {
			errorMessage =
				error instanceof EmailTakenError ? error.message : 'Something went wrong, try again';
		} finally {
			loading = false;
		}
	}
</script>

<form onsubmit={handleSubmit}>
	<h1>Register</h1>

	<label for="email">Email</label>
	<input id="email" type="email" bind:value={email} required autocomplete="email" />

	<label for="password">Password</label>
	<input
		id="password"
		type="password"
		bind:value={password}
		required
		minlength="8"
		autocomplete="new-password"
	/>

	{#if errorMessage}
		<p role="alert">{errorMessage}</p>
	{/if}

	<button type="submit" disabled={loading}>
		{loading ? 'Creating account…' : 'Register'}
	</button>
</form>
```

- [ ] **Step 2: Verify it type-checks**

```bash
cd frontend
npm run check
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/routes/register/+page.svelte
git commit -m "feat(frontend): add registration page"
```

---

## Task 5: Dashboard page + login redirect change

**Files:**
- Create: `frontend/src/routes/dashboard/+page.svelte`
- Modify: `frontend/src/routes/login/+page.svelte`

**Interfaces:**
- Consumes: `me(): Promise<LoginResult>`, `logout(): Promise<void>`, `NotLoggedInError` from `$lib/api`.
- Produces: the `/dashboard` route. No later task depends on this one directly, but Task 6's manual verification exercises it.

- [ ] **Step 1: Write the dashboard page**

Create `frontend/src/routes/dashboard/+page.svelte`:

```svelte
<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { me, logout, NotLoggedInError } from '$lib/api';

	let email = $state<string | null>(null);

	onMount(async () => {
		try {
			const result = await me();
			email = result.email;
		} catch (error) {
			if (error instanceof NotLoggedInError) {
				await goto('/login');
			}
		}
	});

	async function handleLogout() {
		await logout();
		await goto('/');
	}
</script>

{#if email}
	<h1>Welcome, {email}</h1>
	<button onclick={handleLogout}>Log out</button>
{:else}
	<p>Loading…</p>
{/if}
```

- [ ] **Step 2: Change the login page's redirect target**

In `frontend/src/routes/login/+page.svelte`, change:

```typescript
			await login(email, password);
			await goto('/');
```

to:

```typescript
			await login(email, password);
			await goto('/dashboard');
```

- [ ] **Step 3: Verify it type-checks**

```bash
cd frontend
npm run check
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/routes/dashboard/+page.svelte frontend/src/routes/login/+page.svelte
git commit -m "feat(frontend): add dashboard page, redirect login/register there"
```

---

## Task 6: Landing page + end-to-end verification

**Files:**
- Modify: `frontend/src/routes/+page.svelte`

**Interfaces:** none — the landing page is a leaf, nothing depends on it.

- [ ] **Step 1: Rewrite the landing page**

Replace the full contents of `frontend/src/routes/+page.svelte` with:

```svelte
<!--
	Placeholder marketing copy. Replace once Purpose/Target users are filled
	in in wiki/roadmap.md — see the "Landing page copy" item there.
-->
<main>
	<section>
		<h1>[PLACEHOLDER] Tervisehull</h1>
		<p>[PLACEHOLDER] A one-sentence pitch for what tervisehull does and who it's for goes here.</p>
		<a href="/register">Get started</a>
		<a href="/login">Log in</a>
	</section>

	<section>
		<h2>[PLACEHOLDER] Feature one</h2>
		<p>[PLACEHOLDER] One sentence describing this feature.</p>
	</section>

	<section>
		<h2>[PLACEHOLDER] Feature two</h2>
		<p>[PLACEHOLDER] One sentence describing this feature.</p>
	</section>

	<section>
		<h2>[PLACEHOLDER] Feature three</h2>
		<p>[PLACEHOLDER] One sentence describing this feature.</p>
	</section>
</main>
```

- [ ] **Step 2: Verify it type-checks**

```bash
cd frontend
npm run check
```

Expected: no errors.

- [ ] **Step 3: Full backend test run**

```bash
docker compose up -d db
cd backend
./gradlew test
```

Expected: PASS (all tests).

- [ ] **Step 4: Manual end-to-end verification**

```bash
docker compose up --build
```

Then, either in a browser or via curl against `http://localhost:3000` / `http://localhost:8080`:

1. `GET /` (frontend) — shows the placeholder marketing page with "Get started" (→ `/register`) and "Log in" (→ `/login`) links.
2. Register a new account (`POST /api/register` with a fresh email, or the `/register` form) — should succeed, land on `/dashboard`, show "Welcome, `<email>`".
3. Try registering the same email again — should fail with "That email is already registered" (or, via curl, `409` + `{"message":"Email already registered"}`).
4. On the dashboard, click "Log out" — should return to `/` and the session should no longer be valid (`GET /api/me` → 401).
5. Log in again with the seeded dev user (`test@tervisehull.ee` / `DevPassword123!`) — should land on `/dashboard`.
6. Visiting `/dashboard` directly without a session (e.g. in a fresh incognito window, or after logging out) should redirect to `/login`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/routes/+page.svelte
git commit -m "feat(frontend): rewrite landing page as public marketing page"
```

---

## Task 7: Update docs

**Files:**
- Modify: `wiki/backend.md`
- Modify: `wiki/frontend.md`
- Modify: `wiki/roadmap.md`
- Modify: `wiki/log.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update `wiki/backend.md`**

In the "Endpoints (current)" table, add two rows:

```
| POST | `/api/register` | Email+password signup; creates the user and a session cookie (auto-login) | none (credentials in body) |
| GET | `/api/me` | Returns the logged-in user's email, or 401 if not logged in | session cookie |
```

Update the "No signup endpoint exists" note (if present) to reflect that registration now exists.

- [ ] **Step 2: Update `wiki/frontend.md`**

Add `/register` and `/dashboard` to the routes list. Note the new `register`/`me` exports (and `EmailTakenError`/`NotLoggedInError`) on the API client. Note that `/login` and `/register` now redirect to `/dashboard` on success, and that `/` (landing page) is now a public marketing page with placeholder copy.

- [ ] **Step 3: Update `wiki/roadmap.md`**

Mark #8 (frontend landing page) as `done`, with an explicit note/sub-item that the copy is placeholder pending the real product description (Purpose/Target users). Add two new rows to the work-list table: registration flow (`done`) and dashboard (`done`, placeholder content) — matching the existing table's column style (`# | Item | Status | Notes`, continuing the numbering from 11, i.e. items 12 and 13). Add a line under "Open decisions" (or a new "Pending content" section) explicitly stating: landing page copy and dashboard content both need the real product description before they're production-ready — this is the reminder the user asked to keep.

- [ ] **Step 4: Append to `wiki/log.md`**

```
- 2026-07-29 — Added registration (POST /api/register, auto-login) and a
  session-check endpoint (GET /api/me). Rewrote the landing page (/) as a
  public marketing page with placeholder copy, added /register and
  /dashboard pages; login and registration now redirect to /dashboard.
  Pages touched: backend.md, frontend.md, roadmap.md.
```

- [ ] **Step 5: Commit**

```bash
git add wiki/backend.md wiki/frontend.md wiki/roadmap.md wiki/log.md
git commit -m "docs: update wiki for landing page, registration, dashboard"
```
