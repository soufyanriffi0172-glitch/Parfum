# Roadmap

Weeks are rough estimates for one person working part time. Do not start a phase before the previous one
meets its "done when".

## Phase 0: foundation (weeks 1-2)
- Choose and document data sources and their licences (`DATA-SOURCES.md`).
- Run the existing SQL on a real test database and fix what breaks.
- Create the web app, CI, environments, error monitoring and backups.
- **Done when:** an empty site deploys automatically and the schema runs cleanly on a fresh database.

## Phase 1: catalogue (weeks 3-6)
- Import with source and licence per field; tune the perfume filter on real data.
- Admin screens: review queue, publish drafts, merge fragrances, brand aliases.
- Public fragrance pages, search and filters (season, character, price, ...), SEO basics, NL/EN.
- **Done when:** a few thousand fragrances are live, indexable, and filterable.

## Phase 2: accounts and shelf (weeks 7-10)
- Sign-in, collection and wishlist, ml left and wears, season-based shelf.
- GDPR basics: privacy page, cookie choice, delete and export account.
- Tests that prove users cannot read each other's data.
- **Done when:** a test user can build a shelf and no other user can read it.

## Phase 3: community (weeks 11-16)
- Votes (longevity, projection, season) and reviews, with limits, reporting and a moderation queue.
- Average calculation as a separate job from the raw votes.
- A plan for the first votes (empty pages are the biggest launch risk).
- **Done when:** spam is caught and content can be removed without touching code.

## Phase 4: growth (after that)
- Dedicated search engine behind `SearchService` when needed.
- Better recommendations, prices and affiliate links, perhaps a mobile app.
- Only when real users ask for it.
