"""Turn messy shop strings into stable keys: brand_key, name_key, concentration, size, gender, GTIN."""
import re
import unicodedata

_I = re.IGNORECASE


def strip_accents(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def norm_text(s):
    s = strip_accents(s or "").lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def normalize_gtin(raw):
    """Return a zero-padded 14-digit GTIN when the GS1 check digit is valid, else None."""
    if not raw:
        return None
    d = re.sub(r"\D", "", str(raw))
    if len(d) not in (8, 12, 13, 14):
        return None
    body, check = d[:-1], int(d[-1])
    total = sum(int(c) * (3 if i % 2 == 0 else 1) for i, c in enumerate(reversed(body)))
    if (10 - total % 10) % 10 != check:
        return None
    return d.zfill(14)


SIZE_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s?(ml|cl|fl\.?\s?oz|oz)\b", _I)


def parse_size_ml(text):
    m = SIZE_RE.search(text or "")
    if not m:
        return None
    v, unit = float(m.group(1).replace(",", ".")), m.group(2).lower().replace(" ", "")
    ml = v * 10 if unit == "cl" else v * 29.5735 if "oz" in unit else v
    ml = round(ml)
    return ml if 5 <= ml <= 500 else None


CONC = [
    ("Extrait", re.compile(r"\bextrait(?: de parfum)?\b", _I)),
    ("EDP", re.compile(r"\beau de parfum\b|\bedp\b|\be\.d\.p\b", _I)),
    ("EDT", re.compile(r"\beau de toilette\b|\bedt\b", _I)),
    ("EDC", re.compile(r"\beau de cologne\b|\bedc\b", _I)),
    ("Parfum", re.compile(r"\bparfum\b|\bperfume\b|\bparf[uü]m\b", _I)),
]


def parse_concentration(text):
    for label, rx in CONC:
        if rx.search(text or ""):
            return label
    return None


_MEN = re.compile(r"\b(pour homme|for men|for him|men'?s|mens|voor heren|herren)\b", _I)
_WOMEN = re.compile(r"\b(pour femme|for women|for her|women'?s|womens|voor dames|damen)\b", _I)
_UNI = re.compile(r"\bunisex\b", _I)


def parse_gender(text):
    t = text or ""
    m, w, u = bool(_MEN.search(t)), bool(_WOMEN.search(t)), bool(_UNI.search(t))
    if u or (m and w):
        return "U"
    return "M" if m else "F" if w else None


_STRIP = [
    SIZE_RE,
    re.compile(r"\beau de (parfum|toilette|cologne)\b|\bextrait(?: de parfum)?\b|\b(edp|edt|edc)\b", _I),
    _MEN, _WOMEN, _UNI,
    re.compile(r"\b(spray|vaporisateur|vapo|natural|tester|unboxed|nieuw|new)\b", _I),
]


def clean_name(name, brand=None):
    """Return (display_name, name_key) with brand, size, concentration and gender words removed."""
    t = name or ""
    for rx in _STRIP:
        t = rx.sub(" ", t)
    if brand:
        t = re.sub(re.escape(brand), " ", t, count=1, flags=_I)
    # a bare 'parfum' is only a concentration word when something else remains
    stripped = re.sub(r"\b(parfum|perfume|parf[uü]m)\b", " ", t, flags=_I)
    if norm_text(stripped):
        t = stripped
    t = re.sub(r"[\-–—|,/()\[\]]+", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"^(by|for|pour|de|voor)\s+|\s+(by|for|pour|de|voor)$", "", t, flags=_I).strip()
    if not norm_text(t):
        t = re.sub(r"\s+", " ", SIZE_RE.sub(" ", name or "")).strip()
    display = t.title() if (t.islower() or t.isupper()) else t
    return display, norm_text(t)
