# Health knowledge database

Standalone PostgreSQL 16 package in [`db/`](../db/README.md): schema, demonstration
fixtures and a smoke test. **Not integrated into the backend.** Why it is shaped
this way: `decisions.md`. Planned integration and API: `roadmap.md`.

The SQL in `db/init/` is the source of truth for tables and columns; this page
only summarizes. Use `COMMENT ON` in SQL for per-column explanations.

## Run

- `docker compose -f db/compose.yml up -d --wait` from repo root; separate Compose
  project and volume from the root stack, bound to `127.0.0.1:55432`
  (`TERVISEHULL_DB_PORT` overrides). Database/user `tervisehull`.
- Init scripts run once, in order, on an empty volume: `001_schema.sql` (tables,
  constraints, views, matcher), `002_seed_smoke_data.sql` (workbook-derived
  fixtures), `003_enrich_evidence_sources.sql` (PMID/PMCID/DOI metadata).
  Rerunning them never upgrades an existing volume.
- Smoke test: `db/tests/smoke.sql`, command in `db/README.md`. Needs a fresh
  fixture DB; all temporary changes are rolled back. Not run in CI.

## Contents

40 tables, 100 interaction rules, 300 evidence sources (30 resolved articles,
270 `search_only` links awaiting review), 139 concepts, 750 aliases, `en`/`et`
translation rows (the `en` rows currently hold Estonian placeholder text) and six
fixture users. All approval/publication flags in the seed are synthetic — not
medical approval.

| Area | Tables |
|---|---|
| Accounts | `user_roles`, `users`, `user_sessions` |
| Reference | `units`, `data_sources`, `locales`, `countries`, `translation_keys`, `translations` |
| Canonical content | `health_concepts`, `concept_aliases`, `concept_relationships`, `drug_products`, `drug_product_aliases`, `drug_product_ingredients` |
| Evidence | `evidence_sources`, `interaction_rule_sources`, `rule_condition_sources`, `rule_risk_modifier_sources` |
| Rules | `risk_levels`, `interaction_rules`, `interaction_rule_participants`, `rule_condition_groups`, `rule_conditions`, `interaction_rule_copy`, `timing_recommendations`, `profile_risk_factors`, `rule_risk_modifiers` |
| User profile | `user_demographics`, `user_profile_items`, `user_conditions`, `user_observations`, `user_profile_flags`, `measurement_types`, `measurement_type_units`, `user_measurement_events`, `user_measurements` |
| Review / audit | `review_tasks`, `review_decisions`, `content_audit_log` |

Keys: internal `bigint` identity PKs/FKs, `uid uuid` for external references,
workbook IDs (`RULE_0001`, `SRC_0001_1`) as text trace fields.

## Publication gate and matcher (current behaviour)

- `public_interaction_rule_eligibility` (view) lists rules that are published,
  medical- and copy-approved, have ≥2 required participants, approved `et` and
  `en` copy, at least one approved evidence source, only approved conditions and
  timing, and direct approved evidence for numeric thresholds. It only reports —
  nothing prevents setting `publication_status = 'published'` on an ineligible rule.
- `public_rule_matches_for_user(user_id, locale_id)` matches eligible rules whose
  required participant concepts all appear among the user's current
  (`is_current`) profile items — exact concept match only.
- **Not evaluated:** conditions/thresholds, measurements, product → ingredient
  expansion, concept descendants, personal risk modifiers. Do not use it as a
  clinical assessment.
- `user_public_rule_matches` and `user_public_rule_matches_localized` are legacy
  diagnostic views; they must not serve user output.

## Relationship to the backend

The backend owns its own schema via Flyway (`V1`–`V3`, `ddl-auto=validate`).
This package has a different `users` table and does not follow the backend's
audit-column rule (`created_by`/`updated_by` missing everywhere). Do not point the
backend at this database. Integration needs an explicit decision on users,
identifiers, ownership and audit columns — see `roadmap.md`.
