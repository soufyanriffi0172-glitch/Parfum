# Data sources

Status values: **in use**, **candidate** (evaluate terms first), **prototype only**, **not allowed**.
Facts from sources are stored; third-party descriptions, reviews and images are not.

| Source | Gives | Status | Notes |
|---|---|---|---|
| Web Data Commons / Common Crawl (schema.org Product) | brand, name, GTIN, price, page link | **in use** | Yearly snapshots. Check the WDC and Common Crawl terms before going public. No notes or reviews. |
| Own catalogue edits and user submissions | anything we verify | **planned** | Goes through moderation. Main way to cover obscure and brand-new fragrances. |
| Shop/affiliate product feeds | name, brand, EAN, price, licensed images | **candidate** | Not yet checked which shops offer feeds; read each programme's terms (storage, images, attribution). |
| RSS from brands and fragrance blogs | signal that a new release exists | **candidate** | Signal only: a human verifies before anything is created. |
| Fragella API | notes, accords, longevity, sillage, season, price | **candidate** | Coverage claims differ between their pages. Read terms on storing data, commercial use and attribution. |
| Noteboxd API | notes, accords, brands, perfumers, reviews | **candidate** | Free tier of 50 calls per day then pay-per-call; read terms on storing data. |
| Open datasets derived from Fragrantica (Kaggle, Hugging Face) | notes, accords, ratings | **prototype only** | Carry non-commercial terms. Local testing only, never in a public deployment. |
| Fragrantica itself | - | **not allowed** | No scraping. No official public API or licence was found. |

## Checklist before adding any source
1. Read the terms: may we store the data? Use it commercially? Redistribute derived data? Attribution?
2. Check robots.txt and rate limits for anything fetched automatically.
3. Which fields do we take? Facts only; no descriptions, reviews or images unless the licence says so.
4. Add a row to `data_source` (key, licence, notes) and record `provenance` for each field.
5. Land the data in `staging_product` (or a sibling staging table); never write straight into public tables.
6. Update this file.

## Open questions for the owner
- Which source will supply notes, accords and longevity for the public launch (T-016)?
- Which shops or affiliate networks will provide price feeds?
- Legal review of database rights (EU) before public launch.
