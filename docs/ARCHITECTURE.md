# Architecture

Principle: a **modular monolith**. One codebase and one database, with clear modules, so it stays easy to
understand for one builder and can be split later if a module actually needs it.

## Overview
```
 Browser ──▶ Next.js (web/, SSR on Vercel)
               │  pages ─▶ server/ repositories ─▶ Supabase PostgreSQL (RLS)
               │  pages ─▶ SearchService ───────▶ Postgres now, Typesense/Meilisearch later
               └─ domain/ (pure TS: similarity, seasons, duration, filters)

 Data in ──▶ pipeline/ (Python) ─▶ staging_product ─▶ promote_staging() ─▶ catalogue
                                                        └─▶ review_queue (human decides)
```

## Modules (web/src)
| Module | Responsibility |
|---|---|
| `domain/` | Pure logic with unit tests: similarity, season suitability, duration from votes, scent timeline curves, filter definitions |
| `server/catalog` | Brands, fragrances, variants, offers (read, admin edit, merge) |
| `server/search` | `SearchService` interface + implementations; facet counts per filter option |
| `server/shelf` | A user's collection: ml left, wears, wishlist |
| `server/community` | Votes (longevity, projection, season), reviews, reports, moderation queue |
| `server/auth` | Sessions, roles (user, moderator, admin) |
| `app/` | Pages and components; no SQL, no business rules |
| `i18n/` | NL and EN messages |

## Data model (PostgreSQL)
- Catalogue: `brand`, `brand_alias`, `fragrance` (the scent), `variant` (concentration + size + GTIN),
  `offer` (price per shop page), later `note`, `accord`, `fragrance_note`, `perfumer`.
- Provenance: `data_source` (key, licence, notes) and `provenance` (which source gave which field).
- Import: `staging_product`, `review_item`, functions `promote_staging()` and `resolve_review()`.
- Users and community (to add): `profile`, `collection_item`, `vote` (raw votes), `review`, `report`.
  Averages (longevity, season) are computed from raw votes in a separate job and cached, never edited by hand.
- Fragrance lifecycle: `draft` → `published` → `merged` (with `merged_into`). Only `published` is public.

## Key flows
1. **Import**: source extractor → CSV → `staging_product` → `promote_staging()` → matched / review / draft.
2. **Publish**: admin reviews drafts and the review queue, then sets `published`.
3. **Browse**: URL carries the filter state (`?season=autumn&char=sweet`), so pages are shareable and indexable.
4. **Shelf**: logged-in user adds a variant, logs wears (sprays × 0.1 ml), sees season-based rotation.

## Scaling notes (do later, not now)
- Search: when the catalogue or filter load grows, add Typesense or Meilisearch implementing `SearchService`;
  PostgreSQL stays the source of truth and syncs to the index.
- Jobs: scheduled work (imports, vote aggregation) first via `pg_cron` or GitHub Actions; add a queue only
  when a job needs retries or fan-out.
- Pages: ISR/caching and sitemaps split per brand once there are tens of thousands of fragrances.
- Cost guard: spending limits on hosting, bot protection in front of public pages.

## Deliberately deferred
Microservices, a recommendation model (embeddings, collaborative filtering), a mobile app, real-time
features. Add each only when a concrete problem asks for it.

## Decisions (short log)
- D1 Modular monolith over microservices: one builder, one deploy, easy to reason about.
- D2 Supabase for database + auth + storage: fewer services to buy and operate.
- D3 Staging + review queue for every import: no source ever writes directly to public data.
- D4 Facts only from third parties; descriptions are written by us.
- D5 Filter state in the URL and filters declared as data: shareable, indexable, easy to extend.
