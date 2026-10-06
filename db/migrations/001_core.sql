-- 001_core.sql  (PostgreSQL / Supabase)
-- Core catalogue. Facts only: no third-party descriptions, no copied images.

create extension if not exists pg_trgm;

-- Where every piece of data comes from, and under which terms.
create table if not exists data_source (
  id          serial primary key,
  key         text unique not null,
  name        text not null,
  license     text,
  notes       text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists brand (
  id          bigserial primary key,
  name        text not null,
  name_key    text not null unique,
  created_at  timestamptz not null default now()
);

-- "ysl" -> Yves Saint Laurent. Fill this table from the admin screen when brand variants show up.
create table if not exists brand_alias (
  alias_key   text primary key,
  brand_id    bigint not null references brand(id) on delete cascade
);

-- A fragrance is the scent itself (Sauvage); concentrations and sizes live in variant.
create table if not exists fragrance (
  id           bigserial primary key,
  brand_id     bigint not null references brand(id),
  name         text not null,
  name_key     text not null,
  year         int,
  gender       text check (gender in ('M','F','U')),
  status       text not null default 'draft' check (status in ('draft','published','merged')),
  merged_into  bigint references fragrance(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (brand_id, name_key)
);
create index if not exists fragrance_name_trgm on fragrance using gin (name_key gin_trgm_ops);
create index if not exists fragrance_status_idx on fragrance (status);

-- EDP / EDT / size. One row per sellable variant.
create table if not exists variant (
  id             bigserial primary key,
  fragrance_id   bigint not null references fragrance(id) on delete cascade,
  concentration  text,
  size_ml        int,
  gtin           text
);
create unique index if not exists variant_gtin_uq on variant (gtin) where gtin is not null;
create unique index if not exists variant_shape_uq
  on variant (fragrance_id, coalesce(concentration, ''), coalesce(size_ml, 0));

-- Price per shop page. We store the link, not the shop's text or photos.
create table if not exists offer (
  id          bigserial primary key,
  variant_id  bigint not null references variant(id) on delete cascade,
  source_id   int not null references data_source(id),
  url         text not null,
  domain      text,
  price       numeric(8,2),
  currency    text,
  seen_at     timestamptz not null default now(),
  unique (source_id, url)
);

-- Which source supplied which field (so a source can be removed later without guessing).
create table if not exists provenance (
  entity      text not null,
  entity_id   bigint not null,
  field       text not null,
  source_id   int not null references data_source(id),
  fetched_at  timestamptz not null default now(),
  primary key (entity, entity_id, field)
);

-- Row level security: the public may only read published data. Everything else needs the service role.
alter table data_source   enable row level security;
alter table brand         enable row level security;
alter table brand_alias   enable row level security;
alter table fragrance     enable row level security;
alter table variant       enable row level security;
alter table offer         enable row level security;
alter table provenance    enable row level security;

create policy "public read brands" on brand for select using (true);
create policy "public read published fragrances" on fragrance for select using (status = 'published');
create policy "public read variants of published" on variant for select
  using (exists (select 1 from fragrance f where f.id = variant.fragrance_id and f.status = 'published'));
create policy "public read offers of published" on offer for select
  using (exists (select 1 from variant v join fragrance f on f.id = v.fragrance_id
                 where v.id = offer.variant_id and f.status = 'published'));

insert into data_source (key, name, license, notes) values
  ('wdc-schemaorg', 'Web Data Commons schema.org Product', 'Check webdatacommons.org / Common Crawl terms before publishing',
   'Facts only: name, brand, GTIN, price, page link. Descriptions are never stored.')
on conflict (key) do nothing;
