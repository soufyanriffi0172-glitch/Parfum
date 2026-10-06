# Scentshelf

A perfume discovery and collection site, in the spirit of Fragrantica but more interactive: a personal
shelf dashboard, season-based browsing, scent descriptions over time, longevity from reviews, similar and
cheaper alternatives, and a continuously growing catalogue.

## Working with the owner
- The owner has never built a site like this. **Reply in Dutch**, in plain language, without jargon.
  Explain each decision in one or two sentences.
- Work in small steps: take one task from `docs/BACKLOG.md`, say what you will do, do it, run the tests,
  summarise the result. Ask before anything big or irreversible (new paid service, dropping a table,
  changing the data model).
- Keep commits small, one task per commit. Tick the task in `docs/BACKLOG.md` when it meets its acceptance criteria.
- Keep this file and the "Commands" section up to date when you add tooling.

## Read first
- `docs/ARCHITECTURE.md` how the system is organised and why
- `docs/ROADMAP.md` phases, each with a "done when"
- `docs/BACKLOG.md` the task list (work through it in order)
- `docs/DATA-SOURCES.md` which data sources are allowed and what each licence says
- `prototype/scentshelf-v4.html` the visual and interaction prototype (single HTML file). **Port the ideas,
  do not copy-paste the file:** season theming, filters-as-data (`FILTERS`), scent timeline, duration from
  review votes, similarity, URL-based filter state.

## Stack
- Web: Next.js (App Router) + TypeScript, server-side rendered, deployed on Vercel
- Backend/data: Supabase (PostgreSQL, auth, storage); SQL migrations in `db/migrations/`
- Data pipeline: Python 3.10+, standard library only (`pipeline/`), tests with `unittest`
- Search: start with PostgreSQL (pg_trgm + filters) **behind a `SearchService` interface** so Typesense or
  Meilisearch can replace it later without touching pages
- Languages: Dutch and English from day one (no hard-coded UI strings)

## Repository map
```
CLAUDE.md            this file
docs/                architecture, roadmap, backlog, data sources
db/migrations/       numbered, forward-only SQL (001_core, 002_staging_and_promote, ...)
pipeline/            WDC extractor (reader, perfume filter, normalisation, CLI)
tests/               pipeline tests + fixtures
web/                 the Next.js app (to be created in task T-002)
prototype/           the original single-file prototype (reference only)
```

## Commands
- Pipeline tests: `python -m unittest discover -s tests -t .`
- Extract: `python -m pipeline.cli extract --input <file.nq.gz> --out staging.csv --limit 1000`
- Web commands: _fill in after T-002_ (dev server, lint, tests, typecheck)

## Architecture rules
- Business logic (similarity, season scoring, duration from votes, filter definitions) lives in pure
  TypeScript modules under `web/src/domain/` with **no Next.js or Supabase imports**, and has unit tests.
- All database access goes through repository modules in `web/src/server/`. Pages and components never
  write SQL.
- Search goes through `SearchService`. Filters are declared as data (key, label, mode, options, test), like
  `FILTERS` in the prototype, and their state lives in the URL.
- Imports are idempotent: raw data lands in `staging_product`, `promote_staging()` matches it, uncertain
  matches go to `review_queue`, new fragrances start as `draft`. Never write imported data straight into
  the public tables.
- Migrations are numbered and forward-only. Never edit an applied migration; add a new one.

## Hard rules: data and legal
- **Never scrape Fragrantica**, or any site whose terms forbid it. Do not write scrapers for them, do not
  add dependencies that do.
- **Never store third-party descriptions, reviews or images.** Store facts (brand, name, concentration,
  size, GTIN, notes, price + link). Write descriptions ourselves. Images only with a known licence, with the
  licence stored per image.
- Every imported field needs a source and licence: register the source in `data_source`, record `provenance`.
  Do not use a source that is not documented in `docs/DATA-SOURCES.md`.
- Datasets derived from Fragrantica (for example some Kaggle sets) carry non-commercial terms: **local
  testing only, never in a public deployment.**
- User content (reviews, votes, submissions) is moderated before it is public. Plan for spam from day one.

## Security
- Row level security on every table. Add a test that user A cannot read user B's collection or drafts.
- The Supabase service role key never reaches the browser or the repo. Secrets go in environment variables;
  keep `.env.example` current; never commit `.env`.
- Public pages only read `published` data.

## Definition of done
1. Acceptance criteria in `docs/BACKLOG.md` met.
2. Tests added or updated and passing (pipeline tests plus, once it exists, web tests, lint, typecheck).
3. Docs updated if behaviour or structure changed. This file updated if commands changed.
4. No secrets, no copied third-party text or images.

## Known gaps
- The perfume filter in `pipeline/perfume_filter.py` is a heuristic; tune it on real data (T-010).
