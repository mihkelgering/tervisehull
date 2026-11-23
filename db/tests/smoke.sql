\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.th_eligible(p_public_id text) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM public_interaction_rule_eligibility e
    JOIN interaction_rules r ON r.id = e.interaction_rule_id
    WHERE r.public_id = p_public_id
  );
$$;

-- Publication gate. Each case runs in its own block and undoes itself
-- (custom SQLSTATE TH000), starting from the eligible RULE_0001.
DO $$
DECLARE
  rule_pk bigint;
BEGIN
  SELECT id INTO rule_pk FROM interaction_rules WHERE public_id = 'RULE_0001';
  IF NOT pg_temp.th_eligible('RULE_0001') THEN
    RAISE EXCEPTION 'RULE_0001 should be eligible in the fixtures';
  END IF;

  -- Published requires medical approval (row CHECK).
  BEGIN
    UPDATE interaction_rules SET medical_review_status = 'in_review' WHERE id = rule_pk;
    RAISE EXCEPTION 'Published rule without medical approval was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- A retired participant concept makes the rule ineligible, and the deferred
  -- trigger refuses to (re)publish it.
  BEGIN
    UPDATE health_concepts SET status = 'retired'
    WHERE id = (SELECT min(concept_id) FROM interaction_rule_participants WHERE interaction_rule_id = rule_pk);
    IF pg_temp.th_eligible('RULE_0001') THEN
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
    IF pg_temp.th_eligible('RULE_0001') THEN
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
    IF pg_temp.th_eligible('RULE_0001') THEN
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
    IF NOT pg_temp.th_eligible('RULE_0001') THEN
      RAISE EXCEPTION 'Retired risk modifier blocked eligibility';
    END IF;
    UPDATE rule_risk_modifiers SET status = 'draft' WHERE interaction_rule_id = rule_pk;
    IF pg_temp.th_eligible('RULE_0001') THEN
      RAISE EXCEPTION 'Rule with a draft risk modifier is eligible';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;
END;
$$;

-- Locale scalability. Runs first and undoes itself (custom SQLSTATE TH000),
-- so the checks below see untouched fixtures.
DO $$
BEGIN
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM public_interaction_rule_eligibility e
      JOIN interaction_rules r ON r.id = e.interaction_rule_id
      WHERE r.public_id = 'RULE_0001'
    ) THEN
      RAISE EXCEPTION 'RULE_0001 should be eligible in the fixtures';
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
    IF NOT EXISTS (
      SELECT 1 FROM public_interaction_rule_eligibility e
      JOIN interaction_rules r ON r.id = e.interaction_rule_id
      WHERE r.public_id = 'RULE_0001'
    ) THEN
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
    WHERE r.public_id = 'RULE_0001'
      AND rl.id = r.base_risk_level_id
      AND t.text_id = rl.label_text_id
      AND l.id = t.locale_id AND l.code = 'en';
    IF EXISTS (
      SELECT 1 FROM public_interaction_rule_eligibility e
      JOIN interaction_rules r ON r.id = e.interaction_rule_id
      WHERE r.public_id = 'RULE_0001'
    ) THEN
      RAISE EXCEPTION 'Rule eligible without an en risk label';
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'TH000', MESSAGE = 'undo locale checks';
  EXCEPTION WHEN SQLSTATE 'TH000' THEN NULL;
  END;
END;
$$;

DO $$
DECLARE
  item record;
  row_count bigint;
  next_id bigint;
  max_id bigint;
  locale_pk bigint;
BEGIN
  IF current_database() <> 'tervisehull' THEN
    RAISE EXCEPTION 'Run against the standalone tervisehull fixture database';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname = 'public') <> 40 THEN
    RAISE EXCEPTION 'Expected 40 base tables';
  END IF;
  FOR item IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', item.tablename) INTO row_count;
    IF row_count = 0 THEN
      RAISE EXCEPTION 'Fixture table % is empty', item.tablename;
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
  IF EXISTS (
    SELECT 1 FROM users
    WHERE created_by IS DISTINCT FROM id OR updated_by IS DISTINCT FROM id
  ) THEN
    RAISE EXCEPTION 'Seed users must self-reference created_by/updated_by';
  END IF;
  IF (SELECT count(*) FROM users) <> 6
     OR (SELECT count(*) FROM interaction_rules) <> 100
     OR (SELECT count(*) FROM interaction_rule_sources) <> 300
     OR (SELECT count(*) FROM health_concepts) <> 139
     OR (SELECT count(*) FROM concept_aliases) <> 750 THEN
    RAISE EXCEPTION 'Unexpected fixture population';
  END IF;
  IF (SELECT count(*) FROM evidence_sources) <> 300
     OR (SELECT count(doi) FROM evidence_sources) <> 26
     OR (SELECT count(pmid) FROM evidence_sources) <> 29
     OR (SELECT count(pmcid) FROM evidence_sources) <> 10
     OR (SELECT count(*) FROM evidence_sources
         WHERE evidence_grade = 'search_only' AND verification_status = 'needs_review') <> 270 THEN
    RAISE EXCEPTION 'Source enrichment is incomplete';
  END IF;
  IF (SELECT array_agg(code::text ORDER BY code) FROM locales) IS DISTINCT FROM ARRAY['en', 'et'] THEN
    RAISE EXCEPTION 'Expected English and Estonian locales';
  END IF;
  FOR locale_pk IN SELECT id FROM locales LOOP
    IF ARRAY(SELECT rule_public_id FROM public_rule_matches_for_user(101, locale_pk) ORDER BY rule_public_id)
       IS DISTINCT FROM ARRAY['RULE_0001']::text[] THEN
      RAISE EXCEPTION 'Unexpected warfarin fixture matches for locale %', locale_pk;
    END IF;
    IF ARRAY(SELECT rule_public_id FROM public_rule_matches_for_user(102, locale_pk) ORDER BY rule_public_id)
       IS DISTINCT FROM ARRAY['RULE_0002']::text[] THEN
      RAISE EXCEPTION 'Unexpected simvastatin fixture matches for locale %', locale_pk;
    END IF;
    IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(103, locale_pk))
       OR EXISTS (SELECT 1 FROM public_rule_matches_for_user(104, locale_pk)) THEN
      RAISE EXCEPTION 'Incomplete or unrelated profile triggered a match';
    END IF;
  END LOOP;
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

  UPDATE interaction_rules SET publication_status = 'draft' WHERE public_id = 'RULE_0001';
  IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(101)) THEN
    RAISE EXCEPTION 'Unpublished rule was returned';
  END IF;
  UPDATE evidence_sources SET verification_status = 'needs_review'
  WHERE id IN (
    SELECT s.evidence_source_id FROM interaction_rule_sources s
    JOIN interaction_rules r ON r.id = s.interaction_rule_id WHERE r.public_id = 'RULE_0002'
  );
  IF EXISTS (SELECT 1 FROM public_rule_matches_for_user(102)) THEN
    RAISE EXCEPTION 'Rule without approved evidence was returned';
  END IF;
END;
$$;

ROLLBACK;
\echo Tervisehull database smoke test: PASS
