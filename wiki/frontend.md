# Frontend

SvelteKit, TypeScript, `adapter-node`. Runs as its own Node server in production
(not static hosting) — see `Dockerfile` / `build/index.js`.

## Layout

```
frontend/src/
├── app.html            HTML shell
├── app.d.ts            Ambient types
├── lib/
│   ├── index.ts         (empty, scaffold)
│   ├── api.ts            API client (see below)
│   └── assets/favicon.svg
└── routes/
    ├── +layout.svelte   Root layout (scaffold)
    ├── +page.svelte     Public marketing landing page (placeholder copy)
    ├── login/
    │   └── +page.svelte  Login form (email + password) → redirects to /dashboard
    ├── register/
    │   └── +page.svelte  Registration form (email + password) → redirects to /dashboard
    └── dashboard/
        └── +page.svelte  Auth-gated: checks session via me() on mount, redirects to
                           /login if not logged in; otherwise shows a welcome + logout
```

Landing page (`/`) copy is placeholder — see `roadmap.md`. It is public/static
with no auth-check. `/dashboard` is the only auth-gated page so far (client-side
check via `me()`, not SSR-guarded).

## API client

`src/lib/api.ts` wraps `fetch` with `credentials: 'include'` against
`PUBLIC_API_URL` (`$env/dynamic/public`, defaults to `http://localhost:8080`
for dev). Exports:
- `login(email, password): Promise<{ email }>` — throws `InvalidCredentialsError` on 401.
- `register(email, password): Promise<{ email }>` — throws `EmailTakenError` on 409. Auto-logs in on success (same session as login).
- `me(): Promise<{ email }>` — throws `NotLoggedInError` on 401. Used by `/dashboard` to check session state.
- `logout(): Promise<void>`.

## Config

- `vite.config.ts`, `tsconfig.json`, `.svelte-kit/` — standard SvelteKit setup.
- `PUBLIC_API_URL` — backend base URL, see `.env.example`. Not required locally
  (defaults to `http://localhost:8080`); set it in production once the
  backend's Railway URL is known.

## Build & run

```bash
cd frontend
npm install
npm run dev             # local dev server
npm ci && npm run build # -> build/ (started with `node build`)
```

## Ingest note

When adding a route, a form, or API calls to the backend: update the layout
diagram above, note any new env vars in `operations.md`, and update `roadmap.md`'s
status for the matching item (e.g. landing page, login form).
