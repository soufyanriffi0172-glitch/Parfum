"""Command line: python -m pipeline.cli extract --input product.nq.gz --out staging.csv

Reads a Web Data Commons schema.org Product dump (N-Quads, optionally .gz), keeps the perfumes and
writes a CSV that matches the staging_product table. Descriptions are never written.
"""
import argparse
import csv
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from urllib.parse import urlparse

from .normalize import (clean_name, norm_text, normalize_gtin, parse_concentration, parse_gender,
                        parse_size_ml)
from .perfume_filter import is_perfume
from .wdc_reader import iter_graph_groups, iter_quads, open_any, products_from_group

COLUMNS = [
    "source_key", "batch_id", "page_url", "domain", "raw_name", "display_name", "brand", "brand_key",
    "name_key", "gtin", "sku", "category", "price", "currency", "concentration", "size_ml", "gender",
    "perfume_score",
]


def build_row(p, source_key, batch_id):
    """Turn one extracted product into a staging row, or return (None, reason)."""
    ok, score, _why = is_perfume(p["name"], p["category"], p["_description"])
    if not ok:
        return None, "not_perfume"
    brand = (p["brand"] or "").strip()
    brand_key = norm_text(brand)
    if not brand_key:
        return None, "no_brand"
    display, name_key = clean_name(p["name"], brand)
    if not name_key:
        return None, "no_name"
    url = p["page_url"]
    return {
        "source_key": source_key,
        "batch_id": batch_id,
        "page_url": url,
        "domain": (urlparse(url).netloc.lower().removeprefix("www.") if url else None),
        "raw_name": p["name"][:300],
        "display_name": display[:200],
        "brand": brand[:120],
        "brand_key": brand_key,
        "name_key": name_key,
        "gtin": normalize_gtin(p["gtin_raw"]),
        "sku": (p["sku"] or None) and p["sku"][:80],
        "category": p["category"],
        "price": p["price"],
        "currency": p["currency"],
        "concentration": parse_concentration(p["name"]),
        "size_ml": parse_size_ml(p["name"]),
        "gender": parse_gender(p["name"]),
        "perfume_score": score,
    }, None


def extract(path, out_path, source_key="wdc-schemaorg", batch_id=None, limit=None):
    batch_id = batch_id or datetime.now(timezone.utc).strftime("wdc-%Y%m%dT%H%M%SZ")
    stats = Counter()
    with open_any(path) as fh, open(out_path, "w", newline="", encoding="utf-8") as out:
        writer = csv.DictWriter(out, fieldnames=COLUMNS)
        writer.writeheader()
        quads = iter_quads(fh, stats)
        for graph, group in iter_graph_groups(quads):
            stats["pages"] += 1
            for product in products_from_group(graph, group):
                stats["products"] += 1
                row, reason = build_row(product, source_key, batch_id)
                if row is None:
                    stats["rejected_" + reason] += 1
                    continue
                writer.writerow(row)
                stats["perfumes"] += 1
                if limit and stats["perfumes"] >= limit:
                    return batch_id, dict(stats)
    return batch_id, dict(stats)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="pipeline")
    sub = ap.add_subparsers(dest="cmd", required=True)
    ex = sub.add_parser("extract", help="WDC N-Quads -> staging CSV")
    ex.add_argument("--input", required=True, help="WDC schema.org Product dump (.nq or .nq.gz)")
    ex.add_argument("--out", required=True, help="output CSV for staging_product")
    ex.add_argument("--source", default="wdc-schemaorg", help="data_source.key")
    ex.add_argument("--batch-id", default=None)
    ex.add_argument("--limit", type=int, default=None, help="stop after N perfumes (for testing)")
    args = ap.parse_args(argv)
    batch_id, stats = extract(args.input, args.out, args.source, args.batch_id, args.limit)
    print(json.dumps({"batch_id": batch_id, **stats}, indent=2), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
