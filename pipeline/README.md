# Scentshelf data-pipeline

Bouwt een eigen geurencatalogus uit openbare webdata (Web Data Commons / Common Crawl), met een
controlestap voor twijfelgevallen. Alleen feiten worden opgeslagen: merk, naam, concentratie, inhoud,
GTIN en prijs met link. **Beschrijvingen en foto's van winkels worden nooit opgeslagen.**

```
WDC-dump (.nq.gz)
   │  python -m pipeline.cli extract
   ▼
staging.csv ──\copy──▶ staging_product        (ruw, per bron en batch)
                          │  select promote_staging();
                          ▼
              ┌─ zelfde GTIN ............ matched   (automatisch)
              ├─ zelfde merk + naam ..... matched   (automatisch)
              ├─ gelijkaardige naam ..... review_queue  (mens beslist: resolve_review)
              └─ nieuw .................. fragrance 'draft'  (pas publiek na jouw 'published')
```

## Mappen
- `pipeline/` Python (alleen standaardbibliotheek): reader, parfumfilter, normalisatie, CLI
- `db/migrations/` SQL voor PostgreSQL/Supabase (tabellen, RLS, `promote_staging()`, `resolve_review()`)
- `tests/` unittests met een kleine voorbeelddump

## Aan de slag
```bash
# 1. tests (geen installatie nodig, Python 3.10+)
python -m unittest discover -s tests -t .

# 2. database (Supabase: gebruik de directe verbinding / service role)
psql "$DATABASE_URL" -f db/migrations/001_core.sql
psql "$DATABASE_URL" -f db/migrations/002_staging_and_promote.sql

# 3. data downloaden: webdatacommons.org/structureddata -> "Download Schema.org Subset (N-Quads)"
#    en kies de deelverzameling voor de klasse Product (de volledige dump is 1,4 TB, neem die niet)

# 4. parfums eruit filteren (begin met --limit om te testen)
python -m pipeline.cli extract --input product.nq.gz --out staging.csv --limit 1000

# 5. laden en matchen
psql "$DATABASE_URL" -c "\copy staging_product(source_key,batch_id,page_url,domain,raw_name,display_name,brand,brand_key,name_key,gtin,sku,category,price,currency,concentration,size_ml,gender,perfume_score) from 'staging.csv' csv header"
psql "$DATABASE_URL" -c "select promote_staging();"

# 6. twijfelgevallen bekijken en beslissen
psql "$DATABASE_URL" -c "select * from review_queue limit 20;"
psql "$DATABASE_URL" -c "select resolve_review(1, 'same');"      -- of 'different'
psql "$DATABASE_URL" -c "select promote_staging();"               -- verwerkt de beslissingen
```

## Een nieuwe bron toevoegen
1. Voeg een rij toe aan `data_source` (met licentie en notities).
2. Schrijf een extractor die dezelfde CSV-kolommen levert (`COLUMNS` in `pipeline/cli.py`) met die `source_key`.
3. Laad naar `staging_product` en draai `promote_staging()`. De rest werkt zonder aanpassing.

## Wat dit wel en niet doet
- Levert merk, naam, concentratie, inhoud, GTIN en prijzen. **Geen** noten, accorden, longevity of reviews:
  die komen uit een gelicentieerde of open bron, of uit je eigen community.
- WDC publiceert momentopnames (jaarlijks). Voor actuele nieuwe geuren voeg je winkelfeeds, RSS en
  gebruikersvoorstellen toe als extra bronnen (zie hierboven).
- De filter is een heuristiek (`perfume_filter.py`). Bekijk steekproeven en stel `MIN_SCORE` en de
  woordenlijsten bij op echte data.
- Aannames: quads van één webpagina staan in de dump achter elkaar; brandnamen die niet overeenkomen
  (bijv. "YSL") los je op via de tabel `brand_alias`.
- Controleer de licentievoorwaarden van Web Data Commons en Common Crawl voordat je publiek gaat, en
  laat de juridische kant (databankrecht) beoordelen.

## Getest / niet getest
- Python: getest met unittests (`tests/`).
- SQL: **niet** getest tegen een echte database (er was hier geen PostgreSQL). Draai de migraties eerst op
  een lege testdatabase en probeer `promote_staging()` met de voorbeeldrijen. `security_invoker` op de view
  vraagt PostgreSQL 15 of nieuwer.
