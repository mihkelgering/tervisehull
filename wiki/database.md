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
  medically approved, have ≥2 distinct required participant concepts,
  all of them `published` with `can_trigger_matching`, approved complete copy
  (title, risk label, headline, explanation, prompt) in every active locale
  with `is_mvp_required = true` (currently `et` and `en`), at least one approved
  evidence source, only approved conditions and timing, direct approved evidence
  for numeric thresholds, and every non-retired risk modifier approved with
  approved evidence and approved condition groups/conditions.
- **Enforced on publish:** a row CHECK requires medical approval for
  `publication_status = 'published'`, and a deferred constraint trigger
  (`interaction_rules_publication_gate`) refuses to commit a rule inserted or
  updated as published unless it is in the view. Deferral lets a rule and its
  children be written in one transaction (the seed file is one transaction for
  this reason). Later child-row edits that break a published rule are not
  blocked; the view still filters them out at read time.
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
This package has a different `users` table. Do not point the backend at this
database. Integration needs an explicit decision on users, identifiers and
ownership — see `roadmap.md`.

## Languages

Adding a language needs no schema change: insert a `locales` row and its
`translations` / `interaction_rule_copy` rows. Set `is_mvp_required = true` to
make its copy a publication requirement; the eligibility view reads that flag
rather than naming languages. `locales.code` is a BCP 47 subset (`et`, `en-GB`,
`pt-BR`, `zh-Hant`). Matching is language-independent; locale only selects
display copy.

## Copy review status

Copy review is tracked only per locale, in `interaction_rule_copy.review_status`.
There is no rule-level copy status (`interaction_rules.copy_review_status` was
dropped: it duplicated the per-locale value with a different vocabulary and could
disagree with it). For a per-rule "copy approved" figure, derive it: every
required locale's copy row is `approved`.

## Audit columns

Every table follows the standing rule (see `backend.md`): `created_at`,
`created_by`, `updated_at`, `updated_by`, emitted as the last columns of each
table. `created_by`/`updated_by` are nullable `bigint` logical references to
`users.id` with no FK, matching the backend. A `set_updated_at()` trigger is
attached to every table with an `updated_at` column (discovered dynamically at
the end of `001_schema.sql`, not a hand-kept list). Seed users self-reference
their own id; other seed rows leave `created_by`/`updated_by` NULL. The smoke
test asserts all four columns and the trigger exist on every table and that an
UPDATE succeeds on each.
