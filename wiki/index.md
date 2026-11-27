# Wiki index

Living knowledge base for tervisehull. Read `schema.md` first if you're
maintaining this wiki (ingesting new work, querying for context, or linting).

## Product

- [roadmap.md](roadmap.md) — purpose (TBD), target users (TBD), initial work list
  with status, open decisions.

## Technical

- [architecture.md](architecture.md) — monorepo shape, service boundaries,
  deployment topology.
- [backend.md](backend.md) — Spring Boot service: layout, endpoints, config, data
  layer, build/run.
- [database.md](database.md) — standalone health knowledge DB (`db/`): run,
  contents, publication gate and matcher behaviour; not yet integrated.
- [decisions.md](decisions.md) — health knowledge model decisions: product
  boundary, data-model decisions, contradiction log, privacy.
- [frontend.md](frontend.md) — SvelteKit app: layout, config, build/run.
- [operations.md](operations.md) — local dev, env vars, Railway deployment, CI/CD.

## Meta

- [schema.md](schema.md) — how this wiki is maintained (ingest/query/lint).
- [log.md](log.md) — append-only history of wiki changes.
