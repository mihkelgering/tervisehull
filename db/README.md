# Tervisehull Database

Standalone PostgreSQL 16 schema and content for the health knowledge model:
the catalog (concepts, aliases, products, units, locales, risk levels) with six
synthetic fixture users, and the interaction content imported from the medical
doctors' workbook (19 topics, 138 rules, 104 evidence sources, 237 findings).
Internal primary/foreign keys are integers; externally addressable records also
have UUIDs. Data model, decisions and plans live in the wiki:
[`wiki/database.md`](../wiki/database.md), [`wiki/decisions.md`](../wiki/decisions.md)
and [`wiki/roadmap.md`](../wiki/roadmap.md).

## Scope

This package is independent of the repository's existing backend/frontend and
root Compose stack. The backend's existing Flyway V1-V3 migrations define a
different `users` table. Do not point that backend at this database or run these
SQL files against its database. Reconciling those schemas is separate work.

Nothing in the imported content is approved or publishable: every rule carries
the `review` risk level ("Not assessed"), `medical_review_status = 'not_started'`
and `publication_status = 'draft'`; sources are `imported`; new concepts are
`draft`; there is no patient-facing copy and no English text. The fixture users
and the catalog's approval flags are synthetic and exercise database behaviour
only. The legacy SQL matcher handles exact concept pairs and publication gates,
but does not evaluate dose thresholds, measurements, conditions, product
ingredients, or personal risk modifiers. It must not be used as a clinical
assessment service.

## Start a Fresh Database

From the repository root:

```bash
docker compose -f db/compose.yml up -d --wait
```

The numbered files in `init/` execute once, in order, on an empty volume:

| File | Purpose |
| --- | --- |
| `001_schema.sql` | Tables, constraints, indexes, views and diagnostic matcher |
| `002_seed_smoke_data.sql` | Catalog and reference data, six fixture users with profiles |
| `004_md_workbook_schema.sql` | Forward migration: topics, evidence findings, structured timing, participant alternatives, formulation concepts (MD workbook support) |
| `005_md_workbook_fixtures.sql` | Extra units; the `review` risk level never publishes |
| `006_md_workbook_import.sql` | **Generated.** The MD workbook content: concept fixes, topics, rules, participants, sources, findings, timing |

This setup requires no backend build, spreadsheet libraries or network lookup
after the PostgreSQL image is available. The healthcheck connects over TCP, which
the entrypoint's temporary init server does not accept, so `--wait` returns only
after the init scripts have finished.

The Compose project has its own persistent volume. It does not automatically
attach a pre-existing database. If a database is already available on port 55432,
connect to it directly, or use `TERVISEHULL_DB_PORT=55434` for this separate instance.
Optional overrides are documented in `.env.example`; load a private file with
`docker compose --env-file db/.env -f db/compose.yml up -d --wait`.

## Workbook import (`tools/`)

`006_md_workbook_import.sql` is generated from the MD interaction workbook
(`medical-doctor-input*.xlsx`, tabs marked `CICILY_MD_INTERACTION_V2`) by
`tools/import_md_workbook.py`. Do not edit the SQL by hand; change the overrides
or the workbook and regenerate. The script needs only the Python standard library.
Run it in isolated mode from the repository root with the workbook copied to an
empty folder outside the repository (it is untrusted input):

```bash
python3 -I db/tools/import_md_workbook.py /path/to/scratch/medical-doctor-input.xlsx
```

It reads the catalog from `002_seed_smoke_data.sql`, resolves every workbook
factor name (exact display name, then alias, then the overrides file), and
refuses to run when a name is unresolved or would silently match a combined
seed concept. It writes:

- `init/006_md_workbook_import.sql` — one transaction, explicit ids in ranges
  above the seed's, `setval` at the end.
- `tools/md_workbook_concept_map.csv` — every factor name with its resolution
  (existing concept, new draft concept, formulation, or a list of alternatives),
  which seed aliases were re-pointed or rejected, the relationships added, and
  the retyped seed concepts. Review this file when the workbook changes.

`tools/md_workbook_overrides.json` holds every hand-reviewed decision the script
cannot derive: names that need a new concept (with its type), formulations
(decision #23), splits of combined seed concepts (`Amlodipiin / nifedipiin /
felodipiin` and the like become one concept per member, the member alias moves
with it, and a `narrower_than` or `is_a` relationship records the split), the
seed aliases that pointed at the wrong concept, retypes (`Naistepuna` →
supplement, `Alkohol` → lifestyle factor, `Hormonaalsed kontratseptiivid` and the
seed's "Group: member/member" concepts → `drug_group`), the structured reading of
each "Tühja kõhuga" / "Päevaaeg" instruction (`timing_recommendations` typed
columns; the instruction text itself is always stored), and the ten evidence
rows whose cells state an effect number plainly. Everything else in the workbook
is stored as written: topic summaries, case scope/conditions/conclusion (with the
labelled "Olulisus" and "Arvuline mõju" parts also split out), and every Evidence
row as an `evidence_findings` row linked to its case. Sources are deduplicated by
lower-cased DOI, then PMID or PMCID parsed from the link, then URL; `source_type`
comes from the host (SmPC, PIL, DailyMed/FDA label, EMA, NHS/FDA guidance,
PubMed, PMC, `other` for bare DOIs) and titles are the citation text as written.

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

Run against a fresh database. The test first checks the imported state read-only
(population, identifiers, nothing publishable, no demo content, sequences), then
builds two throwaway rules that pass the publication gate (approved copy in both
locales, approved sources, published concepts the fixture users hold, an approved
risk modifier with a measurement condition) and runs the row-constraint, gate,
workbook-support, locale and matching checks against them. Everything is rolled
back. CI runs the same steps on every pull request that touches `db/`
(`.github/workflows/db-smoke.yml`).

```bash
docker compose -f db/compose.yml exec -T postgres \
  psql -X -v ON_ERROR_STOP=1 -U tervisehull -d tervisehull < db/tests/smoke.sql
```

Useful inspection queries:

```sql
SELECT t.public_id, t.source_workbook_sheet, count(r.id) AS rules
FROM interaction_topics t LEFT JOIN interaction_rules r ON r.topic_id = t.id
GROUP BY t.id ORDER BY t.id;
SELECT r.public_id, r.source_workbook_case_name, c.public_id AS concept, p.participant_role, p.alternative_group
FROM interaction_rules r
JOIN interaction_rule_participants p ON p.interaction_rule_id = r.id
JOIN health_concepts c ON c.id = p.concept_id
ORDER BY r.id, p.id;
SELECT * FROM evidence_findings WHERE effect_value IS NOT NULL;
SELECT * FROM public_interaction_rule_eligibility;  -- empty until content is reviewed
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
SQL recreates the content with newly generated UUIDs and timestamps; it is not a
dump of an individual's current database. Restore a backup to a separate empty
database when exact state is required. Existing installations are never upgraded
by rerunning these bootstrap scripts; use explicit forward migrations for
subsequent changes. The workbook itself is not part of this package.
