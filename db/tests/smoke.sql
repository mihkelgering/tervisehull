\set ON_ERROR_STOP on
-- Smoke test for a fresh build of db/init/001..006. Everything runs in one
-- transaction that is rolled back at the end.
--
-- 1. Imported state, read-only: population, identifiers, nothing publishable,
--    no demo content, sequences.
-- 2. Throwaway fixtures: two rules that pass the publication gate (approved
--    copy in both locales, approved source, published concepts the fixture
--    users hold), plus an approved risk modifier with a measurement condition.
--    No imported rule can publish (the 'review' risk level never does), so the
--    gate and matcher checks below use these.
-- 3. Row constraints, gate, workbook-support, locale and matching checks.
BEGIN;

CREATE FUNCTION pg_temp.th_eligible(p_public_id text) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM public_interaction_rule_eligibility e
    JOIN interaction_rules r ON r.id = e.interaction_rule_id
    WHERE r.public_id = p_public_id
  );
$$;

-- Runs a statement that must fail with the given SQLSTATE condition.
CREATE FUNCTION pg_temp.th_expect_error(p_label text, p_sql text, p_condition text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  got text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got = RETURNED_SQLSTATE;
    IF (p_condition = 'check_violation' AND got = '23514')
       OR (p_condition = 'foreign_key_violation' AND got = '23503')
       OR (p_condition = 'unique_violation' AND got = '23505') THEN
      RETURN;
    END IF;
    RAISE EXCEPTION '%: expected %, got SQLSTATE % (%)', p_label, p_condition, got, SQLERRM;
  END;
  RAISE EXCEPTION '%: invalid row was accepted', p_label;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Imported state (read-only).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  item record;
  next_id bigint;
  max_id bigint;
BEGIN
  IF current_database() <> 'tervisehull' THEN
    RAISE EXCEPTION 'Run against the standalone tervisehull fixture database';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname = 'public') <> 42 THEN
    RAISE EXCEPTION 'Expected 42 base tables';
  END IF;

  -- Catalog and fixture users from 002/005, workbook content from 006.
  IF (SELECT count(*) FROM users) <> 6
     OR (SELECT count(*) FROM health_concepts) <> 234
     OR (SELECT count(*) FROM health_concepts WHERE status = 'draft') <> 95
     OR (SELECT count(*) FROM concept_aliases) <> 833
     OR (SELECT count(*) FROM concept_aliases WHERE status = 'rejected') <> 10
     OR (SELECT count(*) FROM concept_relationships) <> 68
     OR (SELECT count(*) FROM units) <> 10 THEN
    RAISE EXCEPTION 'Unexpected catalog population';
  END IF;
  IF (SELECT count(*) FROM interaction_topics) <> 19
     OR (SELECT count(*) FROM interaction_rules) <> 138
     OR (SELECT count(*) FROM interaction_rules WHERE rule_scope = 'timing_context') <> 28
     OR (SELECT count(*) FROM interaction_rule_participants) <> 262
     OR (SELECT count(*) FROM interaction_rule_sources) <> 191
     OR (SELECT count(*) FROM evidence_findings) <> 237
     OR (SELECT count(*) FROM timing_recommendations) <> 35 THEN
    RAISE EXCEPTION 'Unexpected workbook import population';
  END IF;
  IF (SELECT count(*) FROM evidence_sources) <> 104
     OR (SELECT count(doi) FROM evidence_sources) <> 30
     OR (SELECT count(pmid) FROM evidence_sources) <> 30
     OR (SELECT count(pmcid) FROM evidence_sources) <> 1
     OR EXISTS (SELECT 1 FROM evidence_sources WHERE verification_status <> 'imported')
     OR EXISTS (SELECT 1 FROM evidence_sources WHERE doi IS NOT NULL AND doi <> lower(doi)) THEN
    RAISE EXCEPTION 'Unexpected evidence source population';
  END IF;

  -- No demo content: every rule traces to a workbook case, no search-URL
  -- sources, no copy rows, no risk modifiers or conditions yet.
  IF EXISTS (SELECT 1 FROM interaction_rules WHERE source_workbook_sheet IS NULL OR source_workbook_case_name IS NULL OR topic_id IS NULL)
     OR EXISTS (SELECT 1 FROM evidence_sources WHERE url LIKE '%?term=%' OR public_id ~ '^SRC_[0-9]{4}_[0-9]+$')
     OR EXISTS (SELECT 1 FROM interaction_rule_copy)
     OR EXISTS (SELECT 1 FROM rule_risk_modifiers)
     OR EXISTS (SELECT 1 FROM rule_condition_groups) THEN
    RAISE EXCEPTION 'Demo content or unexpected authored content present';
  END IF;

  -- Nothing imported may publish: review risk level, draft, not reviewed.
  IF EXISTS (SELECT 1 FROM interaction_rules r JOIN risk_levels rl ON rl.id = r.base_risk_level_id
             WHERE rl.code <> 'review' OR NOT r.is_risk_inherited_from_topic
                OR r.publication_status <> 'draft' OR r.medical_review_status <> 'not_started')
     OR EXISTS (SELECT 1 FROM public_interaction_rule_eligibility)
     OR (SELECT can_publish FROM risk_levels WHERE code = 'review')
     OR EXISTS (SELECT 1 FROM evidence_findings WHERE status <> 'draft')
     OR EXISTS (SELECT 1 FROM timing_recommendations WHERE status <> 'draft') THEN
    RAISE EXCEPTION 'Imported content must not be publishable';
  END IF;

  -- Shape: MD text present, Estonian only, timing rules have one slot, others two.
  IF EXISTS (SELECT 1 FROM interaction_rules WHERE clinical_conclusion_text_id IS NULL OR scope_note_text_id IS NULL OR conditions_text_id IS NULL)
     OR EXISTS (SELECT 1 FROM translations t JOIN locales l ON l.id = t.locale_id
                WHERE l.code = 'en' AND t.text_id >= 700000)
     OR EXISTS (
       SELECT 1 FROM interaction_rules r
       WHERE (SELECT count(DISTINCT COALESCE(p.alternative_group::bigint, -p.id)) FROM interaction_rule_participants p WHERE p.interaction_rule_id = r.id)
             <> CASE WHEN r.rule_scope = 'timing_context' THEN 1 ELSE 2 END)
     OR EXISTS (SELECT 1 FROM interaction_rules r WHERE r.rule_scope = 'timing_context'
                AND NOT EXISTS (SELECT 1 FROM timing_recommendations t WHERE t.interaction_rule_id = r.id))
     OR EXISTS (SELECT 1 FROM interaction_rules r WHERE r.rule_scope <> 'timing_context'
                AND EXISTS (SELECT 1 FROM timing_recommendations t WHERE t.interaction_rule_id = r.id))
     OR EXISTS (SELECT 1 FROM interaction_rules r WHERE NOT EXISTS (SELECT 1 FROM interaction_rule_sources s WHERE s.interaction_rule_id = r.id))
     OR EXISTS (SELECT 1 FROM interaction_rule_participants p JOIN health_concepts c ON c.id = p.concept_id
                WHERE c.concept_type = 'formulation' AND num_nonnulls(c.dosage_form, c.route, c.strength_text) = 0) THEN
    RAISE EXCEPTION 'Imported rules have an unexpected shape';
  END IF;
  IF (SELECT count(*) FROM interaction_rule_participants WHERE alternative_group IS NOT NULL) <> 21
     OR (SELECT count(*) FROM health_concepts WHERE concept_type = 'formulation') <> 9
     OR (SELECT count(*) FROM evidence_findings WHERE effect_value IS NOT NULL) <> 10
     OR (SELECT count(*) FROM timing_recommendations WHERE min_minutes IS NOT NULL) <> 21 THEN
    RAISE EXCEPTION 'Unexpected structured import details';
  END IF;

  IF (SELECT array_agg(code::text ORDER BY code) FROM locales) IS DISTINCT FROM ARRAY['en', 'et'] THEN
    RAISE EXCEPTION 'Expected English and Estonian locales';
  END IF;
  IF EXISTS (
    SELECT 1 FROM users
    WHERE created_by IS DISTINCT FROM id OR updated_by IS DISTINCT FROM id
  ) THEN
    RAISE EXCEPTION 'Seed users must self-reference created_by/updated_by';
  END IF;

  -- Every identity sequence sits above the explicit ids the init files used.
  FOR item IN
    SELECT table_name, column_name,
           pg_get_serial_sequence(format('%I.%I', table_schema, table_name), column_name) AS sequence_name
    FROM information_schema.columns WHERE table_schema = 'public' AND is_identity = 'YES'
  LOOP
    EXECUTE format('SELECT last_value + CASE WHEN is_called THEN 1 ELSE 0 END FROM %s', item.sequence_name)
      INTO next_id;
    EXECUTE format('SELECT COALESCE(max(%I), 0) FROM public.%I', item.column_name, item.table_name) INTO max_id;
    IF next_id <= max_id THEN
      RAISE EXCEPTION 'Sequence % would collide with existing IDs', item.sequence_name;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Throwaway fixtures (rolled back with the transaction).
--    SMOKE_RULE_A: warfarin (SUB_0001) + vitamin K greens (ITEM_0001), held by
--    user 101 (and warfarin alone by 104). SMOKE_RULE_B: simvastatin
--    (SUB_0002) + grapefruit (ITEM_0002), held by 102 (simvastatin alone by 103).
-- ---------------------------------------------------------------------------
INSERT INTO translation_keys (id, key)
VALUES
  (990001, 'smoke.rule_a.title'), (990002, 'smoke.rule_a.headline'), (990003, 'smoke.rule_a.explanation'),
  (990004, 'smoke.rule_a.prompt'), (990005, 'smoke.rule_a.timing'),
  (990011, 'smoke.rule_b.title'), (990012, 'smoke.rule_b.headline'), (990013, 'smoke.rule_b.explanation'),
  (990014, 'smoke.rule_b.prompt'),
  (990021, 'smoke.modifier.flag_title'), (990022, 'smoke.modifier.extra_warning'), (990023, 'smoke.modifier.clinician_note');

INSERT INTO translations (text_id, locale_id, text)
SELECT k.id, l.id, 'smoke ' || k.key || ' ' || l.code
FROM translation_keys k CROSS JOIN locales l
WHERE k.id BETWEEN 990001 AND 990023;

INSERT INTO evidence_sources (id, public_id, title, source_type, evidence_grade, verification_status, reviewed_by_user_id, reviewed_at)
VALUES
  (990001, 'SMOKE_SRC_A', 'Smoke fixture source A', 'other', 'unknown', 'approved', 2, now()),
  (990002, 'SMOKE_SRC_B', 'Smoke fixture source B', 'other', 'unknown', 'approved', 2, now());

INSERT INTO interaction_rules (id, public_id, title_text_id, interaction_type, rule_scope, base_risk_level_id, medical_review_status, publication_status)
VALUES
  (990001, 'SMOKE_RULE_A', 990001, 'drug_food', 'general_interaction', (SELECT id FROM risk_levels WHERE code = 'high'), 'approved', 'published'),
  (990002, 'SMOKE_RULE_B', 990011, 'drug_food', 'general_interaction', (SELECT id FROM risk_levels WHERE code = 'high'), 'approved', 'published');

INSERT INTO interaction_rule_participants (id, interaction_rule_id, concept_id, participant_role, match_scope, required_for_match)
VALUES
  (990001, 990001, 1001, 'primary', 'exact_concept', true),
  (990002, 990001, 2001, 'interacting_factor', 'exact_concept', true),
  (990003, 990002, 1002, 'primary', 'exact_concept', true),
  (990004, 990002, 2002, 'interacting_factor', 'exact_concept', true);

INSERT INTO interaction_rule_sources (interaction_rule_id, evidence_source_id, source_order, evidence_role)
VALUES (990001, 990001, 1, 'primary_support'), (990002, 990002, 1, 'primary_support');

INSERT INTO interaction_rule_copy (id, interaction_rule_id, locale_id, headline_text_id, one_sentence_explanation_text_id, conversation_prompt_text_id, review_status, reviewed_by_user_id, reviewed_at)
SELECT 990000 + r.n * 10 + l.id, r.rule_id, l.id, r.headline, r.explanation, r.prompt, 'approved', 2, now()
FROM (VALUES (1, 990001, 990002, 990003, 990004), (2, 990002, 990012, 990013, 990014)) AS r(n, rule_id, headline, explanation, prompt)
CROSS JOIN locales l;

INSERT INTO timing_recommendations (id, interaction_rule_id, timing_type, instruction_text_id, status, anchor, relation, min_minutes, requirement_strength)
VALUES (990001, 990001, 'separate_or_wait_time', 990005, 'approved', 'the_other_factor', 'before_or_after', 240, 'label_recommendation');

-- An approved modifier on SMOKE_RULE_B with an approved measurement condition
-- (systolic BP >= 140 mmHg), mirroring what a reviewed personal-risk flag looks like.
INSERT INTO rule_risk_modifiers (id, interaction_rule_id, profile_risk_factor_id, condition_operator, condition_value, risk_change, personal_flag_title_text_id, extra_warning_text_id, clinician_note_text_id, status)
VALUES (990001, 990002, 8006, 'present', NULL, 'add_personal_flag_only', 990021, 990022, 990023, 'approved');

INSERT INTO rule_risk_modifier_sources (rule_risk_modifier_id, evidence_source_id, source_order, evidence_role, evidence_summary)
VALUES (990001, 990002, 1, 'personal_risk_support', 'Smoke fixture.');

INSERT INTO rule_condition_groups (id, rule_risk_modifier_id, group_operator, sort_order, status)
VALUES (990001, 990001, 'all', 1, 'approved');

INSERT INTO rule_conditions (id, condition_group_id, condition_kind, measurement_type_id, operator, numeric_value, unit_id, quantity_basis, lookback_days, status)
VALUES (990001, 990001, 'measurement_value', 8401, 'greater_than_or_equal', 140, 2, 'latest_value', 30, 'approved');

INSERT INTO rule_condition_sources (rule_condition_id, evidence_source_id, source_order, evidence_role, evidence_summary)
VALUES (990001, 990002, 1, 'measurement_threshold_support', 'Smoke fixture.');

-- The deferred publication gate fires now, while both fixtures are complete:
-- a failure here means the gate rejects a rule that meets every condition.
SET CONSTRAINTS interaction_rules_publication_gate IMMEDIATE;
SET CONSTRAINTS interaction_rules_publication_gate DEFERRED;

DO $$
BEGIN
  IF NOT pg_temp.th_eligible('SMOKE_RULE_A') OR NOT pg_temp.th_eligible('SMOKE_RULE_B') THEN
    RAISE EXCEPTION 'Throwaway fixtures should be eligible';
  END IF;
  IF (SELECT count(*) FROM public_interaction_rule_eligibility) <> 2 THEN
    RAISE EXCEPTION 'Only the throwaway fixtures may be eligible';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Condition and value constraints (review item 8).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  grp bigint := (SELECT min(id) FROM rule_condition_groups);
  mtype bigint := (SELECT min(measurement_type_id) FROM measurement_type_units);
  ok_unit bigint;
  bad_unit bigint;
  concept bigint := (SELECT min(id) FROM health_concepts);
  base text;
BEGIN
  SELECT min(unit_id) INTO ok_unit FROM measurement_type_units WHERE measurement_type_id = mtype;
  SELECT min(id) INTO bad_unit FROM units
  WHERE id NOT IN (SELECT unit_id FROM measurement_type_units WHERE measurement_type_id = mtype);
  IF bad_unit IS NULL THEN
    RAISE EXCEPTION 'Fixtures need a unit not allowed for measurement type %', mtype;
  END IF;
  base := 'INSERT INTO rule_conditions (condition_group_id, condition_kind, concept_id, measurement_type_id, operator, numeric_value, numeric_min, numeric_max, unit_id, lookback_days, status) VALUES (' || grp || ', ';

  PERFORM pg_temp.th_expect_error('between without bounds',
    base || format('''measurement_value'', NULL, %s, ''between'', NULL, NULL, NULL, %s, NULL, ''draft'')', mtype, ok_unit), 'check_violation');
  PERFORM pg_temp.th_expect_error('between with min > max',
    base || format('''measurement_value'', NULL, %s, ''between'', NULL, 10, 5, %s, NULL, ''draft'')', mtype, ok_unit), 'check_violation');
  PERFORM pg_temp.th_expect_error('bounds on a non-between operator',
    base || format('''measurement_value'', NULL, %s, ''greater_than'', 1, 0, 5, %s, NULL, ''draft'')', mtype, ok_unit), 'check_violation');
  PERFORM pg_temp.th_expect_error('has_concept without concept',
    base || '''has_concept'', NULL, NULL, ''exists'', NULL, NULL, NULL, NULL, NULL, ''draft'')', 'check_violation');
  PERFORM pg_temp.th_expect_error('measurement_value without measurement type',
    base || format('''measurement_value'', NULL, NULL, ''greater_than'', 1, NULL, NULL, %s, NULL, ''draft'')', ok_unit), 'check_violation');
  PERFORM pg_temp.th_expect_error('negative lookback',
    base || format('''has_concept'', %s, NULL, ''exists'', NULL, NULL, NULL, NULL, -1, ''draft'')', concept), 'check_violation');
  PERFORM pg_temp.th_expect_error('unit not allowed for measurement type',
    base || format('''measurement_value'', NULL, %s, ''greater_than'', 1, NULL, NULL, %s, NULL, ''draft'')', mtype, bad_unit), 'foreign_key_violation');
  PERFORM pg_temp.th_expect_error('intake_pattern without text',
    base || format('''intake_pattern'', %s, NULL, ''equals'', NULL, NULL, NULL, NULL, NULL, ''draft'')', concept), 'check_violation');
  PERFORM pg_temp.th_expect_error('item_duration without unit',
    base || format('''item_duration'', %s, NULL, ''greater_than'', 30, NULL, NULL, NULL, NULL, ''draft'')', concept), 'check_violation');

  PERFORM pg_temp.th_expect_error('modifier comparison without value',
    'INSERT INTO rule_risk_modifiers (interaction_rule_id, profile_risk_factor_id, condition_operator, condition_value, risk_change, personal_flag_title_text_id, extra_warning_text_id, clinician_note_text_id, status)
     SELECT interaction_rule_id, profile_risk_factor_id, ''greater_than'', NULL, risk_change, personal_flag_title_text_id, extra_warning_text_id, clinician_note_text_id, ''draft''
     FROM rule_risk_modifiers ORDER BY id LIMIT 1', 'check_violation');
  PERFORM pg_temp.th_expect_error('profile flag without value',
    'UPDATE user_profile_flags SET value_boolean = NULL WHERE user_id = (SELECT min(user_id) FROM user_profile_flags)', 'check_violation');
  PERFORM pg_temp.th_expect_error('profile flag with two values',
    'UPDATE user_profile_flags SET value_text = ''x'' WHERE user_id = (SELECT min(user_id) FROM user_profile_flags)', 'check_violation');
  PERFORM pg_temp.th_expect_error('measurement without value',
    'UPDATE user_measurements SET value_number = NULL WHERE id = (SELECT min(id) FROM user_measurements)', 'check_violation');
  PERFORM pg_temp.th_expect_error('measurement unit not allowed for its type',
    format('UPDATE user_measurements SET unit_id = %s WHERE id = (SELECT min(id) FROM user_measurements WHERE measurement_type_id = %s)', bad_unit, mtype), 'foreign_key_violation');

  -- A valid between condition is still accepted (then undone, so the draft
  -- condition doesn't affect the gate checks below).
  BEGIN
    EXECUTE base || format('''measurement_value'', NULL, %s, ''between'', NULL, 5, 10, %s, 0, ''draft'')', mtype, ok_unit);
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Publication gate. Each case runs in its own block and undoes itself
--    (custom SQLSTATE TH000), starting from the eligible SMOKE_RULE_A.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  rule_pk bigint;
BEGIN
  SELECT id INTO rule_pk FROM interaction_rules WHERE public_id = 'SMOKE_RULE_A';

  -- Published requires medical approval (row CHECK).
  BEGIN
    UPDATE interaction_rules SET medical_review_status = 'in_review' WHERE id = rule_pk;
    RAISE EXCEPTION 'Published rule without medical approval was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- An imported rule cannot be pushed through the gate: the 'review' risk
  -- level blocks it even with medical approval.
  BEGIN
    UPDATE interaction_rules SET medical_review_status = 'approved' WHERE public_id = 'RULE_0001';
    BEGIN
      SET CONSTRAINTS interaction_rules_publication_gate IMMEDIATE;
      UPDATE interaction_rules SET publication_status = 'published' WHERE public_id = 'RULE_0001';
      RAISE EXCEPTION 'Imported rule with the review risk level was published';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- A retired participant concept makes the rule ineligible, and the deferred
  -- trigger refuses to (re)publish it.
  BEGIN
    UPDATE health_concepts SET status = 'retired'
    WHERE id = (SELECT min(concept_id) FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk);
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with a retired participant concept is eligible';
    END IF;
    BEGIN
      SET CONSTRAINTS interaction_rules_publication_gate IMMEDIATE;
      UPDATE interaction_rules SET publication_status = 'published' WHERE id = rule_pk;
      RAISE EXCEPTION 'Ineligible rule was published';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- A concept that may not trigger matching makes the rule ineligible.
  BEGIN
    UPDATE health_concepts SET can_trigger_matching = false
    WHERE id = (SELECT min(concept_id) FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk);
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with a non-matching participant concept is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- One concept under two roles counts as one participant.
  BEGIN
    DELETE FROM interaction_rule_participants
    WHERE interaction_rule_id = rule_pk
      AND concept_id <> (SELECT min(concept_id) FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk);
    INSERT INTO interaction_rule_participants (interaction_rule_id, concept_id, participant_role, match_scope, required_for_match)
    SELECT rule_pk, min(concept_id), 'risk_context', 'exact_concept', true
    FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk;
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with one distinct required concept is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- A draft risk modifier makes the rule ineligible; a retired one does not.
  BEGIN
    INSERT INTO rule_risk_modifiers (interaction_rule_id, profile_risk_factor_id, condition_operator, condition_value, risk_change, personal_flag_title_text_id, extra_warning_text_id, clinician_note_text_id, status)
    SELECT rule_pk, profile_risk_factor_id, condition_operator, condition_value, risk_change, personal_flag_title_text_id, extra_warning_text_id, clinician_note_text_id, 'retired'
    FROM rule_risk_modifiers ORDER BY id LIMIT 1;
    IF NOT pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Retired risk modifier blocked eligibility';
    END IF;
    UPDATE rule_risk_modifiers SET status = 'draft' WHERE interaction_rule_id = rule_pk;
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with a draft risk modifier is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- A modifier whose evidence is not approved blocks eligibility (SMOKE_RULE_B).
  BEGIN
    UPDATE evidence_sources SET verification_status = 'needs_review' WHERE public_id = 'SMOKE_SRC_B';
    IF pg_temp.th_eligible('SMOKE_RULE_B') THEN
      RAISE EXCEPTION 'Rule whose only source is unapproved is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;
  BEGIN
    UPDATE rule_conditions SET status = 'draft' WHERE id = 990001;
    IF pg_temp.th_eligible('SMOKE_RULE_B') THEN
      RAISE EXCEPTION 'Rule with a draft modifier condition is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Workbook import support (004_md_workbook_schema.sql). Each case undoes
--    itself (custom SQLSTATE TH000).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  rule_pk bigint;
  linked_source bigint;
  unlinked_source bigint;
  existing_doi text;
  spare_concept bigint;
  primary_pk bigint;
  en_locale bigint := (SELECT id FROM locales WHERE code = 'en');
BEGIN
  SELECT id INTO rule_pk FROM interaction_rules WHERE public_id = 'SMOKE_RULE_A';
  SELECT min(evidence_source_id) INTO linked_source
  FROM interaction_rule_sources WHERE interaction_rule_id = rule_pk;
  SELECT min(id) INTO unlinked_source FROM evidence_sources
  WHERE id NOT IN (SELECT evidence_source_id FROM interaction_rule_sources WHERE interaction_rule_id = rule_pk);
  SELECT min(doi) INTO existing_doi FROM evidence_sources WHERE doi IS NOT NULL;
  SELECT min(id) INTO primary_pk FROM interaction_rule_participants
  WHERE interaction_rule_id = rule_pk AND participant_role = 'primary';
  SELECT min(hc.id) INTO spare_concept FROM health_concepts hc
  WHERE hc.status = 'published' AND hc.can_trigger_matching
    AND hc.id NOT IN (SELECT concept_id FROM user_profile_items WHERE user_id = 101 AND concept_id IS NOT NULL)
    AND hc.id NOT IN (SELECT concept_id FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk);

  -- DOI uniqueness ignores case.
  PERFORM pg_temp.th_expect_error('DOI differing only in case',
    format('INSERT INTO evidence_sources (public_id, title, source_type, doi, evidence_grade, verification_status)
            VALUES (''SRC_SMOKE_DOI'', ''dup'', ''other'', %L, ''unknown'', ''imported'')', upper(existing_doi)),
    'unique_violation');

  -- A finding needs its source linked to the rule; a CI needs a value.
  PERFORM pg_temp.th_expect_error('finding on an unlinked source',
    format('INSERT INTO evidence_findings (interaction_rule_id, evidence_source_id, finding_text) VALUES (%s, %s, ''x'')', rule_pk, unlinked_source),
    'foreign_key_violation');
  PERFORM pg_temp.th_expect_error('finding with CI but no value',
    format('INSERT INTO evidence_findings (interaction_rule_id, evidence_source_id, finding_order, finding_text, effect_ci_low, effect_ci_high) VALUES (%s, %s, 99, ''x'', 1, 2)', rule_pk, linked_source),
    'check_violation');
  PERFORM pg_temp.th_expect_error('finding value without metric',
    format('INSERT INTO evidence_findings (interaction_rule_id, evidence_source_id, finding_order, finding_text, effect_value) VALUES (%s, %s, 99, ''x'', 3.6)', rule_pk, linked_source),
    'check_violation');

  -- A timing window needs an anchor and relation.
  PERFORM pg_temp.th_expect_error('timing window without anchor',
    'UPDATE timing_recommendations SET min_minutes = 30, anchor = NULL, relation = NULL WHERE id = (SELECT min(id) FROM timing_recommendations)',
    'check_violation');

  -- Formulation qualifiers only on formulation concepts, and at least one.
  PERFORM pg_temp.th_expect_error('dosage form on an active substance',
    format('UPDATE health_concepts SET dosage_form = ''tablet'' WHERE id = %s', spare_concept),
    'check_violation');
  PERFORM pg_temp.th_expect_error('formulation without a qualifier',
    format('UPDATE health_concepts SET concept_type = ''formulation'' WHERE id = %s', spare_concept),
    'check_violation');
  PERFORM pg_temp.th_expect_error('qualifier dropped from an imported formulation',
    'UPDATE health_concepts SET dosage_form = NULL, route = NULL, strength_text = NULL WHERE public_id = ''FORM_0001''',
    'check_violation');

  -- A draft finding blocks eligibility; an approved one does not.
  BEGIN
    INSERT INTO evidence_findings (interaction_rule_id, evidence_source_id, finding_order, finding_text, status)
    VALUES (rule_pk, linked_source, 99, 'draft finding', 'draft');
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with a draft evidence finding is eligible';
    END IF;
    UPDATE evidence_findings SET status = 'approved' WHERE interaction_rule_id = rule_pk AND finding_order = 99;
    IF NOT pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Approved evidence finding blocked eligibility';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- A risk level that may not publish blocks eligibility.
  BEGIN
    UPDATE risk_levels SET can_publish = false
    WHERE id = (SELECT base_risk_level_id FROM interaction_rules WHERE id = rule_pk);
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with an unpublishable risk level is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- One participant is enough for a timing_context rule, not for others.
  BEGIN
    DELETE FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk AND id <> primary_pk;
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'General rule with one participant is eligible';
    END IF;
    UPDATE interaction_rules SET rule_scope = 'timing_context' WHERE id = rule_pk;
    IF NOT pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Timing rule with one participant is not eligible';
    END IF;
    IF ARRAY(SELECT rule_public_id FROM public_rule_matches_for_user(101, en_locale))
       IS DISTINCT FROM ARRAY['SMOKE_RULE_A']::text[] THEN
      RAISE EXCEPTION 'Timing rule did not match the profile holding its drug';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- Alternatives: a slot is met by any one of its concepts; a participant in
  -- a slot of its own must be present.
  BEGIN
    UPDATE interaction_rule_participants SET alternative_group = 1 WHERE id = primary_pk;
    INSERT INTO interaction_rule_participants (interaction_rule_id, concept_id, participant_role, match_scope, required_for_match, alternative_group)
    VALUES (rule_pk, spare_concept, 'primary', 'exact_concept', true, 1);
    IF NOT pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with an alternative participant is not eligible';
    END IF;
    IF ARRAY(SELECT rule_public_id FROM public_rule_matches_for_user(101, en_locale))
       IS DISTINCT FROM ARRAY['SMOKE_RULE_A']::text[] THEN
      RAISE EXCEPTION 'Alternative participant broke the match';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_public_rule_matches WHERE user_id = 101 AND rule_public_id = 'SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Legacy view disagrees with the matcher on alternatives';
    END IF;
    UPDATE interaction_rule_participants SET alternative_group = NULL
    WHERE interaction_rule_id = rule_pk AND concept_id = spare_concept;
    IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(101, en_locale)) THEN
      RAISE EXCEPTION 'Missing required participant still matched';
    END IF;
    -- Two concepts in one slot are one slot: not enough for a general rule.
    DELETE FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk AND id <> primary_pk AND concept_id <> spare_concept;
    UPDATE interaction_rule_participants SET alternative_group = 1 WHERE interaction_rule_id = rule_pk;
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule with a single alternative slot is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;

  -- Imported content: a topic with its summary texts, a rule with its trace
  -- and findings, a timing rule with a structured window.
  IF NOT EXISTS (SELECT 1 FROM interaction_topics t JOIN translations tr ON tr.text_id = t.what_happens_text_id
                 WHERE t.public_id = 'TOPIC_0001' AND t.source_workbook_sheet = 'Statiinid')
     OR NOT EXISTS (SELECT 1 FROM interaction_rules r JOIN evidence_findings f ON f.interaction_rule_id = r.id
                    WHERE r.public_id = 'RULE_0001' AND r.source_workbook_case_name = 'Atorvastatiin + Greip')
     OR NOT EXISTS (SELECT 1 FROM interaction_rules r JOIN timing_recommendations t ON t.interaction_rule_id = r.id
                    WHERE r.source_workbook_sheet = 'Tühja kõhuga' AND t.anchor IS NOT NULL AND t.min_minutes IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM interaction_rule_participants p JOIN health_concepts c ON c.id = p.concept_id
                    WHERE c.concept_type = 'formulation' AND c.dosage_form = 'soft_capsule') THEN
    RAISE EXCEPTION 'Workbook import rows missing';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Locale scalability. Undoes itself (custom SQLSTATE TH000).
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    IF NOT pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'SMOKE_RULE_A should be eligible';
    END IF;

    -- Region/script variants are valid locale codes; malformed ones are not.
    INSERT INTO locales (code, display_name) VALUES
      ('pt-BR', 'Portuguese (Brazil)'), ('zh-Hant', 'Chinese (Traditional)'), ('fil', 'Filipino');
    BEGIN
      INSERT INTO locales (code, display_name) VALUES ('EN', 'Bad code');
      RAISE EXCEPTION 'Malformed locale code EN was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- A non-required locale without copy does not affect eligibility...
    IF NOT pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Optional locale without copy blocked eligibility';
    END IF;
    -- ...but making it required does, with no view change.
    UPDATE locales SET is_mvp_required = true WHERE code = 'pt-BR';
    IF EXISTS (SELECT 1 FROM public_interaction_rule_eligibility) THEN
      RAISE EXCEPTION 'Rule eligible without copy in a required locale';
    END IF;
    UPDATE locales SET is_mvp_required = false WHERE code = 'pt-BR';

    -- A missing risk-label translation in a required locale blocks eligibility.
    DELETE FROM translations t
    USING interaction_rules r, risk_levels rl, locales l
    WHERE r.public_id = 'SMOKE_RULE_A'
      AND rl.id = r.base_risk_level_id
      AND t.text_id = rl.label_text_id
      AND l.id = t.locale_id AND l.code = 'en';
    IF pg_temp.th_eligible('SMOKE_RULE_A') THEN
      RAISE EXCEPTION 'Rule eligible without an en risk label';
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo locale checks';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Audit columns on every table, matching per locale, unpublish behaviour.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  item record;
  row_count bigint;
  locale_pk bigint;
BEGIN
  -- Every table has rows (imported content plus the throwaway fixtures for
  -- copy, modifiers and conditions, which no authored content provides yet).
  FOR item IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', item.tablename) INTO row_count;
    IF row_count = 0 THEN
      RAISE EXCEPTION 'Table % is empty', item.tablename;
    END IF;
  END LOOP;

  -- Standing rule: every table has the four audit columns, and UPDATE works on
  -- every table (the set_updated_at trigger must find its column).
  FOR item IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    SELECT count(*) INTO row_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = item.tablename
      AND column_name IN ('created_at', 'created_by', 'updated_at', 'updated_by');
    IF row_count <> 4 THEN
      RAISE EXCEPTION 'Table % has % of 4 audit columns', item.tablename, row_count;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = format('public.%I', item.tablename)::regclass
        AND tgname = 'set_' || item.tablename || '_updated_at'
    ) THEN
      RAISE EXCEPTION 'Table % has no updated_at trigger', item.tablename;
    END IF;
    EXECUTE format('UPDATE public.%I SET updated_by = updated_by', item.tablename);
  END LOOP;

  FOR locale_pk IN SELECT id FROM locales LOOP
    IF ARRAY(SELECT rule_public_id FROM public_rule_matches_for_user(101, locale_pk) ORDER BY rule_public_id)
       IS DISTINCT FROM ARRAY['SMOKE_RULE_A']::text[] THEN
      RAISE EXCEPTION 'Unexpected warfarin fixture matches for locale %', locale_pk;
    END IF;
    IF ARRAY(SELECT rule_public_id FROM public_rule_matches_for_user(102, locale_pk) ORDER BY rule_public_id)
       IS DISTINCT FROM ARRAY['SMOKE_RULE_B']::text[] THEN
      RAISE EXCEPTION 'Unexpected simvastatin fixture matches for locale %', locale_pk;
    END IF;
    IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(103, locale_pk))
       OR EXISTS (SELECT 1 FROM public_rule_matches_for_user(104, locale_pk)) THEN
      RAISE EXCEPTION 'Incomplete or unrelated profile triggered a match';
    END IF;
  END LOOP;

  UPDATE interaction_rules SET publication_status = 'draft' WHERE public_id = 'SMOKE_RULE_A';
  IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(101)) THEN
    RAISE EXCEPTION 'Unpublished rule was returned';
  END IF;
  UPDATE evidence_sources SET verification_status = 'needs_review'
  WHERE id IN (
    SELECT s.evidence_source_id FROM interaction_rule_sources s
    JOIN interaction_rules r ON r.id = s.interaction_rule_id WHERE r.public_id = 'SMOKE_RULE_B'
  );
  IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(102)) THEN
    RAISE EXCEPTION 'Rule without approved evidence was returned';
  END IF;
END;
$$;

ROLLBACK;
\echo Tervisehull database smoke test: PASS
