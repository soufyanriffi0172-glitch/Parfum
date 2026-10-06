"""Decide whether a schema.org Product is a single perfume (not a candle, gift set, body lotion, ...)."""
import re

_I = re.IGNORECASE
POS_NAME = re.compile(
    r"\b(eau de (parfum|toilette|cologne)|edp|edt|edc|parfum|parfums|perfume|parf[uü]m|profumo|perfumy|"
    r"cologne|extrait|colonia|parfym)\b", _I)
POS_CAT = re.compile(r"(fragrance|perfume|parfum|parf[uü]m|geur|cologne|duft)", _I)
NEG = re.compile(
    r"\b(candles?|kaars|kaarsen|diffuser|room spray|shower gel|douchegel|body (lotion|wash|mist|cream|spray)|"
    r"deodorant|deo|soap|zeep|shampoo|hair mist|gift ?set|geschenkset|giftset|coffret|set of|travel set|"
    r"miniature set|sample set|refill|navulling|reed|incense|car freshener|aftershave balm|\d+\s?-?\s?piece)\b",
    _I)
SIZE = re.compile(r"\d+(?:[.,]\d+)?\s?(ml|cl|oz)\b", _I)

MIN_SCORE = 3


def perfume_score(name, category=None, description=None):
    """Return (score, reasons). A product counts as perfume when score >= MIN_SCORE."""
    score, why = 0, []
    if POS_NAME.search(name or ""):
        score += 3
        why.append("name:perfume-word")
    if category and POS_CAT.search(category):
        score += 3  # a fragrance category on its own is enough: many shops name a product just "Libre"
        why.append("category:fragrance")
    if description and POS_NAME.search(description[:400]):
        score += 1
        why.append("description:perfume-word")
    if SIZE.search(name or ""):
        score += 1
        why.append("name:size")
    if NEG.search(name or ""):
        score -= 4
        why.append("name:negative")
    if category and NEG.search(category):
        score -= 2
        why.append("category:negative")
    return score, why


def is_perfume(name, category=None, description=None):
    s, why = perfume_score(name, category, description)
    return s >= MIN_SCORE, s, why
