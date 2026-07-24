# Wiki schema

How this wiki is maintained. Read this before ingesting new work or querying for context.

Pattern: raw sources (the code, commits, this conversation history) are immutable truth.
This wiki is a compiled, persistent summary of that truth, kept current instead of
re-derived from scratch on every question. See:
https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

## Pages

| Page | Covers |
|---|---|
| `index.md` | Catalog of every wiki page, one-line summary each |
| `roadmap.md` | Product purpose, target users, planned/needed features, status |
| `architecture.md` | Monorepo shape, service boundaries, deployment topology |
| `backend.md` | Spring Boot service: packages, endpoints, config |
| `frontend.md` | SvelteKit app: routes, structure, config |
| `operations.md` | Local dev, env vars, Railway deployment |
| `log.md` | Append-only history of wiki changes |

## Operations

**Ingest** (after completing a feature or making a decision):
1. Identify which pages are now stale (new endpoint → `backend.md`; new route →
   `frontend.md`; new infra → `operations.md`/`architecture.md`; scope/priority
   change → `roadmap.md`).
2. Update those pages directly — don't leave stale facts alongside new ones.
3. Append one line to `log.md`: date, what changed, which pages were touched.
4. If a page's summary in `index.md` no longer fits, update it too.

**Query** (before starting a feature):
1. Check `index.md` to find the relevant page(s).
2. Read those pages for current state before touching code.
3. Check `roadmap.md` for whether the feature is already scoped/prioritized.

**Lint** (periodically, or when something feels off):
- Look for pages that contradict each other or the actual code.
- Look for `roadmap.md` items marked TODO that are actually done (or vice versa).
- Look for orphaned pages not listed in `index.md`.

## Conventions

- Plain Markdown, one topic per file, files stay under repo root `wiki/`.
- Every page states facts as they are *now* — no speculative content unless it's
  explicitly in `roadmap.md` under a "planned" heading.
- Prefer short, factual, skimmable sections over prose.
- Status tags used in `roadmap.md`: `done`, `in progress`, `todo`.
