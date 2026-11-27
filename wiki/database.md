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
  constraints, views, matcher), `002_seed_smoke_data.sql` (catalog, reference
  data, six fixture users), `004_md_workbook_schema.sql` (forward migration: MD
  workbook support, see below), `005_md_workbook_fixtures.sql` (extra units,
  `review` risk level unpublishable), `006_md_workbook_import.sql` (generated:
  the MD workbook content, see "Workbook import"). There is no `003` any more:
  the demo rules and their enrichment were removed on 2026-11-25. Rerunning the
  scripts never upgrades an existing volume; `004`–`006` can be applied to one
  with `psql` since they only add or alter in place.
- Smoke test: `db/tests/smoke.sql`, command in `db/README.md`. Needs a fresh
  fixture DB; all temporary changes are rolled back. Runs in CI on changes to `db/**`
  (`.github/workflows/db-smoke.yml`, see `operations.md`).

## Contents

42 tables. Catalog from the seed: 139 concepts, 750 aliases, one Estonian drug
product, 8 profile risk factors, one measurement type, `en`/`et` translation rows
(the `en` concept names currently repeat the Estonian text) and six fixture users
with profiles. Content from the MD workbook import (`006`): 19 topics, 138 rules
(28 of them single-drug `timing_context` instructions), 262 participants (21 in
"any one of these" groups), 104 evidence sources (30 DOIs, 30 PMIDs, 1 PMCID;
31 SmPCs, 2 PILs, 6 DailyMed/FDA labels, 1 EMA, 6 NHS/FDA guidance pages, the
rest journal articles), 191 rule–source links, 237 evidence findings (10 with a
typed effect number), 35 timing rows (21 with a minute window), 95 new draft
concepts (9 formulations) with 83 added and 30 re-pointed aliases, 66 draft
relationships, 16 retyped and 10 rejected seed rows. No rule is publishable:
all carry the `review` risk level, are `draft` and `not_started`, and have no
copy and no English text. The seed's catalog approval flags are synthetic.

| Area | Tables |
|---|---|
| Accounts | `user_roles`, `users`, `user_sessions` |
| Reference | `units`, `data_sources`, `locales`, `countries`, `translation_keys`, `translations` |
| Canonical content | `health_concepts`, `concept_aliases`, `concept_relationships`, `drug_products`, `drug_product_aliases`, `drug_product_ingredients` |
| Evidence | `evidence_sources`, `interaction_rule_sources`, `evidence_findings`, `rule_condition_sources`, `rule_risk_modifier_sources` |
| Rules | `risk_levels`, `interaction_topics`, `interaction_rules`, `interaction_rule_participants`, `rule_condition_groups`, `rule_conditions`, `interaction_rule_copy`, `timing_recommendations`, `profile_risk_factors`, `rule_risk_modifiers` |
| User profile | `user_demographics`, `user_profile_items`, `user_conditions`, `user_observations`, `user_profile_flags`, `measurement_types`, `measurement_type_units`, `user_measurement_events`, `user_measurements` |
| Review / audit | `review_tasks`, `review_decisions`, `content_audit_log` |

Keys: internal `bigint` identity PKs/FKs, `uid uuid` for external references,
public ids (`RULE_0001`, `SRC_0001`, `TOPIC_0001`) plus the workbook sheet and
case name as text trace fields.

## Publication gate and matcher (current behaviour)

- `public_interaction_rule_eligibility` (view) lists rules that are published,
  medically approved, have a publishable base risk level (`risk_levels.can_publish`;
  `review` = the workbook's "Not assessed" never publishes), have ≥2 required
  participant *slots* and ≥2 distinct required concepts (≥1 of each when
  `rule_scope = 'timing_context'`, an instruction for one drug), all participant
  concepts `published` with `can_trigger_matching`, approved complete copy
  (title, risk label, headline, explanation, prompt) in every active locale
  with `is_mvp_required = true` (currently `et` and `en`), at least one approved
  evidence source, every non-retired evidence finding approved, only approved
  conditions and timing, direct approved evidence for numeric thresholds, and
  every non-retired risk modifier approved with approved evidence and approved
  condition groups/conditions.
- **Enforced on publish:** a row CHECK requires medical approval for
  `publication_status = 'published'`, and a deferred constraint trigger
  (`interaction_rules_publication_gate`) refuses to commit a rule inserted or
  updated as published unless it is in the view. Deferral lets a rule and its
  children be written in one transaction (the seed file is one transaction for
  this reason). Later child-row edits that break a published rule are not
  blocked; the view still filters them out at read time.
- `public_rule_matches_for_user(user_id, locale_id)` matches eligible rules for
  which every required participant slot has at least one of its concepts among
  the user's current (`is_current`) profile items — exact concept match only.
  A slot is one participant, or all participants of the rule that share an
  `alternative_group` ("any one of these"); `rule_required_slots_met(rule_id,
  user_id)` holds the check.
- **Not evaluated:** conditions/thresholds, measurements, product → ingredient
  expansion, concept descendants, personal risk modifiers, timing windows after
  a drug is stopped. Do not use it as a clinical assessment.
- `user_public_rule_matches` and `user_public_rule_matches_localized` are legacy
  diagnostic views; they must not serve user output.

## Workbook import support (`004_md_workbook_schema.sql`)

Added 2026-11-25 so the MD interaction workbook (`CICILY_MD_INTERACTION_V2`
tabs: topic summary, Cases table, Evidence table) can be imported without
losing content. What each piece holds:

| Workbook | Database |
|---|---|
| One tab: topic, what happens, proposed guidance, when it applies, questions, notes, default risk, factor relation, handoff status, author | `interaction_topics` (texts as translation keys); `interaction_rules.topic_id` |
| One Cases row | `interaction_rules`: `scope_note_text_id`, `conditions_text_id`, `clinical_conclusion_text_id`, `significance_text_id`, `numeric_effect_text_id`, `effect_direction`, `is_risk_inherited_from_topic`; trace `source_workbook_sheet` + `source_workbook_case_name` (unique) |
| One Evidence row (a source can give several per case) | `evidence_findings`: finding, limitations, locator, source guidance, `study_design`, `population`, `sample_size`, one `effect_metric`/`effect_value`/CI/`p_value` per row, `is_negative_finding`, `status`. Composite FK onto `interaction_rule_sources`, so the source must be linked to the rule first |
| "Tühja kõhuga" / "Päevaaeg" rows (instructions for one drug) | `interaction_rules` with `rule_scope = 'timing_context'`, `interaction_type = 'drug_administration'` and one participant; `timing_recommendations` gained `anchor`, `relation`, `min_minutes`/`max_minutes`, `alternative_group`, `time_of_day`, `stay_upright_minutes`, `with_water_ml_min/max`, `requirement_strength`, plus timing types `take_on_empty_stomach`, `take_with_food`, `take_at_time_of_day`, `avoid_after_stopping` |
| "Any one of these" group members | `interaction_rule_participants.alternative_group` |
| Formulation-specific factors ("Levotüroksiin (pehmekapsel)", "Ibandronaat 150 mg") | `health_concepts.concept_type = 'formulation'` with `dosage_form` / `route` / `strength_text` (at least one; only on formulations), linked `is_a` to the substance |
| Supplement–food, supplement–supplement, food–food, drug–lifestyle pairs | new `interaction_type` values |
| Duration and intake-pattern conditions ("long-term PPI use", "binge drinking") | `rule_conditions.condition_kind` `item_duration` (needs unit) and `intake_pattern` (needs `text_value`) |
| Medical approver | `interaction_rules.medical_reviewed_by_user_id`, `medical_reviewed_at` |

Also: `evidence_sources.doi` uniqueness is now on `lower(doi)`;
`interaction_topics` also keeps the tab's "Factor 1 / Factor 2 / Other factors"
descriptions (`factor_1_text_id`, `factor_2_text_id`, `other_factors_text_id`);
`005_md_workbook_fixtures.sql` adds units `ml`, `g`, `ug`, `min`, `h`, `d`,
`glass`, `uk_alcohol_unit`.

## Workbook import (`006_md_workbook_import.sql`)

Done 2026-11-25: the doctors' workbook (`medical-doctor-input*.xlsx`, 19 tabs,
138 cases, 193 evidence rows) is the interaction content; the 100 demo rules,
their 300 search-URL sources, copy, timing, modifiers and conditions are gone.
`006` is generated by `db/tools/import_md_workbook.py` (stdlib only, run with
`python3 -I`, takes the workbook path); `db/README.md` has the command. Inputs
and outputs:

- `db/tools/md_workbook_overrides.json` — hand-reviewed decisions: new concepts
  and their types, formulations, splits of combined seed concepts, alias fixes,
  retypes, the typed reading of each timing instruction, the ten typed effect
  numbers. The script fails when a factor name is unresolved or would silently
  match a combined concept.
- `db/tools/md_workbook_concept_map.csv` — generated: every workbook factor name
  → existing `public_id`, new concept, formulation or alternatives list, with
  alias moves/rejections, relationships and retypes. Review it when the workbook
  changes.

Mapping: tab → `interaction_topics` (`TOPIC_0001`+, all `working_draft`,
default risk `review`); case → `interaction_rules` (`RULE_0001`+, trace
`source_workbook_sheet` + `source_workbook_case_name`, scope/conditions/
conclusion as written, `significance`/`numeric_effect` split from the labelled
conclusion parts, `interaction_type` derived from the participants' categories);
factor → participant (`primary` = factor 1, `interacting_factor` = factor 2;
list-type names such as "Kogu rühm: diasepaam, alprasolaam, …" become one
participant per member in one `alternative_group`; group concepts use
`include_descendants`); "Tühja kõhuga"/"Päevaaeg" rows → `timing_context`
rules with one participant and `timing_recommendations` rows (typed columns only
where the text gives a clear window); Evidence row → `evidence_sources` (dedupe
by lower-cased DOI, else PMID/PMCID from the link, else URL; `source_type` from
the host; `verification_status = 'imported'`; title = citation text as written),
an `interaction_rule_sources` link and one `evidence_findings` row per case the
row applies to. Concept fixes applied by the import: `Naistepuna` → supplement,
`Alkohol` → lifestyle factor, `Hormonaalsed kontratseptiivid` → drug group;
`C-vitamiin`, `Apelsinimahl`, `Kiudained` got their own concepts (the wrong
seed aliases now point there); the `soja`, `lagrits`, `greibimahl` and a few
other nonsense aliases are `rejected`; the "Group: member/member" seed concepts
that received `is_a` members are typed `drug_group`.

Not done by the import (data work, see `roadmap.md`): merging the duplicate
seed substances (`Levotüroksiin` SUB_0004/SUB_0021, `Varfariin`,
`Tsiprofloksatsiin`; the import uses the lower id), membership lists for the
CYP3A4-inhibitor and serotonergic groups, titles/metadata for the 28 bare-DOI
sources, medical review of every imported row, and patient-facing copy in `et`
and `en` (`interaction_rule_copy`), without which nothing can publish.

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

## Row constraints on conditions and values

- `rule_conditions`: `has_concept`/`item_dose`/`item_frequency` need
  `concept_id`, `measurement_value` needs `measurement_type_id`, `profile_flag`
  needs `profile_risk_factor_id`; `between` needs `numeric_min <= numeric_max`
  (and only `between` may set bounds); `lookback_days >= 0`.
- `(measurement_type_id, unit_id)` on `rule_conditions` and `user_measurements`
  must be a pair in `measurement_type_units` (composite FK, checked when both
  are set).
- `rule_risk_modifiers`: `is_true`/`present` take no `condition_value`; other
  operators require one. Whether a modifier has a profile risk factor or
  condition groups is not enforced (cross-table).
- `user_profile_flags`: exactly one of the three value columns;
  `user_measurements`: exactly one of `value_number`/`value_text`. Whether the
  value matches `profile_risk_factors.value_type` is not enforced.

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
the end of `001_schema.sql` and again, for tables still lacking one, at the end
of `004_md_workbook_schema.sql` — not a hand-kept list). Seed users self-reference
their own id; other seed rows leave `created_by`/`updated_by` NULL. The smoke
test asserts all four columns and the trigger exist on every table and that an
UPDATE succeeds on each.
