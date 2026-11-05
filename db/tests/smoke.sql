\set ON_ERROR_STOP on
BEGIN;

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
