-- Reference rows for the objects added in 004_md_workbook_schema.sql. The
-- interaction content itself (topics, rules, findings, timing) comes from the
-- MD workbook import in 006_md_workbook_import.sql, not from this file.

BEGIN;

-- Units the workbook's conditions need beyond mg and mmHg.
INSERT INTO units (id, code, display_name, ucum_code, unit_family, is_active)
VALUES
  (3, 'ml', 'millilitre', 'mL', 'volume', true),
  (4, 'g', 'gram', 'g', 'mass', true),
  (5, 'ug', 'microgram', 'ug', 'mass', true),
  (6, 'min', 'minute', 'min', 'time', true),
  (7, 'h', 'hour', 'h', 'time', true),
  (8, 'd', 'day', 'd', 'time', true),
  (9, 'glass', 'glass (serving)', NULL, 'count', true),
  (10, 'uk_alcohol_unit', 'UK alcohol unit (8 g ethanol)', NULL, 'other', true);

-- The 'review' level is the workbook's "Not assessed": never publishable.
UPDATE risk_levels SET can_publish = false WHERE code = 'review';

SELECT setval(pg_get_serial_sequence('units', 'id'), (SELECT max(id) FROM units));

COMMIT;
