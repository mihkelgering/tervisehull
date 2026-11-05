# Tervisehull Database

Standalone PostgreSQL 16 schema and demonstration data for the health knowledge
model. It includes 40 tables, 100 interaction rules, 300 evidence-source records,
139 concepts, 750 aliases, English/Estonian translation rows, and six fixture users.
Internal primary/foreign keys are integers; externally addressable records also
have UUIDs. See [the data model](docs/data-model.md) for relationships and decisions.

## Scope

This package is independent of the repository's existing backend/frontend and
root Compose stack. The backend's existing Flyway V1-V3 migrations define a
different `users` table. Do not point that backend at this database or run these
SQL files against its database. Reconciling those schemas is separate work.

These are development fixtures. Seed approval/publication flags and reviewer
records exercise database behavior; they do not establish medical approval.
Some English translations still contain Estonian fallback text. The legacy SQL
matcher handles exact concept pairs and publication gates, but does not evaluate
dose thresholds, measurements, conditions, product ingredients, or personal risk
modifiers. It must not be used as a complete clinical assessment service.

## Start a Fresh Database

From the repository root:

```bash
docker compose -f db/compose.yml up -d --wait
```

The numbered files in `init/` execute once, in order, on an empty volume:

| File | Purpose |
| --- | --- |
| `001_schema.sql` | Tables, constraints, indexes, views and diagnostic matcher |
| `002_seed_smoke_data.sql` | Imported workbook content and synthetic profiles |
| `003_enrich_evidence_sources.sql` | Publication identifiers and metadata |

This setup requires no backend build, spreadsheet libraries or network lookup
after the PostgreSQL image is available. Initialization can take a few seconds
beyond initial server startup; run the smoke test below to confirm completion.

The Compose project has its own persistent volume. It does not automatically
attach a pre-existing database. If a database is already available on port 55432,
connect to it directly, or use `TERVISEHULL_DB_PORT=55434` for this separate instance.
Optional overrides are documented in `.env.example`; load a private file with
`docker compose --env-file db/.env -f db/compose.yml up -d --wait`.

## DataGrip Connection

| Setting | Value |
| --- | --- |
| Host | `localhost` |
| Port | `55432` (or `TERVISEHULL_DB_PORT`) |
| Database | `tervisehull` |
| User | `tervisehull` |
| Local development password | `tervisehull_dev_password` (or `TERVISEHULL_DB_PASSWORD`) |
| JDBC URL | `jdbc:postgresql://localhost:55432/tervisehull` |

## Verify

Run against a fresh fixture database. The test checks population, source metadata,
both locales, matching/nonmatching profiles, sequence allocation, and publication
gates. Temporary updates are rolled back.

```bash
docker compose -f db/compose.yml exec -T postgres \
  psql -X -v ON_ERROR_STOP=1 -U tervisehull -d tervisehull < db/tests/smoke.sql
```

Useful inspection queries:

```sql
SELECT * FROM evidence_sources ORDER BY public_id;
SELECT * FROM public_interaction_rule_eligibility;
SELECT * FROM public_rule_matches_for_user(
  101, (SELECT id FROM locales WHERE code = 'en')
);
SELECT tk.id AS text_id, tk.key, l.code AS locale, tr.text
FROM translation_keys tk
JOIN translations tr ON tr.text_id = tk.id
JOIN locales l ON l.id = tr.locale_id
ORDER BY tk.id, l.code;
```

## Preserve State

`docker compose -f db/compose.yml down` stops this package and keeps its volume.
Do not use `down -v` for routine upgrades. Changing `POSTGRES_DB`, `POSTGRES_USER`
or `POSTGRES_PASSWORD` in Compose does not rename or update an initialized database.
Use PostgreSQL administration commands for existing database/role changes.

For a private local backup:

```bash
mkdir -p db/backups
docker compose -f db/compose.yml exec -T postgres \
  pg_dump -U tervisehull -d tervisehull --format=custom > db/backups/tervisehull.dump
```

Backups, live account data and credentials do not belong in Git. The checked-in
SQL recreates fixtures with newly generated UUIDs and timestamps; it is not a dump
of an individual's current database. Restore a backup to a separate empty database
when exact state is required. Existing installations are never upgraded by rerunning
these bootstrap scripts; use explicit forward migrations for subsequent changes.

## Evidence Metadata

[The metadata record](docs/evidence-source-metadata.json) records the enrichment
of 30 concrete article rows: 29 have a PMID, 10 a PMCID, 26 a DOI, and 30 journal/year
metadata. The other 270 rows are search URLs marked `search_only` and `needs_review`.
Metadata resolution is not evidence verification. One duplicate article remains as
two source records with duplicate PMID/DOI omitted on one row; source consolidation
and clinical review remain outstanding. Original authoring workbooks and the
application's separate import tooling are not part of this database-only package.
