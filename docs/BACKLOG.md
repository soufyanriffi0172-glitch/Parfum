# Backlog

Work top to bottom. One task per commit. Tick the box when every acceptance criterion is met.
Tasks marked **[owner]** need a decision or an account from the owner: ask in Dutch, do not guess.

## Phase 0: foundation

- [ ] **T-001 Run the SQL on a real database**
  Run `db/migrations/001_core.sql` and `002_staging_and_promote.sql` on a fresh PostgreSQL 15+ (local Docker
  or a Supabase test project). Fix any errors in new numbered migrations if already applied, otherwise in place.
  Add `db/tests/promote_test.sql` that inserts sample staging rows and checks: GTIN match, exact key match,
  similar name goes to `review_item`, unknown name creates a `draft`, running `promote_staging()` twice
  changes nothing, `resolve_review('same'|'different')` works.
  *Accept:* migrations apply cleanly from scratch; the test script passes; README states how to run it.

- [ ] **T-002 Create the web app**
  Create `web/` with Next.js (App Router) + TypeScript, lint, typecheck and a unit-test runner. Add
  `web/src/domain/`, `web/src/server/`, `web/src/i18n/` with a placeholder test in each. Fill in the
  "Web commands" in `CLAUDE.md`.
  *Accept:* dev server starts, lint + typecheck + tests pass, commands documented.

- [ ] **T-003 CI and environments**
  GitHub Actions running pipeline tests and web lint/typecheck/tests on every push. `.env.example`
  listing every variable. Document local / preview / production in `docs/ENVIRONMENTS.md`.
  *Accept:* CI green on a clean clone; no secret in the repo.

- [ ] **T-004 [owner] Hosting, database and monitoring accounts**
  Walk the owner through creating Supabase, Vercel (note: commercial use needs a paid plan) and an
  error-monitoring account; enable database backups; set spending limits. Record results in `docs/ENVIRONMENTS.md`.
  *Accept:* a deploy from `main` works; an intentional test error shows up in monitoring.

## Phase 1: catalogue

- [ ] **T-010 [owner] Real data run**
  Owner downloads the WDC schema.org Product subset (see `pipeline/README.md`). Run the extractor on one file
  with `--limit`, review 200 random rows, tune `perfume_filter.py` and `normalize.py`, add failing examples to
  `tests/fixtures/`. Report precision on the sample in `docs/DATA-SOURCES.md`.
  *Accept:* at least 95% of the 200 sampled accepted rows are single perfumes; tests cover each fix.

- [ ] **T-011 Brand aliases**
  Seed `brand_alias` for common variants (YSL, D&G, JPG, ...) from the brands found in T-010; add a script to
  list brand_keys that look like duplicates.
  *Accept:* top 200 brands resolve to one brand each.

- [ ] **T-012 Import report**
  A SQL view or script: per batch, counts by status (matched, created, review, rejected) and top rejection reasons.
  *Accept:* report runs after every import and is described in the pipeline README.

- [ ] **T-013 Admin: review queue and drafts**
  Admin-only screens (role check, RLS): review queue (same / different), drafts list with publish, merge two
  fragrances (`merged_into`), edit brand aliases.
  *Accept:* a non-admin gets no access; each action is covered by a test.

- [ ] **T-014 Public fragrance page**
  Server-rendered page per published fragrance with variants and offers, canonical URL, `Product` JSON-LD,
  sitemap, NL/EN.
  *Accept:* page renders without client JS for core content; sitemap lists published fragrances only.

- [ ] **T-015 SearchService and filters**
  Define `SearchService` in `web/src/server/search` and a PostgreSQL implementation (pg_trgm + filters) that
  returns results and facet counts per option. Port the prototype's `FILTERS` (season first, then character,
  price, ...) as data, with state in the URL.
  *Accept:* swapping the implementation needs no page changes; facet counts react to other active filters; tests.

- [ ] **T-016 [owner] Notes, accords and season data**
  Owner picks a licensed or open source for notes/accords (see `DATA-SOURCES.md`). Add `note`, `accord`,
  `fragrance_note` tables and an importer through staging, with provenance. Port season scoring from the
  prototype (fallback derived from note families).
  *Accept:* source and licence recorded per field; nothing from a Fragrantica-derived set in public tables.

## Phase 2: accounts and shelf

- [ ] **T-020 Authentication** Sign-up/sign-in with roles user, moderator, admin. *Accept:* roles enforced in RLS and tested.
- [ ] **T-021 Shelf data and RLS** `profile`, `collection_item` (variant, ml left, wears), wishlist. *Accept:* test proves user A cannot read user B's rows.
- [ ] **T-022 Shelf UI** Port the season-first shelf (season hero, rotation, out-of-season, gaps) from the prototype. *Accept:* matches prototype behaviour; no client-only data loss.
- [ ] **T-023 GDPR basics** Privacy page, cookie choice, delete and export account. *Accept:* deleting an account removes its rows; export returns the user's data.

## Phase 3: community

- [ ] **T-030 Votes** Raw `vote` rows (longevity, projection, season) with per-user uniqueness and rate limits. *Accept:* duplicates rejected; limits tested.
- [ ] **T-031 Aggregation job** Compute averages and distributions from raw votes into cached columns. *Accept:* idempotent; matches the prototype's duration formula.
- [ ] **T-032 Reviews and moderation** Submit, report, moderate, remove. Bot protection. *Accept:* reported items land in a queue; moderator can remove without code.
- [ ] **T-033 [owner] Launch plan for first votes** Decide how to seed the first real votes and reviews. *Accept:* documented plan.
