-- db/tests/promote_test.sql
-- Exercises promote_staging() and resolve_review() against sample staging rows.
-- Run on a disposable database (see README "Database" section). Wrapped in a
-- transaction that is rolled back at the end, so it can be re-run safely.
--
-- Usage:
--   psql -d scentshelf_test -v ON_ERROR_STOP=1 -f db/tests/promote_test.sql
--
-- Any failed check raises an exception and aborts the script (ON_ERROR_STOP).
-- "OK: ..." notices print for each check that passes.

begin;

-- Scratch table to pass ids between DO blocks.
create temp table test_state (key text primary key, val bigint);

-- 1. Unknown brand + name -> creates a draft fragrance, brand, variant, offer.
insert into staging_product
  (source_key, batch_id, page_url, domain, raw_name, display_name, brand, brand_key,
   name_key, gtin, price, currency, concentration, size_ml, gender)
values
  ('wdc-schemaorg', 'b1', 'https://shop.example/dior-sauvage-edt-100', 'shop.example',
   'Dior Sauvage EDT 100ml', 'Sauvage', 'Dior', 'dior', 'sauvage', '1111111111111',
   89.00, 'EUR', 'EDT', 100, 'M');

do $$
declare r jsonb;
begin
  r := promote_staging('b1');
  if (r->>'created')::int is distinct from 1 then
    raise exception 'expected 1 created row for b1, got %', r;
  end if;
  raise notice 'OK: unknown name creates a draft fragrance (%)', r;
end $$;

do $$
declare
  f_id bigint; f_status text; v_id bigint;
begin
  select f.id, f.status into f_id, f_status
  from fragrance f join brand b on b.id = f.brand_id
  where b.name_key = 'dior' and f.name_key = 'sauvage';

  if f_id is null then
    raise exception 'draft fragrance for Dior Sauvage was not created';
  end if;
  if f_status <> 'draft' then
    raise exception 'expected new fragrance status draft, got %', f_status;
  end if;

  select id into v_id from variant where fragrance_id = f_id and gtin = '1111111111111';
  if v_id is null then
    raise exception 'variant with gtin 1111111111111 was not created';
  end if;

  insert into test_state values ('sauvage_fragrance_id', f_id);
  insert into test_state values ('sauvage_variant_id', v_id);
  raise notice 'OK: draft fragrance % and variant % exist', f_id, v_id;
end $$;

-- 2. Same GTIN, different (mismatched) name -> matches the existing variant by GTIN,
--    not by name, proving GTIN match takes priority.
insert into staging_product
  (source_key, batch_id, page_url, domain, raw_name, display_name, brand, brand_key,
   name_key, gtin, price, currency, concentration, size_ml, gender)
values
  ('wdc-schemaorg', 'b2', 'https://othershop.example/dior-sauvage-100', 'othershop.example',
   'Dior Sauvage 100ml', 'Sauvage', 'Dior', 'dior', 'sauvage-eau-de-toilette', '1111111111111',
   79.00, 'EUR', 'EDT', 100, 'M');

do $$
declare
  r jsonb; st record; expect_fragrance bigint; expect_variant bigint;
begin
  r := promote_staging('b2');
  select val into expect_fragrance from test_state where key = 'sauvage_fragrance_id';
  select val into expect_variant from test_state where key = 'sauvage_variant_id';

  select status, fragrance_id, variant_id into st
  from staging_product where batch_id = 'b2';

  if st.status <> 'matched' then
    raise exception 'expected GTIN row to be matched, got status %', st.status;
  end if;
  if st.fragrance_id is distinct from expect_fragrance then
    raise exception 'GTIN match resolved to wrong fragrance: % (expected %)', st.fragrance_id, expect_fragrance;
  end if;
  if st.variant_id is distinct from expect_variant then
    raise exception 'GTIN match resolved to wrong variant: % (expected %)', st.variant_id, expect_variant;
  end if;
  raise notice 'OK: GTIN match wins over a mismatched name (%)', r;
end $$;

-- 3. Same brand + exact name key, new variant shape (EDP 60ml) -> matches the
--    existing fragrance by name, adds a new variant.
insert into staging_product
  (source_key, batch_id, page_url, domain, raw_name, display_name, brand, brand_key,
   name_key, price, currency, concentration, size_ml, gender)
values
  ('wdc-schemaorg', 'b3', 'https://shop.example/dior-sauvage-edp-60', 'shop.example',
   'Dior Sauvage EDP 60ml', 'Sauvage', 'Dior', 'dior', 'sauvage',
   75.00, 'EUR', 'EDP', 60, 'M');

do $$
declare
  r jsonb; st record; expect_fragrance bigint; new_variant bigint;
begin
  r := promote_staging('b3');
  select val into expect_fragrance from test_state where key = 'sauvage_fragrance_id';

  select status, fragrance_id, variant_id into st from staging_product where batch_id = 'b3';
  if st.status <> 'matched' then
    raise exception 'expected exact-name row to be matched, got status %', st.status;
  end if;
  if st.fragrance_id is distinct from expect_fragrance then
    raise exception 'exact-name match resolved to wrong fragrance: % (expected %)', st.fragrance_id, expect_fragrance;
  end if;

  select id into new_variant from variant
  where fragrance_id = expect_fragrance and concentration = 'EDP' and size_ml = 60;
  if new_variant is null then
    raise exception 'expected a new EDP/60ml variant to be created';
  end if;
  raise notice 'OK: exact name key match reuses the fragrance, adds a new variant (%)', r;
end $$;

-- 4. Similar (not identical) name, same brand -> goes to the review queue instead
--    of auto-matching or creating a duplicate.
insert into staging_product
  (source_key, batch_id, page_url, domain, raw_name, display_name, brand, brand_key,
   name_key, price, currency, gender)
values
  ('wdc-schemaorg', 'b4', 'https://shop.example/dior-sauvagee', 'shop.example',
   'Dior Sauvagee', 'Sauvagee', 'Dior', 'dior', 'sauvagee', 80.00, 'EUR', 'M');

do $$
declare r jsonb; st record; ri_id bigint;
begin
  r := promote_staging('b4');
  select status into st from staging_product where batch_id = 'b4';
  if st.status <> 'review' then
    raise exception 'expected similar-name row to go to review, got status %', st.status;
  end if;

  select ri.id into ri_id
  from review_item ri join staging_product sp on sp.id = ri.staging_id
  where sp.batch_id = 'b4' and ri.status = 'open';
  if ri_id is null then
    raise exception 'expected an open review_item for the similar-name row';
  end if;

  insert into test_state values ('review_same_id', ri_id);
  raise notice 'OK: similar name creates a review item (%), not an auto match or draft (%)', ri_id, r;
end $$;

-- 5. Unrelated brand + name -> creates its own new draft fragrance.
insert into staging_product
  (source_key, batch_id, page_url, domain, raw_name, display_name, brand, brand_key,
   name_key, price, currency, gender)
values
  ('wdc-schemaorg', 'b5', 'https://shop.example/chanel-bleu', 'shop.example',
   'Chanel Bleu', 'Bleu', 'Chanel', 'chanel', 'bleu', 95.00, 'EUR', 'M');

do $$
declare r jsonb; f_id bigint; f_status text;
begin
  r := promote_staging('b5');
  select f.id, f.status into f_id, f_status
  from fragrance f join brand b on b.id = f.brand_id
  where b.name_key = 'chanel' and f.name_key = 'bleu';

  if f_id is null then
    raise exception 'draft fragrance for Chanel Bleu was not created';
  end if;
  if f_status <> 'draft' then
    raise exception 'expected new fragrance status draft, got %', f_status;
  end if;

  insert into test_state values ('bleu_fragrance_id', f_id);
  raise notice 'OK: unrelated brand/name creates its own draft fragrance (%)', r;
end $$;

-- 6. Idempotency: running promote_staging() again for an already-processed batch
--    must be a no-op (no rows to pick up, counts unchanged).
do $$
declare
  r jsonb;
  brand_n int; fragrance_n int; variant_n int; offer_n int;
  brand_n2 int; fragrance_n2 int; variant_n2 int; offer_n2 int;
begin
  select count(*) into brand_n from brand;
  select count(*) into fragrance_n from fragrance;
  select count(*) into variant_n from variant;
  select count(*) into offer_n from offer;

  r := promote_staging('b1');  -- b1 rows are no longer 'new', nothing to do
  if r <> '{}'::jsonb then
    raise exception 'expected re-running promote_staging(''b1'') to be a no-op, got %', r;
  end if;

  select count(*) into brand_n2 from brand;
  select count(*) into fragrance_n2 from fragrance;
  select count(*) into variant_n2 from variant;
  select count(*) into offer_n2 from offer;

  if (brand_n, fragrance_n, variant_n, offer_n) is distinct from (brand_n2, fragrance_n2, variant_n2, offer_n2) then
    raise exception 'running promote_staging() twice changed row counts';
  end if;
  raise notice 'OK: running promote_staging() twice changes nothing';
end $$;

-- 7. resolve_review('same') -> the staging row is corrected to the candidate's
--    name key and re-promoted into an exact match on the existing fragrance.
do $$
declare
  ri_id bigint; expect_fragrance bigint; st record;
begin
  select val into ri_id from test_state where key = 'review_same_id';
  select val into expect_fragrance from test_state where key = 'sauvage_fragrance_id';

  perform resolve_review(ri_id, 'same');

  select status, name_key into st from staging_product where batch_id = 'b4';
  if st.status <> 'new' or st.name_key <> 'sauvage' then
    raise exception 'resolve_review(same) did not reset the staging row as expected: %', st;
  end if;

  perform promote_staging('b4');

  select status, fragrance_id into st from staging_product where batch_id = 'b4';
  if st.status <> 'matched' or st.fragrance_id is distinct from expect_fragrance then
    raise exception 'resolve_review(same) + re-promote did not match the candidate fragrance: %', st;
  end if;
  raise notice 'OK: resolve_review(same) merges the staging row into the candidate fragrance';
end $$;

-- 8. resolve_review('different') -> a second, similarly-named row is forced to
--    become its own new fragrance instead of joining the review candidate.
insert into staging_product
  (source_key, batch_id, page_url, domain, raw_name, display_name, brand, brand_key,
   name_key, price, currency, gender)
values
  ('wdc-schemaorg', 'b6', 'https://shop.example/chanel-bleue', 'shop.example',
   'Chanel Bleue', 'Bleue', 'Chanel', 'chanel', 'bleue', 95.00, 'EUR', 'F');

do $$
declare
  r jsonb; ri_id bigint; bleu_id bigint; bleue_id bigint; st record;
begin
  r := promote_staging('b6');
  select ri.id into ri_id
  from review_item ri join staging_product sp on sp.id = ri.staging_id
  where sp.batch_id = 'b6' and ri.status = 'open';
  if ri_id is null then
    raise exception 'expected an open review_item for Chanel Bleue, got %', r;
  end if;

  perform resolve_review(ri_id, 'different');
  perform promote_staging('b6');

  select val into bleu_id from test_state where key = 'bleu_fragrance_id';
  select status, fragrance_id into st from staging_product where batch_id = 'b6';
  bleue_id := st.fragrance_id;

  if st.status <> 'created' then
    raise exception 'expected resolve_review(different) row to be created, got status %', st.status;
  end if;
  if bleue_id is null or bleue_id = bleu_id then
    raise exception 'resolve_review(different) should create a fragrance distinct from %, got %', bleu_id, bleue_id;
  end if;
  raise notice 'OK: resolve_review(different) creates a separate fragrance (% vs %)', bleu_id, bleue_id;
end $$;

do $$ begin raise notice 'All promote_staging() / resolve_review() checks passed.'; end $$;

rollback;
