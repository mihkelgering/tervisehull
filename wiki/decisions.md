# Decisions — health knowledge model

Accepted product and data-model decisions behind the health knowledge database
(`database.md`). Each entry states the decision and the tension it resolves.
Planned work that follows from these lives in `roadmap.md`.

## Product boundary (MVP)

The app supports safety information and GP/pharmacist conversations, not clinical
orders. It may flag possible interactions, explain why they matter and say when a
user's profile makes one worth discussing. It must never tell a user to start,
stop, replace or change the dose of a medicine or supplement.

- **Allowed:** "This interaction may be more relevant for people with kidney
  disease. Discuss this with your GP, pharmacist, or prescribing clinician."
- **Not allowed:** "Increase your dose." / "Stop taking this." / "This is unsafe
  for you." / "Your blood pressure is dangerously high."

Personal data changes *relevance*, never instructions: it produces evidence-backed
"personal relevance flags" and conversation prompts only.

## Starting experience (2026-10-29)

- A saved personal profile is the starting experience (supersedes the UX draft's
  guest pair checker). No free-tier limits; packaging decided later.
- Onboarding collects language preference, optional birth year and current
  medicines/supplements. No exact birth date, sex, conditions or pregnancy status
  required. An empty list is valid; everything stays editable.
- Selections reference published catalog entries; unrecognized names may be saved
  as unmatched entries. A catalog match identifies an item — it is not a safety
  verdict.

## Data model decisions

| # | Decision | Resolution |
|---|---|---|
| 1 | Personal-risk flagging | Evidence-backed `rule_risk_modifiers`, shown as relevance flags with sources. |
| 2 | Race / ethnicity / ancestry, pharmacogenomics | Optional self-reported descriptors, separate from PGx results, explicit consent, source-backed flags only; prefer exact clinical factors. Future-gated: not in MVP APIs or migrations. |
| 3 | Pregnancy / lactation | Time-bound `user_observations`, not static demographics. |
| 4 | Quantitative conditions | `rule_condition_groups` + `rule_conditions` over doses, measurements, observations, profile flags. Output stays "worth discussing". |
| 5 | Canonical concept hub | Everything searchable/matchable lives in `health_concepts` with a controlled `concept_type`; rules never get per-type nullable FK columns; combined spreadsheet labels are split. |
| 6 | Brands vs active ingredients | `drug_products` → `drug_product_ingredients` → active-substance concepts. Rules target substances; a selected product expands to its ingredients. |
| 7 | Product fields and booleans | Keep `drug_products` simple (no registry columns yet). Two-state facts are booleans named `is_*` / `has_*` / `can_*`; `status` only for 3+ lifecycle states. |
| 8 | Search lanes | UI asks what is being added (medication, supplement, food/drink, condition, observation, measurement) and searches only that lane. Global search is an admin/debug fallback. |
| 9 | Evidence sources | `evidence_sources` (not "articles") covers publications, guidelines, labels, SPC/PIL, registries, internal MD content; linked via rule, condition and modifier join tables. |
| 10 | Rule structure | `interaction_rules` is a thin parent; participants, conditions, copy, timing and evidence are child tables. |
| 11 | Risk levels | Six internal levels with severity order, cautious user labels and escalation booleans (`requires_gp_discussion`, `requires_pharmacist_discussion`, `show_as_blocking_warning`). |
| 12 | Publication gate | Public endpoints return only fully published/approved content: concepts, products, ingredient mappings, aliases, rule, copy, conditions, timing, modifiers and evidence must each pass their gate. Editors/admins may see drafts. |
| 13 | Roles | Only `user`, `editor`, `admin`. Review is workflow state, not roles; approving user is recorded. |
| 14 | Direct publishing | Editors and admins may publish directly; mitigated by strict gates and an immutable `content_audit_log`. |
| 15 | Product market | Estonia only for MVP (`countries.code = EE`), verified against Ravimiregister / Estonian SPC/PIL. Others stay candidates. |
| 16 | MVP scope hardening | Profile covers medicines/supplements/foods/drinks, optional dose/frequency, conditions, observations and blood pressure. Kidney/liver markers, glucose, body metrics, population descriptors and PGx are future-gated. Numeric thresholds need direct approved evidence; matching is exact-unit only (no conversion). |
| 17 | Localization | Display text in `translations(text_id, locale_id, text)` keyed by `translation_keys`; no per-language columns. Required languages are the active `locales` with `is_mvp_required` (MVP: `et`, `en`); locale codes are a BCP 47 subset. |
| 18 | Identifiers | Internal `bigint` identity PKs/FKs; `uid uuid` for external references; sequential IDs never exposed in APIs; workbook IDs (`RULE_0001`, …) kept as text trace fields. |
| 19 | Topics above rules (2026-11-25) | The MD workbook's per-tab summary (what happens, guidance, uncertainty, default risk) lives in `interaction_topics`; rules point at a topic and record whether their risk was inherited from it. Rules stay the unit of matching and publication. |
| 20 | Findings, not notes | A source can give several distinct findings for one case, each with its own limitations, locator, study design and one effect number. `evidence_findings` holds them; `interaction_rule_sources.note` is not the place. Negative findings are first-class (`is_negative_finding`). |
| 21 | Single-drug instructions are rules | "Take on an empty stomach" / "take in the morning" rows are `interaction_rules` with `rule_scope = 'timing_context'` and one participant, so they get the same copy, evidence, review and gate machinery. The gate requires one participant slot for them instead of two. No placeholder "food" concept. |
| 22 | Alternatives in participants | "Any one of these" is `interaction_rule_participants.alternative_group`; matching counts slots, not rows. Group concepts with `is_a` members remain the way to say "every member of the class". |
| 23 | Formulations are concepts | A dosage form, route or strength that changes the guidance is a `formulation` concept (`is_a` its substance) with the qualifier columns, not a product and not a text note on the rule. |
| 24 | Workbook is the content (2026-11-25) | The MD workbook replaces the demo rules. Import is a generated SQL file plus a hand-reviewed overrides file and a generated resolution map; factor names resolve exact → alias → override, never silently to a combined concept (those are split, member aliases move, a `narrower_than`/`is_a` relationship records it). Imported rows stay unpublishable (`review` risk, draft, `imported`), MD text is stored as written in `et` only, and numbers are typed only where a cell states them plainly. |

Conventions that follow:

- FK delete behaviour: `cascade` only for user-owned data and children that can't
  exist alone; `restrict` for reviewed medical/evidence content; prefer `retired`
  status over hard deletes.
- Dependency direction: profile → content, rules → content + evidence; content and
  evidence never reference user data.

## Contradiction log

| ID | Tension | Resolution |
|---|---|---|
| C001 | Personalized warnings vs no personalized advice | Relevance flags + conversation prompts only. |
| C002 | Store dose/frequency vs no dose recommendations | Stored as user context; never drives dose output. |
| C003 | Sources mention race, but race is not a dosing variable | Optional self-reported descriptors, source-backed flags only. |
| C004 | Pregnancy is important but not a stable demographic | Time-bound observations. |
| C005 | Thresholds vs looking like diagnosis | Reviewed conditions; output stays "worth discussing". |
| C006 | Central concept table vs junk drawer | Strict `concept_type`, statuses, aliases, relationships, review. |
| C007 | Users search brands, rules target substances | Products + ingredient mapping + expansion. |
| C008 | Product verification later vs unused registry columns | Simple `drug_products`; provenance in source tables later. |
| C009 | `status` fields that are really booleans | Explicitly named booleans. |
| C010 | Global search vs mixed result types | Context-specific lanes. |
| C011 | "Articles" too narrow | `evidence_sources`. |
| C012 | Thin rule parent = more joins | Accepted; child tables evolve independently. |
| C013 | Severity labels read as diagnosis | Internal ordering + careful labels + prompts. |
| C014 | Strict gates slow content work | Accepted; public output never uses drafts. |
| C015 | Review gates vs many roles | Three roles; review as workflow state. |
| C016 | Editors publishing weakens separation | Allowed; strict gates + immutable audit log. |
| C017 | Estonia-only vs international brands | EE catalog; others candidates. |
| C018 | Population/PGx useful but privacy-heavy | Documented, not in MVP. |
| C019 | Unit conversion can cause false matches | Exact-unit only for MVP. |
| C020 | Bilingual launch vs brittle language columns | Single translation table. |
| C021 | UUID PKs vs bigint joins | bigint PKs + `uid` UUIDs. |

## Security and privacy

- Medicines, supplements, diagnoses, measurements, pregnancy status, risk flags,
  population descriptors and PGx results are sensitive data.
- Health, genetic and race/ethnicity data need explicit consent before use in
  matching; never infer them from indirect signals.
- HTTP-only, same-site, secure session cookies; HTTPS everywhere; never log raw
  profile payloads.
- Audit editor/admin access to sensitive content and user profiles.
- Account deletion removes or anonymizes profile data; aggregate content logs kept
  where legally allowed.
