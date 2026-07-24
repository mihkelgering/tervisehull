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
│   ├── api.ts            API client (login/logout — see below)
│   └── assets/favicon.svg
└── routes/
    ├── +layout.svelte   Root layout (scaffold)
    ├── +page.svelte     Landing page (scaffold, no real content yet)
    └── login/
        └── +page.svelte  Login form (email + password)
```

Landing page (`/`) is still a scaffold — see `roadmap.md`. No auth-aware layout
(e.g. redirecting unauthenticated users) exists yet.

## API client

`src/lib/api.ts` wraps `fetch` with `credentials: 'include'` against
`PUBLIC_API_URL` (`$env/dynamic/public`, defaults to `http://localhost:8080`
for dev). Exports `login(email, password): Promise<{ email }>` (throws
`InvalidCredentialsError` on 401) and `logout(): Promise<void>`.

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
