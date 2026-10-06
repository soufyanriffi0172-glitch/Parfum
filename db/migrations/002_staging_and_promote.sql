-- 002_staging_and_promote.sql
-- Raw imports land in staging_product. promote_staging() matches them against the catalogue:
--   1. same GTIN                      -> matched (auto)
--   2. same brand + same name_key     -> matched (auto)
--   3. same brand + similar name      -> review queue (a human decides)
--   4. otherwise                      -> new fragrance as 'draft' (not public until you publish it)
-- Re-running is safe: only rows with status 'new' are processed.

create table if not exists staging_product (
  id             bigserial primary key,
  source_key     text not null,
  batch_id       text,
  page_url       text,
  domain         text,
  raw_name       text,
  display_name   text,
  brand          text,
  brand_key      text,
  name_key       text,
  gtin           text,
  sku            text,
  category       text,
  price          numeric(8,2),
  currency       text,
  concentration  text,
  size_ml        int,
  gender         text,
  perfume_score  int,
  -- processing state
  status         text not null default 'new' check (status in ('new','matched','created','review','rejected')),
  force_new      boolean not null default false,   -- set by resolve_review('different')
  fragrance_id   bigint references fragrance(id),
  variant_id     bigint references variant(id),
  error          text,
  created_at     timestamptz not null default now(),
  processed_at   timestamptz
);
create index if not exists staging_status_idx on staging_product (status, batch_id);

create table if not exists review_item (
  id                      bigserial primary key,
  kind                    text not null,
  staging_id              bigint not null references staging_product(id) on delete cascade,
  candidate_fragrance_id  bigint references fragrance(id),
  score                   real,
  status                  text not null default 'open' check (status in ('open','resolved')),
  resolution              text,
  created_at              timestamptz not null default now(),
  resolved_at             timestamptz,
  unique (staging_id, kind)
);

alter table staging_product enable row level security;   -- no policies: service role only
alter table review_item     enable row level security;

-- Admin view for the review screen (security_invoker keeps row level security in force).
create or replace view review_queue with (security_invoker = true) as
select r.id, r.score, st.raw_name, st.brand, st.display_name as incoming_name,
       f.id as candidate_id, f.name as candidate_name, st.page_url
from review_item r
join staging_product st on st.id = r.staging_id
left join fragrance f on f.id = r.candidate_fragrance_id
where r.status = 'open'
order by r.score desc;

create or replace function promote_staging(p_batch text default null)
returns jsonb
language plpgsql
as $$
declare
  result jsonb;
begin
  -- Rows from a source that is not registered cannot be trusted or traced.
  update staging_product st
     set status = 'rejected', error = 'unknown source_key', processed_at = now()
   where st.status = 'new'
     and (p_batch is null or st.batch_id = p_batch)
     and not exists (select 1 from data_source ds where ds.key = st.source_key);

  drop table if exists _s;
  create temp table _s on commit drop as
  select st.id, st.brand, st.brand_key, st.display_name, st.name_key, st.gtin, st.concentration,
         st.size_ml, st.gender, st.force_new,
         null::bigint as brand_id, null::bigint as fragrance_id, null::bigint as variant_id, null::text as how
  from staging_product st
  where st.status = 'new' and (p_batch is null or st.batch_id = p_batch)
    and st.brand_key is not null and st.name_key is not null;

  -- 1. brands
  insert into brand (name, name_key)
  select distinct on (s.brand_key) s.brand, s.brand_key
  from _s s
  where not exists (select 1 from brand_alias a where a.alias_key = s.brand_key)
  order by s.brand_key, s.id
  on conflict (name_key) do nothing;

  update _s s set brand_id = coalesce(
    (select a.brand_id from brand_alias a where a.alias_key = s.brand_key),
    (select b.id from brand b where b.name_key = s.brand_key));

  -- 2. same GTIN
  update _s set fragrance_id = v.fragrance_id, variant_id = v.id, how = 'gtin'
  from variant v
  where _s.gtin is not null and v.gtin = _s.gtin;

  -- 3. same brand + same name key (follows merges)
  update _s set fragrance_id = coalesce(f.merged_into, f.id), how = 'exact'
  from fragrance f
  where _s.fragrance_id is null and _s.brand_id is not null
    and f.brand_id = _s.brand_id and f.name_key = _s.name_key;

  -- 4. similar name, same brand -> a human decides
  with ins as (
    insert into review_item (kind, staging_id, candidate_fragrance_id, score)
    select 'possible_duplicate', s.id, c.id, c.sim
    from _s s
    cross join lateral (
      select f.id, similarity(f.name_key, s.name_key) as sim
      from fragrance f
      where f.brand_id = s.brand_id and f.status <> 'merged'
        and f.name_key % s.name_key and similarity(f.name_key, s.name_key) >= 0.5
      order by similarity(f.name_key, s.name_key) desc
      limit 1
    ) c
    where s.fragrance_id is null and s.brand_id is not null and not s.force_new
    on conflict (staging_id, kind) do nothing
    returning staging_id
  )
  update _s set how = 'review' from ins where _s.id = ins.staging_id;

  -- 5. everything else becomes a draft fragrance
  insert into fragrance (brand_id, name, name_key, gender, status)
  select distinct on (s.brand_id, s.name_key) s.brand_id, s.display_name, s.name_key, s.gender, 'draft'
  from _s s
  where s.fragrance_id is null and s.how is null and s.brand_id is not null
  order by s.brand_id, s.name_key, s.id
  on conflict (brand_id, name_key) do nothing;

  update _s set fragrance_id = coalesce(f.merged_into, f.id), how = 'created'
  from fragrance f
  where _s.fragrance_id is null and _s.how is null and _s.brand_id is not null
    and f.brand_id = _s.brand_id and f.name_key = _s.name_key;

  insert into provenance (entity, entity_id, field, source_id)
  select distinct on (s.fragrance_id) 'fragrance', s.fragrance_id, 'name', ds.id
  from _s s
  join staging_product st on st.id = s.id
  join data_source ds on ds.key = st.source_key
  where s.how = 'created'
  order by s.fragrance_id, s.id
  on conflict do nothing;

  -- 6. variants (concentration + size)
  insert into variant (fragrance_id, concentration, size_ml, gtin)
  select distinct on (s.fragrance_id, coalesce(s.concentration, ''), coalesce(s.size_ml, 0))
         s.fragrance_id, s.concentration, s.size_ml, s.gtin
  from _s s
  where s.fragrance_id is not null and s.variant_id is null
  order by s.fragrance_id, coalesce(s.concentration, ''), coalesce(s.size_ml, 0), (s.gtin is null), s.id
  on conflict do nothing;

  update _s set variant_id = v.id
  from variant v
  where _s.variant_id is null and _s.fragrance_id is not null
    and v.fragrance_id = _s.fragrance_id
    and coalesce(v.concentration, '') = coalesce(_s.concentration, '')
    and coalesce(v.size_ml, 0) = coalesce(_s.size_ml, 0);

  -- 7. offers (price per shop page)
  insert into offer (variant_id, source_id, url, domain, price, currency, seen_at)
  select distinct on (ds.id, st.page_url) s.variant_id, ds.id, st.page_url, st.domain, st.price, st.currency, now()
  from _s s
  join staging_product st on st.id = s.id
  join data_source ds on ds.key = st.source_key
  where s.variant_id is not null and st.page_url is not null
  order by ds.id, st.page_url, st.id desc
  on conflict (source_id, url) do update
    set variant_id = excluded.variant_id, price = excluded.price,
        currency = excluded.currency, seen_at = excluded.seen_at;

  -- 8. record what happened to each staging row
  update staging_product st
     set status = case s.how when 'review' then 'review' when 'created' then 'created'
                             when 'gtin' then 'matched' when 'exact' then 'matched' else 'rejected' end,
         fragrance_id = s.fragrance_id, variant_id = s.variant_id,
         error = case when s.how is null then 'no brand or name' end,
         processed_at = now()
    from _s s
   where st.id = s.id;

  -- rows without brand_key / name_key never entered _s
  update staging_product st
     set status = 'rejected', error = 'no brand or name', processed_at = now()
   where st.status = 'new' and (p_batch is null or st.batch_id = p_batch)
     and (st.brand_key is null or st.name_key is null);

  select coalesce(jsonb_object_agg(coalesce(how, 'rejected'), n), '{}'::jsonb) into result
  from (select how, count(*) as n from _s group by how) t;
  return result;
end;
$$;

-- Admin decision on a review item:
--   'same'      -> the incoming product is the candidate fragrance (it will be matched on the next promote)
--   'different' -> it is a separate fragrance (it will be created as a draft on the next promote)
create or replace function resolve_review(p_id bigint, p_action text)
returns void
language plpgsql
as $$
declare
  r review_item%rowtype;
begin
  select * into r from review_item where id = p_id and status = 'open';
  if not found then
    raise exception 'review item % not found or already resolved', p_id;
  end if;
  if p_action = 'same' then
    update staging_product st
       set name_key = f.name_key, status = 'new', error = null
      from fragrance f
     where st.id = r.staging_id and f.id = r.candidate_fragrance_id;
  elsif p_action = 'different' then
    update staging_product set force_new = true, status = 'new', error = null where id = r.staging_id;
  else
    raise exception 'unknown action %, use same or different', p_action;
  end if;
  update review_item set status = 'resolved', resolution = p_action, resolved_at = now() where id = p_id;
end;
$$;

-- Only the service role (your server / admin tools) may run these.
-- anon/authenticated only exist on Supabase; revoke from them there, skip on plain PostgreSQL.
revoke all on function promote_staging(text) from public;
revoke all on function resolve_review(bigint, text) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function promote_staging(text) from anon';
    execute 'revoke all on function resolve_review(bigint, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function promote_staging(text) from authenticated';
    execute 'revoke all on function resolve_review(bigint, text) from authenticated';
  end if;
end $$;

-- Optional (Supabase): run the promotion automatically every 30 minutes.
-- select cron.schedule('promote-staging', '*/30 * * * *', $$select promote_staging()$$);
