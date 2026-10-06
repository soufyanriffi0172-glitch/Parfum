"""Stream a Web Data Commons N-Quads file and turn schema.org Product markup into plain dicts.

Assumption: quads that belong to one web page (same graph IRI) are contiguous in the file, which is how
WDC writes its dumps. Nested nodes (brand, offers) are resolved inside one page.
Descriptions are read ONLY so the perfume filter can classify a product. They are never written out.
"""
import gzip
import itertools
import re

RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
SCHEMA = re.compile(r"^https?://(?:www\.)?schema\.org/(.+)$")
PRODUCT_TYPES = {"product", "individualproduct", "someproducts"}

QUAD = re.compile(
    r'^(?:<(?P<si>[^>]*)>|(?P<sb>_:\S+))\s+'
    r'<(?P<p>[^>]*)>\s+'
    r'(?:<(?P<oi>[^>]*)>|(?P<ob>_:\S+)|"(?P<ol>(?:[^"\\]|\\.)*)"(?:@[A-Za-z0-9-]+|\^\^<[^>]*>)?)'
    r'(?:\s+(?:<(?P<gi>[^>]*)>|(?P<gb>_:\S+)))?\s*\.\s*$'
)
_ESC = re.compile(r"\\(u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|[tbnrf\"'\\])")
_ESC_MAP = {"t": "\t", "b": "\b", "n": "\n", "r": "\r", "f": "\f", '"': '"', "'": "'", "\\": "\\"}


def _unescape(text):
    return _ESC.sub(
        lambda m: chr(int(m.group(1)[1:], 16)) if m.group(1)[0] in "uU" else _ESC_MAP[m.group(1)], text
    )


def open_any(path):
    if str(path).endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "rt", encoding="utf-8", errors="replace")


def iter_quads(lines, stats=None):
    """Yield (subject, predicate, kind, value, graph). kind is 'node' or 'lit'."""
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = QUAD.match(line)
        if not m:
            if stats is not None:
                stats["bad_lines"] = stats.get("bad_lines", 0) + 1
            continue
        subj = ("i:" + m.group("si")) if m.group("si") is not None else m.group("sb")
        if m.group("ol") is not None:
            kind, val = "lit", _unescape(m.group("ol"))
        else:
            kind = "node"
            val = ("i:" + m.group("oi")) if m.group("oi") is not None else m.group("ob")
        graph = m.group("gi") or m.group("gb") or ""
        yield subj, m.group("p"), kind, val, graph


def iter_graph_groups(quads):
    for graph, group in itertools.groupby(quads, key=lambda q: q[4]):
        yield graph, list(group)


def _local(iri):
    m = SCHEMA.match(iri)
    return m.group(1) if m else None


def _first_lit(node, *props):
    for p in props:
        for kind, val in node.get(p, []):
            if kind == "lit" and val.strip():
                return val.strip()
    return None


def _named(nodes, node, prop):
    """Value of a property that may be a literal or a nested node with a name (e.g. brand)."""
    for kind, val in node.get(prop, []):
        if kind == "lit" and val.strip():
            return val.strip()
        if kind == "node" and val in nodes:
            n = _first_lit(nodes[val], "name")
            if n:
                return n
    return None


def parse_price(raw):
    if raw is None:
        return None
    s = re.sub(r"[^\d.,]", "", str(raw))
    if not s:
        return None
    if "," in s and "." in s:
        s = s.replace(".", "").replace(",", ".") if s.rfind(",") > s.rfind(".") else s.replace(",", "")
    elif "," in s:
        s = s.replace(",", ".")
    try:
        v = float(s)
    except ValueError:
        return None
    return round(v, 2) if 0 < v < 5000 else None


def _offer_price(nodes, product):
    for kind, val in product.get("offers", []):
        if kind != "node" or val not in nodes:
            continue
        offer = nodes[val]
        price = _first_lit(offer, "price", "lowprice")
        cur = _first_lit(offer, "pricecurrency")
        if price is None:  # price may sit in a nested priceSpecification
            for k2, v2 in offer.get("pricespecification", []):
                if k2 == "node" and v2 in nodes:
                    price = _first_lit(nodes[v2], "price")
                    cur = cur or _first_lit(nodes[v2], "pricecurrency")
        p = parse_price(price)
        if p is not None:
            return p, ((cur or "").upper()[:3] or None)
    return None, None


def products_from_group(graph, quads):
    nodes, types = {}, {}
    for s, p, kind, val, _g in quads:
        if p == RDF_TYPE:
            loc = _local(val[2:]) if val.startswith("i:") else None
            if loc:
                types.setdefault(s, set()).add(loc.lower())
            continue
        loc = _local(p)
        if loc:
            nodes.setdefault(s, {}).setdefault(loc.lower(), []).append((kind, val))
    for s, tset in types.items():
        if not (tset & PRODUCT_TYPES) or s not in nodes:
            continue
        n = nodes[s]
        name = _first_lit(n, "name")
        if not name:
            continue
        price, currency = _offer_price(nodes, n)
        gtin = _first_lit(n, "gtin13", "gtin", "gtin12", "gtin14", "gtin8", "ean")
        cats = [v for k, v in n.get("category", []) if k == "lit"]
        yield {
            "page_url": graph if graph and not graph.startswith("_:") else None,
            "name": name,
            "brand": _named(nodes, n, "brand") or _named(nodes, n, "manufacturer"),
            "gtin_raw": gtin,
            "sku": _first_lit(n, "sku", "mpn"),
            "category": " > ".join(cats)[:300] if cats else None,
            "price": price,
            "currency": currency,
            "_description": (_first_lit(n, "description") or "")[:600],  # classification only, never stored
        }
