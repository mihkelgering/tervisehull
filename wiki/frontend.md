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
│   └── assets/favicon.svg
└── routes/
    ├── +layout.svelte   Root layout (scaffold)
    └── +page.svelte     Landing page (scaffold, no real content yet)
```

No routing beyond the root page exists yet. No API client, no auth/session
handling, no forms — see `roadmap.md`.

## Config

- `vite.config.ts`, `tsconfig.json`, `.svelte-kit/` — standard SvelteKit setup.
- No `PUBLIC_API_URL` (or similar) is wired up yet for talking to the backend;
  README's Railway section anticipates adding it once needed.

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
