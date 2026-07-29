-- V2's seed user was inserted with created_by/updated_by left NULL. There's
-- no other acting user for seed data either, so self-reference it the same
-- way self-registration does.
UPDATE users
SET created_by = id, updated_by = id
WHERE email = 'test@tervisehull.ee' AND created_by IS NULL;
