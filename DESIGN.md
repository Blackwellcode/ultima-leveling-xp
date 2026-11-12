house: blackwellcode

Ab 2026-11-12 gilt der Blackwellcode-Hausstil (Skill `masterwork`, Datei `house/blackwellcode.md`, Richtung "Rail"). Design v2 unten beschreibt nur noch den Bestand bis zur Umstellung.

# Ultima – Design v2 ("Keynote")

Stand: 2026-11-09. Auftrag: rund statt eckig, deutlich hochwertiger, Apple-Keynote-Anmutung.

## 1. Leitbild

Ruhige, dunkle Glasflächen mit weichen Rundungen, viel Luft, eine klare Hauptaussage pro Blick.
Farbe nur als Akzent und als Signal. Bewegung nur, wenn sich etwas ändert.

| Prinzip | Umsetzung |
| :--- | :--- |
| Eine Hauptaussage | Die "Jetzt"-Karte ist das größte Element, alles andere ordnet sich unter |
| Rund und weich | Alle Flächen abgerundet (Panel 16, Karten 12, Pillen ganz rund, Knöpfe kreisrund) |
| Tiefe ohne Rahmenlinien | Weicher Schatten unter dem Panel, Karten heben sich durch hellere Fläche ab, Rand nur als Hauch (7 % Weiß) |
| Typografie trägt | Fira Sans Bold für Titel, Medium für Text, Light für Nebeninfos, klare Größenstufen |
| Farbe als Signal | Türkis-Blau-Verlauf für Fortschritt, Grün/Gelb/Rot nur für Zustände |
| Bewegung mit Sinn | Neuer Schritt blendet weich ein, Fortschritt gleitet statt springt |

## 2. Gestaltungs-Tokens

| Token | Wert |
| :--- | :--- |
| Fläche Panel | #0E0F12, 88 % deckend |
| Fläche Karte | Weiß 4 % über Panel, Rand Weiß 7 % |
| Fläche Hero-Karte | Verlauf #33D6B0 → #3BA7FF mit 14 % Deckkraft, Rand Akzent 35 % |
| Text primär / sekundär / tertiär | #F2F3F5 / #A0A4AE / #6B6F78 |
| Akzentverlauf | #33D6B0 → #3BA7FF |
| Status | Grün #4ADE80, Gelb #FACC15, Rot #FF6B5E, Blau Erholt #60A5FA |
| Radien | Panel 16, Karte 12, Pille Höhe/2, Knopf Kreis 24 |
| Abstände | Raster 4: Innenabstand Panel 16, Kartenabstand 10, Zeilenabstand 8 |
| Schrift | Titel 18 Bold, Hero 15 Medium, Text 13 Medium, Neben 11 Light, Überschrift 10 Bold in Großbuchstaben |

Die Schriftdateien liegen in EllesmereUI (`media\fonts\FiraSans *.ttf`). Fehlt EllesmereUI, gilt die Standardschrift.

## 3. Bauteile

```
╭──────────────────────────────────────────────╮
│ (◆)  16-19 Darkshore                 ( 16 )  │  Kopf: Logo-Kachel, Titel, Level-Pille
│      Schritt 12 von 147 · 8 %                 │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │  XP-Pille mit Verlauf, Erholt als heller Abschnitt
│ 57 %  ·  noch 6.871 XP              Erholt 1 % │
│ ╭──────────────────────────────────────────╮ │
│ │ REISE                                    │ │  Reise-Karte (nur bei Kontinentwechsel)
│ │  ●  Zum Hafen Stormwind        420 m     │ │  Zeitleiste mit Punkten und Linie
│ │  │                                       │ │
│ │  ○  Schiff nach Darkshore                │ │
│ ╰──────────────────────────────────────────╯ │
│ ╭──────────────────────────────────────────╮ │
│ │ JETZT                                    │ │  Hero-Karte mit Akzentverlauf
│ │ (!)  Annehmen: WANTED: Murkdeep!         │ │  Icon in runder Kachel, große Zeile
│ │      ( 320 m )  ( 0:50 )                 │ │  Meta-Pillen
│ │ ( ) Murlocs töten  ████████░░ 6/8         │ │  Ziele mit Kreis-Häkchen und Pillen-Balken
│ ╰──────────────────────────────────────────╯ │
│  Tipp: Click the Wanted Poster                │
│  DANACH                                       │
│  Abgeben: The Cliffspring River               │
│ ( Zz 1 % ) ( Essen ) ( Schlafsack ) ( Camp )  │  Chips als Pillen
│                         (‹) (›) (≡) (–)      │  Runde Glyph-Knöpfe
╰──────────────────────────────────────────────╯
        ╭───╮
        │ ↑ │   Pfeil: runde Glasscheibe mit Verlaufsring, darunter Pille "320 m · 0:50"
        ╰───╯
```

## 4. Technik

| Thema | Lösung |
| :--- | :--- |
| Rundungen | Eigene 9-Teile-Textur (Ecken, Kanten, Mitte) aus einer 2x-TGA mit Kantenglättung. Ecken behalten ihre Form bei jeder Größe |
| Ränder | Zweite 9-Teile-Textur als Ring, gleiche Rundung |
| Schatten | 9-Teile-Textur mit weichem Verlauf (Gauß), 24 px Auslauf |
| Verläufe | `SetGradient` mit `CreateColor`, im Forever-Client belegt (in 47 Addons genutzt) |
| Glyphen | Eigene TGA: Chevron links/rechts, Liste, Minus, Plus, Häkchen, Schiff |
| Bewegung | Einblenden über `AnimationGroup` (Alpha 0 → 1, 0,25 s), Balken gleiten per Interpolation |

## 5. Reisen über Kontinente (Phase 4, gleichzeitig)

- Fährverbindungen stammen aus der eigenen Datenbank: Schritte mit "boat to", "zeppelin to" und "tram to" samt Koordinaten,
  z. B. Stormwind → Darkshore, Menethil → Darkshore/Theramore, Ratchet ↔ Booty Bay, Durotar → Tirisfal/Stranglethorn.
- Planer: Liegt das nächste Ziel auf einem anderen Kontinent, wählt Ultima die Fähre mit dem kürzesten Gesamtweg
  (du → Hafen, Ankunftshafen → Ziel). Die Reise-Karte zeigt die Etappen, der Pfeil führt zum Hafen.
- Erledigt-Erkennung: Hafen erreicht, wenn näher als 15 Yards. Überfahrt erledigt, sobald du auf dem Zielkontinent bist.
- Grenzen v1: Flugpunkte und Ruhestein planen noch nicht mit. Ob Forever zusätzliche Fähren hat: "I don't know",
  neue Verbindungen kommen automatisch mit, sobald die Routen-Daten sie enthalten.

## 6. Abnahme

- Oberflächentest prüft runde Flächen, Reise-Karte, Pfeil auf Hafen.
- Reisetest: Mensch Level 16 in Stormwind, Ziel Darkshore ergibt "Zum Hafen Stormwind" und "Schiff nach Darkshore".
- Screenshot aus dem Spiel.
