#!/usr/bin/env bash
#
# check-images.sh
#
# Problem 4: Unoptimierte Bilder.
# Kapitel 22: Die 20 haeufigsten Performance-Probleme
#
# Wichtig zur Messung: geprueft werden die Bild-URLs, die wirklich im HTML
# stehen. Shopware liefert in der Storefront Thumbnails aus
# (/thumbnail/<pfad>_800x800.jpg), nicht die Originaldatei aus /media/.
# Wer "curl -I .../media/bild.jpg" misst, misst das Original — also meist
# nicht die Datei, die der Besucher laedt.
#
# Verwendung:
#   ./check-images.sh [SHOP_URL] [SHOP_PATH]
#
# Exit-Codes:
#   0 = nichts Auffaelliges
#   1 = Auffaelligkeiten gefunden
#   64 = Aufruffehler

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check-images.sh [SHOP_URL] [SHOP_PATH]

Prueft die Bilder der Startseite auf Groesse, modernes Format und
Lazy-Loading.

Argumente:
  SHOP_URL    Startseite des Shops. Default: http://localhost
  SHOP_PATH   Wird nicht ausgewertet; nur der Einheitlichkeit halber.

Umgebungsvariablen:
  MAX_IMAGE_KB   Ab dieser Groesse gilt ein Bild als gross. Default: 200
                 Das ist ein Erfahrungswert, kein Standard.
  MAX_IMAGES     Wie viele Bilder gemessen werden. Default: 10
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

# Aufrufkonvention aller Skripte dieses Kapitels: $1 = SHOP_URL, $2 = SHOP_PATH.
# Dieses Skript braucht nur die URL; $2 wird bewusst entgegengenommen und
# nicht ausgewertet, damit run-all-diagnostics.sh alle gleich aufrufen kann.
SHOP_URL="${1:-http://localhost}"
SHOP_URL="${SHOP_URL%/}"
MAX_IMAGE_KB="${MAX_IMAGE_KB:-200}"
MAX_IMAGES="${MAX_IMAGES:-10}"

echo "=== Problem 4: Bilder ==="
echo
echo "Prueft: ${SHOP_URL}"
echo

HTML=$(curl -sS -L "${SHOP_URL}/") || {
    echo "Shop nicht erreichbar: ${SHOP_URL}" >&2
    exit 1
}

absolutise() {
    case "$1" in
        http://*|https://*) printf '%s\n' "$1" ;;
        //*)                printf '%s:%s\n' "${SHOP_URL%%:*}" "$1" ;;
        /*)                 printf '%s%s\n' "${SHOP_URL}" "$1" ;;
        *)                  printf '%s/%s\n' "${SHOP_URL}" "$1" ;;
    esac
}

IMG_TAGS=$(printf '%s\n' "${HTML}" | grep -oE '<img[^>]*>' || true)
IMG_COUNT=$(printf '%s' "${IMG_TAGS}" | grep -c '<img' || true)

ISSUES=0

echo "1. Bilder im HTML"
echo "   Gefunden: ${IMG_COUNT}"
if [[ "${IMG_COUNT}" -eq 0 ]]; then
    echo "   Nichts zu messen."
    exit 0
fi

echo
echo "2. Uebertragene Groessen (die ersten ${MAX_IMAGES})"
LARGE=0
MEASURED=0
while IFS= read -r tag; do
    [[ -z "${tag}" ]] && continue
    [[ "${MEASURED}" -ge "${MAX_IMAGES}" ]] && break
    src=$(printf '%s' "${tag}" | grep -oE 'src="[^"]*"' | head -1 | sed 's/^src="//; s/"$//')
    [[ -z "${src}" ]] && continue
    case "${src}" in data:*) continue ;; esac
    url=$(absolutise "${src}")
    bytes=$(curl -sS -o /dev/null -L -w '%{size_download}' "${url}" 2>/dev/null || echo 0)
    [[ "${bytes}" -eq 0 ]] && continue
    kb=$(( bytes / 1024 ))
    MEASURED=$((MEASURED + 1))
    name="${src##*/}"
    name="${name%%\?*}"
    if [[ "${kb}" -ge "${MAX_IMAGE_KB}" ]]; then
        printf '   %-44s %5s KB  gross\n' "${name:0:44}" "${kb}"
        LARGE=$((LARGE + 1))
    else
        printf '   %-44s %5s KB\n' "${name:0:44}" "${kb}"
    fi
done <<< "${IMG_TAGS}"

if [[ "${MEASURED}" -eq 0 ]]; then
    echo "   Keine messbare Bild-URL gefunden."
elif [[ "${LARGE}" -gt 0 ]]; then
    echo "   ${LARGE} von ${MEASURED} Bildern ab ${MAX_IMAGE_KB} KB."
    ISSUES=$((ISSUES + 1))
else
    echo "   Alle ${MEASURED} gemessenen Bilder unter ${MAX_IMAGE_KB} KB."
fi

echo
echo "3. Thumbnails oder Originale?"
THUMBS=$(printf '%s' "${IMG_TAGS}" | grep -c '/thumbnail/' || true)
MEDIA=$(printf '%s' "${IMG_TAGS}" | grep -c '/media/' || true)
echo "   Thumbnail-URLs: ${THUMBS}"
echo "   Direkte /media/-URLs: ${MEDIA}"
if [[ "${MEDIA}" -gt 0 && "${THUMBS}" -eq 0 ]]; then
    echo "   Es werden Originale ausgeliefert. Thumbnails erzeugen mit:"
    echo "     bin/console media:generate-thumbnails"
    ISSUES=$((ISSUES + 1))
fi

echo
echo "4. Modernes Bildformat"
FIRST_IMG=$(printf '%s' "${IMG_TAGS}" | grep -oE 'src="[^"]*\.(jpe?g|png)[^"]*"' | head -1 | sed 's/^src="//; s/"$//' || true)
if [[ -z "${FIRST_IMG}" ]]; then
    echo "   Kein JPEG/PNG im HTML — moeglicherweise laeuft schon alles ueber WebP/AVIF."
else
    hdrs=$(curl -sS -o /dev/null -D - -L -H 'Accept: image/avif,image/webp,*/*' "$(absolutise "${FIRST_IMG}")" 2>/dev/null | tr -d '\r')
    ctype=$(printf '%s\n' "${hdrs}" | awk 'BEGIN{IGNORECASE=1} tolower($1)=="content-type:" { $1=""; sub(/^ /,""); v=$0 } END{print v}')
    vary=$(printf '%s\n' "${hdrs}" | awk 'BEGIN{IGNORECASE=1} tolower($1)=="vary:" { $1=""; sub(/^ /,""); v=$0 } END{print v}')
    echo "   Angefragt mit Accept: image/avif,image/webp"
    echo "   Geliefert als: ${ctype:-unbekannt}"
    case "${ctype}" in
        image/webp|image/avif)
            echo "   Der Server liefert ein modernes Format aus."
            if [[ "${vary}" != *Accept* ]]; then
                echo "   ABER: kein 'Vary: Accept'. Ein Proxy oder CDN davor liefert dieses"
                echo "   Bild sonst auch an Clients aus, die kein WebP koennen."
                ISSUES=$((ISSUES + 1))
            fi
            ;;
        *)
            echo "   Kein WebP/AVIF. Shopware 6.6 konvertiert selbst nicht."
            ISSUES=$((ISSUES + 1))
            ;;
    esac
fi

echo
echo "5. Lazy Loading und feste Abmessungen"
LAZY=$(printf '%s' "${IMG_TAGS}" | grep -c 'loading="lazy"' || true)
DIMS=$(printf '%s' "${IMG_TAGS}" | grep -cE 'width="[0-9]+"' || true)
echo "   loading=\"lazy\": ${LAZY} von ${IMG_COUNT}"
echo "   width-Attribut:  ${DIMS} von ${IMG_COUNT}"
if [[ "${LAZY}" -eq 0 ]]; then
    echo "   Kein Bild laedt verzoegert. Fuer Bilder unterhalb des sichtbaren"
    echo "   Bereichs spart loading=\"lazy\" Bandbreite — das LCP-Bild selbst"
    echo "   bekommt dagegen loading=\"eager\" und fetchpriority=\"high\"."
    ISSUES=$((ISSUES + 1))
fi
if [[ "${DIMS}" -lt "${IMG_COUNT}" ]]; then
    echo "   Ohne width/height reserviert der Browser keinen Platz — das kostet CLS."
fi

echo
echo "=== Ergebnis ==="
echo

if [[ "${ISSUES}" -eq 0 ]]; then
    echo "Bei den Bildern der Startseite faellt nichts auf."
    exit 0
fi

cat <<'EOF'
Ansatzpunkte:

  Thumbnails: Shopware erzeugt sie beim Upload. Fehlen sie fuer Altbestaende:
    bin/console media:generate-thumbnails

  Moderne Formate: Shopware 6.6 konvertiert nicht selbst. Zwei Wege:
    - FroshPlatformThumbnailProcessor schreibt die Thumbnail-URLs auf das
      Original plus Query-Parameter um; konvertieren muss dann der
      dahinterliegende Bilddienst (imgproxy, Cloudflare Polish, Bunny
      Optimizer). Ohne einen solchen Dienst passiert nichts.
    - Oder ein CDN mit Bildoptimierung davorschalten.

  Wer die Umschaltung per .htaccess loesen will, braucht beide Bedingungen —
  sonst liefert der Rewrite eine 404 fuer jedes Bild ohne .webp-Geschwister:

    AddType image/webp .webp
    RewriteCond %{HTTP_ACCEPT} image/webp
    RewriteCond %{REQUEST_FILENAME} (.+)\.(jpe?g|png)$
    RewriteCond %1.webp -f
    RewriteRule (.+)\.(jpe?g|png)$ $1.webp [T=image/webp,E=webp:1,L]
    Header append Vary Accept env=webp

  Die mittlere Bedingung haelt den Basisnamen in %1 fest. Die verbreitete
  Kurzform "RewriteCond %{REQUEST_FILENAME}.webp -f" prueft dagegen auf
  "bild.jpg.webp" und passt nicht zur Regel, die "bild.webp" ausliefert.
  Fertig zum Kopieren steht das in config/apache-webp.conf.

  Das Vary gehoert dazu, sonst cachen Proxys das WebP fuer alle.
  Unter Nginx wirkt .htaccess nicht; dort uebernimmt das eine map-Direktive
  auf $http_accept zusammen mit try_files.
EOF
exit 1
