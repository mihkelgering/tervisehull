# Health knowledge database

The standalone package lives in [`db/`](../db/README.md). It contains 40 tables,
100 demonstration interaction rules, 300 source rows, 139 canonical concepts,
750 aliases, translation rows for `en`/`et`, and six fixture users. Integer keys
connect tables; UUIDs are available for external references.

Start it with `docker compose -f db/compose.yml up -d --wait` and run the smoke
test described in the database README. It uses database/user `tervisehull` and
defaults to localhost port 55432. The Compose project and volume are separate
from the root application stack. An existing local instance on that port can be
inspected directly without starting another one.

This package is not integrated into the current backend. Its `users` table and
schema history differ from the backend's Flyway migrations. Existing tables and
data were preserved; the backend's standard audit-column convention has not been
retroactively applied. Integration needs explicit identifier, ownership and audit
mapping. No application or deployment configuration is changed by this package.

The seed is demonstration content, including synthetic review/publication flags.
The SQL matcher exercises exact concept matches and publication gates; numeric
conditions and personal context are stored but not evaluated. Source metadata
and translations still need content review. See the
[data model](../db/docs/data-model.md) for relationships and recorded decisions.
