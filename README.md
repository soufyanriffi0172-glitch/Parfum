# Scentshelf

Een geuren-site (Fragrantica-achtig, maar interactiever) met jouw eigen shelf, seizoensgebonden browsen,
geurverloop in de tijd en een catalogus die vanzelf groeit.

In deze map staat alles wat Claude Code nodig heeft om het project stap voor stap te bouwen.

## Wat zit erin
| Map / bestand | Waarvoor |
|---|---|
| `CLAUDE.md` | Vaste instructies voor Claude Code: stack, regels, juridische grenzen, werkwijze |
| `docs/ARCHITECTURE.md` | Hoe het systeem in elkaar zit en waarom |
| `docs/ROADMAP.md` | Fases met telkens een "klaar als"-punt |
| `docs/BACKLOG.md` | De takenlijst, in volgorde, met acceptatiecriteria |
| `docs/DATA-SOURCES.md` | Welke databronnen mogen, en onder welke voorwaarden |
| `pipeline/`, `tests/`, `db/` | De importketen (Python) en de database (SQL) |
| `prototype/` | Het eerdere prototype (alleen als voorbeeld van ontwerp en gedrag) |
| `web/` | Hier komt de echte website (taak T-002) |

## Beginnen met Claude Code
1. **Installeer Claude Code** volgens de officiële documentatie:
   https://docs.claude.com/en/docs/claude-code/overview (daar staat ook welk abonnement of welke toegang je nodig hebt).
2. **Zet de map in git** (aanrader, zodat je alles kunt terugdraaien):
   ```bash
   cd scentshelf
   git init && git add . && git commit -m "Startpunt"
   ```
3. **Start Claude Code in deze map** (nooit vanuit je thuismap):
   ```bash
   claude
   ```
   Claude Code leest `CLAUDE.md` in de projectmap automatisch.
4. **Eerste opdracht** (kopieer dit):
   > Lees CLAUDE.md en docs/BACKLOG.md. Leg in het Nederlands in een paar zinnen uit wat je gaat doen en begin dan met taak T-001. Vraag me om een beslissing als het nodig is.
5. **Werk taak voor taak.** Laat Claude Code na elke taak de tests draaien en een korte samenvatting geven.
   Taken met **[owner]** vragen iets van jou: een account, een keuze of een controle van data.

## Tips
- Houd taken klein: één taak per sessie en per commit.
- Laat het eerst een plan uitleggen bij grotere stappen, en pas daarna code schrijven.
- Zet nooit geheime sleutels in de code of in git. Gebruik `.env` (staat niet in git) en `.env.example`.
- Wijzigt er iets aan de werkwijze of de commando's? Laat Claude Code `CLAUDE.md` bijwerken.

## Let op
- De SQL is nog nooit tegen een echte database gedraaid; taak T-001 doet dat als eerste.
- Er zit geen Fragrantica-data in en er wordt niet gescrapet. Zie `docs/DATA-SOURCES.md`.
- Controleer licenties en laat het databankrecht beoordelen voordat je publiek gaat.
