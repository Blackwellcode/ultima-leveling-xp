#!/usr/bin/env bash
# Baut Ultima Leveling XP: Hauptaddon plus Routen-Daten je Fraktion als Nachlade-Addons.
#   dist/UltimaLevelingXP     Code, Bibliotheken, Grafiken
#   dist/UltimaLevelingXP_A   Routen Allianz (+ fraktionsneutrale)
#   dist/UltimaLevelingXP_H   Routen Horde (+ fraktionsneutrale)
#   dist/UltimaLevelingXP_<Sprache>  Routen-Texte und NPC-Namen für Clients dieser Sprache
# Aufruf: bash tools/build.sh [--deploy] [--package]
#   --deploy   in den Spielordner spiegeln
#   --package  Release-Archiv dist/UltimaLevelingXP-<Version>.zip mit allen Addon-Ordnern
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
DIST="$ROOT/dist"
ADDONS_WIN="${ULTIMA_ADDONS:-E:\\World of Warcraft\\_forever_\\Interface\\AddOns}"
NAME=UltimaLevelingXP
VERSION=2.4.1
DEPLOY=0; PACKAGE=0
for a in "$@"; do
    case "$a" in
        --deploy) DEPLOY=1 ;;
        --package) PACKAGE=1 ;;
        *) echo "Unbekannte Option: $a" >&2; exit 2 ;;
    esac
done

fail() { echo "FEHLER: $*" >&2; exit 1; }

# 1. Datenbank erzeugen und pruefen
lua tools/convert.lua > dist.convert.log || { cat dist.convert.log; fail "Konverter"; }
grep -E '^Routen:' dist.convert.log
rm -f dist.convert.log
lua tools/verify-db.lua > /dev/null || { lua tools/verify-db.lua | grep FEHLER; fail "Datenbank-Pruefung"; }
echo "Datenbank ok"

# 2. Syntax und Tests
for f in $(find src -name '*.lua'); do luac -p "$f" || fail "Syntaxfehler in $f"; done
echo "luac ok: $(find src -name '*.lua' | wc -l) Dateien"
# Das Spiel läuft mit Lua 5.1, die Prüfung oben mit dem Lua dieser Maschine (5.4). Deshalb zusätzlich
# nach Sprachmitteln suchen, die es erst ab Lua 5.2 gibt (goto, Sprungmarken, Ganzzahl-Division,
# Bit-Operatoren, utf8-Bibliothek, table.unpack/table.pack, <const>/<close>).
LUA52=$(grep -nE '(^|[^[:alnum:]_])goto[[:space:]]+[[:alpha:]_]|::[[:alpha:]_][[:alnum:]_]*::|[^-/]//[^/]|[[:alnum:]_)] *(<<|>>) *[[:alnum:]_(]|utf8\.|table\.(unpack|pack)|<(const|close)>' $(find src -name '*.lua') | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' || true)
[ -z "$LUA52" ] || { echo "$LUA52"; fail "Sprachmittel ab Lua 5.2 in src (das Spiel nutzt Lua 5.1)"; }
echo "Lua 5.1: keine Sprachmittel ab 5.2 gefunden"
# Testlogs im Projekt (dist/.logs, ignoriert), nicht im System-Temp
LOGS="$DIST/.logs"
mkdir -p "$LOGS"
for t in test-engine test-ui test-locale test-talents test-paths; do
    lua "tools/$t.lua" > "$LOGS/$t.log" 2>&1 || { cat "$LOGS/$t.log"; fail "$t"; }
    echo "$t ok: $(grep -E ' OK( |$)' "$LOGS/$t.log" | grep -cv '^Alle') Pruefungen"
    rm -f "$LOGS/$t.log"
done
rmdir "$LOGS" 2>/dev/null || true

# 3. Hauptaddon
# Nur die Ausgaben dieses Skripts entfernen (Addon-Ordner und Archive), nie andere Dateien in dist/
[ "$(basename "$DIST")" = dist ] && [ -d "$ROOT/src" ] || fail "unerwarteter Ausgabeordner: $DIST"
rm -rf "${DIST:?}/$NAME" "${DIST:?}/${NAME}"_* "${DIST:?}/${NAME}.zip" "${DIST:?}/${NAME}-${VERSION}.zip"
MAIN="$DIST/$NAME"
mkdir -p "$MAIN/Textures"
cp -r libs "$MAIN/libs"
cp -r src/. "$MAIN/"
cp assets/branding/*.tga "$MAIN/Textures/"
# Schriften des Hausstils (Barlow, SIL OFL) mit Lizenztext im media-Ordner
mkdir -p "$MAIN/media"
cp assets/fonts/BarlowCondensed-SemiBold.ttf assets/fonts/Barlow-Medium.ttf assets/fonts/OFL.txt "$MAIN/media/"
mkdir -p "$MAIN/Data" && cp data/Travel.lua data/Flights.lua data/Talents.lua "$MAIN/Data/"
cp assets/CREDITS.txt assets/LICENSE-DATA.txt assets/LICENSE.txt "$MAIN/"
{
    cat <<EOF
## Interface: 16001
## Title: |cffff6a3dUltima|r Leveling XP
## Notes: Leveling companion for WoW Forever: routes, arrow, travel planner, bonus tracking, leveling talents.
## Notes-deDE: Leveling-Begleiter für WoW Forever: Routen, Pfeil, Reiseplaner, Boni im Blick, Leveling-Talente.
## Author: Blackwell Code
## Version: $VERSION
## IconTexture: Interface\\AddOns\\$NAME\\Textures\\ulx-minimap-icon
## OptionalDeps: Questie, EllesmereUI, EllesmereUINameplates, EllesmereUIUnitFrames
## SavedVariables: UltimaAccountDB
## SavedVariablesPerCharacter: UltimaCharDB

libs\\LibStub\\LibStub.lua
libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua
libs\\LibDataBroker-1.1\\LibDataBroker-1.1.lua
libs\\LibDBIcon-1.0\\LibDBIcon-1.0.lua
libs\\HereBeDragons\\HereBeDragons-2.0.lua
libs\\HereBeDragons\\HereBeDragons-Pins-2.0.lua

Core.lua
Locale\\Locale.lua
Locale\\enUS.lua
Locale\\deDE.lua
Locale\\frFR.lua
Locale\\esES.lua
Locale\\itIT.lua
Locale\\ptBR.lua
Locale\\ruRU.lua
Locale\\koKR.lua
Locale\\zhCN.lua
Locale\\zhTW.lua
Theme.lua
Kit.lua
Settings.lua
Engine\\Conditions.lua
Engine\\State.lua
Engine\\Progress.lua
Engine\\Text.lua
Engine\\Runner.lua
Engine\\Travel.lua
Engine\\Paths.lua
Engine\\Talents.lua
Data\\Travel.lua
Data\\Flights.lua
Data\\Talents.lua
Data\\Extra.lua
Live.lua
Auto.lua
Loot.lua
UI\\Bonus.lua
UI\\Panel.lua
UI\\Item.lua
Assist.lua
UI\\Nav.lua
UI\\Arrow.lua
UI\\Minimap.lua
UI\\Plates.lua
UI\\Talents.lua
UI\\Options.lua
UI\\Welcome.lua
Slash.lua
EOF
} > "$MAIN/$NAME.toc"

# 4. Routen-Daten je Fraktion
for f in A H; do
    label=$([ "$f" = A ] && echo Alliance || echo Horde)
    DATA="$DIST/${NAME}_$f"
    mkdir -p "$DATA"
    cp "data/Routes_$f.lua" "data/Routes_B.lua" "$DATA/"
    cp assets/CREDITS.txt assets/LICENSE-DATA.txt "$DATA/"
    cat > "$DATA/${NAME}_$f.toc" <<EOF
## Interface: 16001
## Title: |cffff6a3dUltima|r Leveling XP - Routes $label
## Notes: Route data, loaded by Ultima Leveling XP on demand.
## Author: Blackwell Code
## Version: $VERSION
## LoadOnDemand: 1
## Dependencies: $NAME

Routes_$f.lua
Routes_B.lua
EOF
done

# 4b. Routen-Texte und NPC-Namen je Client-Sprache (Nachlade-Addon, lädt nur im passenden Client)
LOCALE_ADDONS=""
for f in data/Text_*.lua; do
    loc=$(basename "$f" .lua); loc=${loc#Text_}
    DATA="$DIST/${NAME}_$loc"
    mkdir -p "$DATA"
    cp "$f" "$DATA/Text.lua"
    cp assets/CREDITS.txt assets/LICENSE-DATA.txt "$DATA/"
    cat > "$DATA/${NAME}_$loc.toc" <<EOF
## Interface: 16001
## Title: |cffff6a3dUltima|r Leveling XP - $loc
## Notes: Route texts and NPC names for $loc clients, loaded by Ultima Leveling XP on demand.
## Author: Blackwell Code
## Version: $VERSION
## LoadOnDemand: 1
## Dependencies: $NAME

Text.lua
EOF
    LOCALE_ADDONS="$LOCALE_ADDONS ${NAME}_$loc"
done

# 5. Jede TOC-Datei muss existieren
for toc in "$DIST"/*/*.toc; do
    dir=$(dirname "$toc")
    while IFS= read -r line; do
        entry=${line//\\//}
        [ -f "$dir/$entry" ] || fail "$(basename "$toc"): fehlt $entry"
    done < <(grep -vE '^#|^[[:space:]]*$' "$toc" | tr -d '\r')
done
echo "TOC ok: $(ls "$DIST"/*/*.toc | wc -l) Addons"
du -sh "$DIST"/* | sed 's#'"$DIST"'/##'

# 6. Verteilen
if [ "$DEPLOY" = 1 ]; then
    for d in "$NAME" "${NAME}_A" "${NAME}_H" $LOCALE_ADDONS; do
        set +e
        robocopy "$(cygpath -w "$DIST/$d")" "$ADDONS_WIN\\$d" //MIR //R:1 //W:1 //NFL //NDL //NP //NJH //NJS >/dev/null
        code=$?
        set -e
        [ "$code" -lt 8 ] || fail "robocopy $d Exit $code"
        echo "Verteilt: $d (robocopy Exit $code)"
    done
fi

# 7. Release-Archiv (Pfade mit "/", wie es CurseForge und Wago erwarten)
if [ "$PACKAGE" = 1 ]; then
    ZIP="$DIST/${NAME}-${VERSION}.zip"
    python - "$DIST" "$ZIP" "$NAME" "${NAME}_A" "${NAME}_H" $LOCALE_ADDONS <<'PY'
import os, sys, zipfile
dist, out, folders = sys.argv[1], sys.argv[2], sys.argv[3:]
count = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder in folders:
        for root, _, files in os.walk(os.path.join(dist, folder)):
            for f in sorted(files):
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, dist).replace(os.sep, "/"))
                count += 1
print(f"Archiv: {out} ({count} Dateien, {os.path.getsize(out)} Bytes)")
PY
fi
