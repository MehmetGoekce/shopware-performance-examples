#!/bin/bash
#
# Problem 10: Zu viele Plugins diagnostizieren
# Kapitel 22: Die 20 häufigsten Performance-Probleme
#

SHOP_PATH="${2:-.}"

echo "=== Problem 10: Plugin-Audit ==="
echo ""

if [[ ! -f "${SHOP_PATH}/bin/console" ]]; then
    echo "⚠ Shopware nicht gefunden in: ${SHOP_PATH}"
    echo "Bitte SHOP_PATH als Parameter angeben."
    exit 1
fi

# Plugin-Liste abrufen
echo "1. Aktive Plugins..."
PLUGIN_LIST=$(php "${SHOP_PATH}/bin/console" plugin:list --json 2>/dev/null)

if [[ -z "${PLUGIN_LIST}" ]]; then
    echo "   ⚠ Plugin-Liste konnte nicht abgerufen werden"
    exit 1
fi

# Zählen
TOTAL=$(echo "${PLUGIN_LIST}" | php -r '${p}=json_decode(file_get_contents("php://stdin")); echo count(${p});' 2>/dev/null)
ACTIVE=$(echo "${PLUGIN_LIST}" | php -r '${p}=json_decode(file_get_contents("php://stdin")); echo count(array_filter(${p}, fn(${x}) => ${x}->active));' 2>/dev/null)
INSTALLED=$(echo "${PLUGIN_LIST}" | php -r '${p}=json_decode(file_get_contents("php://stdin")); echo count(array_filter(${p}, fn(${x}) => ${x}->installedAt !== null));' 2>/dev/null)

echo ""
echo "   Gesamt:      ${TOTAL} Plugins"
echo "   Installiert: ${INSTALLED} Plugins"
echo "   Aktiv:       ${ACTIVE} Plugins"
echo ""

# Warnung bei zu vielen Plugins
if [[ "${ACTIVE}" -gt 30 ]]; then
    echo "   ✗ Kritisch: Mehr als 30 aktive Plugins!"
    echo "     Performance-Impact: Sehr hoch"
elif [[ "${ACTIVE}" -gt 20 ]]; then
    echo "   ⚠ Warnung: Mehr als 20 aktive Plugins"
    echo "     Performance-Impact: Mittel"
else
    echo "   ✓ Plugin-Anzahl im grünen Bereich"
fi

# Plugin-Details
echo ""
echo "2. Aktive Plugins (sortiert nach Name)..."
echo ""
echo "${PLUGIN_LIST}" | php -r '
${plugins} = json_decode(file_get_contents("php://stdin"));
${active} = array_filter(${plugins}, fn(${p}) => ${p}->active);
usort(${active}, fn(${a}, ${b}) => strcmp(${a}->name, ${b}->name));
foreach (${active} as ${p}) {
    ${version} = ${p}->version ?? "?";
    ${author} = ${p}->author ?? "Unknown";
    printf("   %-40s v%-10s %s\n", ${p}->name, ${version}, ${author});
}
' 2>/dev/null

# Deaktivierte aber installierte Plugins
echo ""
echo "3. Installiert aber nicht aktiv (können entfernt werden)..."
echo ""
echo "${PLUGIN_LIST}" | php -r '
${plugins} = json_decode(file_get_contents("php://stdin"));
${inactive} = array_filter(${plugins}, fn(${p}) => ${p}->installedAt !== null && !${p}->active);
if (empty(${inactive})) {
    echo "   Keine inaktiven Plugins gefunden.\n";
} else {
    foreach (${inactive} as ${p}) {
        echo "   - " . ${p}->name . "\n";
    }
    echo "\n   Entfernen mit: bin/console plugin:uninstall PluginName\n";
}
' 2>/dev/null

# Performance-Impact-Analyse
echo ""
echo "4. Performance-Impact-Schätzung..."
echo ""

# Bekannte Performance-kritische Plugins
HEAVY_PLUGINS=("SwagPayPal" "KlarnaPayments" "SwagSocialShopping" "SwagEnterpriseSearchPlatform")

echo "${PLUGIN_LIST}" | php -r '
${plugins} = json_decode(file_get_contents("php://stdin"));
${heavy} = ["SwagPayPal", "SwagSocialShopping", "SwagEnterpriseSearch"];
${active} = array_filter(${plugins}, fn(${p}) => ${p}->active);

${impact} = "Niedrig";
${heavy}Count = 0;
foreach (${active} as ${p}) {
    if (in_array(${p}->name, ${heavy})) {
        ${heavy}Count++;
    }
}

${active}Count = count(${active});
if (${active}Count > 30 || ${heavy}Count > 2) {
    ${impact} = "Hoch";
} elseif (${active}Count > 20 || ${heavy}Count > 1) {
    ${impact} = "Mittel";
}

echo "   Geschätzter Performance-Impact: " . ${impact} . "\n";
echo "   Ressourcenintensive Plugins: " . ${heavy}Count . "\n";
' 2>/dev/null

# Empfehlungen
echo ""
echo "=== Empfehlung ==="
echo ""

if [[ "${ACTIVE}" -gt 30 ]]; then
    echo "Dringend Plugin-Anzahl reduzieren:"
    echo ""
    echo "1. Nicht genutzte Plugins identifizieren und deaktivieren"
    echo "2. Ähnliche Funktionen konsolidieren"
    echo "3. Custom-Entwicklung für spezifische Features erwägen"
    echo ""
    echo "Deaktivieren: bin/console plugin:deactivate PluginName"
    echo "Entfernen:    bin/console plugin:uninstall PluginName"
    exit 1
else
    echo "Plugin-Anzahl ist akzeptabel."
    echo "Tipp: Regelmäßig ungenutzte Plugins entfernen."
    exit 0
fi
