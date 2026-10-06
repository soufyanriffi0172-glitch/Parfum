import csv
import os
import tempfile
import unittest

from pipeline.cli import extract
from pipeline.normalize import (clean_name, norm_text, normalize_gtin, parse_concentration, parse_gender,
                                parse_size_ml)
from pipeline.perfume_filter import is_perfume
from pipeline.wdc_reader import iter_graph_groups, iter_quads, parse_price, products_from_group

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "sample.nq")


class NormalizeTests(unittest.TestCase):
    def test_gtin(self):
        self.assertEqual(normalize_gtin("3348901250153"), "03348901250153")
        self.assertIsNone(normalize_gtin("3348901250154"))  # wrong check digit
        self.assertIsNone(normalize_gtin("12345"))
        self.assertIsNone(normalize_gtin(None))

    def test_size(self):
        self.assertEqual(parse_size_ml("Sauvage EDT 100ml"), 100)
        self.assertEqual(parse_size_ml("Sauvage 3,4 fl oz"), 101)
        self.assertEqual(parse_size_ml("Sauvage 10 cl"), 100)
        self.assertIsNone(parse_size_ml("Sauvage candle 250 g"))

    def test_concentration(self):
        self.assertEqual(parse_concentration("Bleu de Chanel Eau de Parfum"), "EDP")
        self.assertEqual(parse_concentration("Sauvage EDT"), "EDT")
        self.assertEqual(parse_concentration("Shalimar Parfum"), "Parfum")
        self.assertEqual(parse_concentration("Tobacco Vanille Extrait de Parfum"), "Extrait")
        self.assertIsNone(parse_concentration("Sauvage"))

    def test_gender(self):
        self.assertEqual(parse_gender("Sauvage for Men"), "M")
        self.assertEqual(parse_gender("Libre pour femme"), "F")
        self.assertEqual(parse_gender("CK One unisex"), "U")
        self.assertIsNone(parse_gender("Dior Homme Intense"))  # 'homme' alone is part of a real name

    def test_clean_name(self):
        d, k = clean_name("Dior Sauvage Eau de Toilette 100ml Spray for Men", "Dior")
        self.assertEqual((d, k), ("Sauvage", "sauvage"))
        d, k = clean_name("CHANEL Bleu de Chanel Eau de Parfum 50 ml", "Chanel")
        self.assertEqual(k, "bleu de chanel")
        d, k = clean_name("Dior Homme Intense Eau de Parfum", "Dior")
        self.assertEqual(k, "homme intense")
        d, k = clean_name("Guerlain Shalimar Parfum 50ml", "Guerlain")
        self.assertEqual(k, "shalimar")
        self.assertEqual(norm_text("Dolce & Gabbana"), "dolce and gabbana")


class FilterTests(unittest.TestCase):
    def test_accepts_perfume(self):
        self.assertTrue(is_perfume("Sauvage Eau de Toilette 100ml")[0])
        self.assertTrue(is_perfume("Libre", "Beauty > Fragrance")[0])

    def test_rejects_non_perfume(self):
        self.assertFalse(is_perfume("Sauvage Scented Candle 250 g")[0])
        self.assertFalse(is_perfume("Sauvage Gift Set 3-piece Eau de Toilette")[0])
        self.assertFalse(is_perfume("Trail running shoes size 42")[0])
        self.assertFalse(is_perfume("Body lotion Eau de Parfum scented 200 ml")[0])


class ReaderTests(unittest.TestCase):
    def test_price(self):
        self.assertEqual(parse_price("89,95"), 89.95)
        self.assertEqual(parse_price("1.299,00"), 1299.0)
        self.assertEqual(parse_price("1,299.00"), 1299.0)
        self.assertIsNone(parse_price("free"))
        self.assertIsNone(parse_price("0"))

    def test_products_resolve_nested_nodes(self):
        stats = {}
        with open(FIXTURE, encoding="utf-8") as fh:
            groups = list(iter_graph_groups(iter_quads(fh, stats)))
        self.assertEqual(stats["bad_lines"], 1)
        prods = [p for g, q in groups for p in products_from_group(g, q)]
        sauvage = next(p for p in prods if "Eau de Toilette 100ml" in p["name"])
        self.assertEqual(sauvage["brand"], "Dior")  # brand came from a nested node
        self.assertEqual(sauvage["price"], 89.95)
        self.assertEqual(sauvage["currency"], "EUR")
        bleu = next(p for p in prods if "Bleu" in p["name"])
        self.assertEqual(bleu["brand"], "Chanel")  # literal with language tag
        self.assertIn("Fragrance > Men", bleu["category"])  # \u003E unescaped


class EndToEndTests(unittest.TestCase):
    def test_extract(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "staging.csv")
            _batch, stats = extract(FIXTURE, out, batch_id="test-batch")
            with open(out, newline="", encoding="utf-8") as fh:
                rows = list(csv.DictReader(fh))
        self.assertEqual(stats["perfumes"], 2)
        self.assertEqual(stats["rejected_no_brand"], 1)
        self.assertGreaterEqual(stats["rejected_not_perfume"], 3)  # candle, gift set, shoes
        by_key = {r["name_key"]: r for r in rows}
        s = by_key["sauvage"]
        self.assertEqual((s["brand_key"], s["concentration"], s["size_ml"], s["gender"]), ("dior", "EDT", "100", "M"))
        self.assertEqual((s["gtin"], s["price"], s["currency"], s["domain"]), ("03348901250153", "89.95", "EUR", "shop-a.example"))
        b = by_key["bleu de chanel"]
        self.assertEqual((b["concentration"], b["size_ml"], b["currency"]), ("EDP", "50", "EUR"))
        self.assertNotIn("description", rows[0])  # descriptions are never persisted


if __name__ == "__main__":
    unittest.main()
