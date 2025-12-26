/**
 * Third-Party Scripts Audit
 * Kapitel 5: CSS und JavaScript optimieren
 *
 * Analysiert alle Third-Party Scripts und deren Performance-Impact.
 * Verwendung: In Chrome DevTools Console (F12) einfügen
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

// ============================================================
// 1. Third-Party Scripts identifizieren
// ============================================================

/**
 * Listet alle externen Scripts mit Größe und Ladezeit
 */
function auditThirdPartyScripts() {
    console.log('%c🔍 THIRD-PARTY SCRIPTS AUDIT', 'font-size: 16px; font-weight: bold; color: #FF5722;');

    const hostname = location.hostname;
    const resources = performance.getEntriesByType('resource');

    // Scripts von externen Domains
    const thirdPartyScripts = resources
        .filter(r => r.initiatorType === 'script')
        .filter(r => {
            try {
                const url = new URL(r.name);
                return url.hostname !== hostname;
            } catch {
                return false;
            }
        })
        .map(r => {
            const url = new URL(r.name);
            return {
                domain: url.hostname,
                path: url.pathname.split('/').pop().substring(0, 30),
                size: Math.round(r.transferSize / 1024),
                duration: Math.round(r.duration),
                blocked: Math.round(r.responseStart - r.startTime)
            };
        })
        .sort((a, b) => b.size - a.size);

    // Nach Domain gruppieren
    const byDomain = {};
    thirdPartyScripts.forEach(s => {
        if (!byDomain[s.domain]) {
            byDomain[s.domain] = { count: 0, totalSize: 0, totalDuration: 0 };
        }
        byDomain[s.domain].count++;
        byDomain[s.domain].totalSize += s.size;
        byDomain[s.domain].totalDuration += s.duration;
    });

    // Gesamt-Statistiken
    const totalSize = thirdPartyScripts.reduce((sum, s) => sum + s.size, 0);
    const totalDuration = thirdPartyScripts.reduce((sum, s) => sum + s.duration, 0);

    console.log(`\n📊 Gefunden: ${thirdPartyScripts.length} Third-Party Scripts`);
    console.log(`📦 Gesamt-Größe: ${totalSize} KB`);
    console.log(`⏱️ Gesamt-Ladezeit: ${totalDuration}ms`);

    console.log('\n%c📋 Nach Domain gruppiert:', 'font-weight: bold;');
    console.table(Object.entries(byDomain).map(([domain, data]) => ({
        Domain: domain,
        'Anzahl': data.count,
        'Größe (KB)': data.totalSize,
        'Dauer (ms)': data.totalDuration
    })).sort((a, b) => b['Größe (KB)'] - a['Größe (KB)']));

    console.log('\n%c📋 Alle Scripts:', 'font-weight: bold;');
    console.table(thirdPartyScripts.map(s => ({
        Domain: s.domain,
        Script: s.path,
        'Größe (KB)': s.size,
        'Dauer (ms)': s.duration
    })));

    return { scripts: thirdPartyScripts, byDomain };
}

// Ausführen:
auditThirdPartyScripts();


// ============================================================
// 2. Bekannte Third-Party Scripts kategorisieren
// ============================================================

/**
 * Kategorisiert Third-Party Scripts nach Typ
 */
function categorizeThirdParty() {
    console.log('%c🏷️ THIRD-PARTY KATEGORISIERUNG', 'font-size: 16px; font-weight: bold; color: #9C27B0;');

    const categories = {
        analytics: {
            name: 'Analytics & Tracking',
            domains: ['google-analytics.com', 'googletagmanager.com', 'analytics.google.com', 'hotjar.com', 'clarity.ms', 'matomo'],
            scripts: []
        },
        advertising: {
            name: 'Werbung & Retargeting',
            domains: ['facebook.net', 'fbevents', 'doubleclick.net', 'googlesyndication.com', 'criteo', 'adroll', 'taboola'],
            scripts: []
        },
        social: {
            name: 'Social Media',
            domains: ['platform.twitter.com', 'connect.facebook.net', 'platform.linkedin.com', 'pinterest'],
            scripts: []
        },
        chat: {
            name: 'Chat & Support',
            domains: ['zendesk', 'intercom', 'tawk.to', 'livechat', 'crisp', 'drift'],
            scripts: []
        },
        payment: {
            name: 'Payment',
            domains: ['paypal', 'stripe', 'klarna', 'adyen'],
            scripts: []
        },
        other: {
            name: 'Sonstige',
            domains: [],
            scripts: []
        }
    };

    const scripts = document.querySelectorAll('script[src]');

    scripts.forEach(script => {
        try {
            const url = new URL(script.src);
            if (url.hostname === location.hostname) return;

            let categorized = false;
            for (const [key, cat] of Object.entries(categories)) {
                if (key === 'other') continue;
                if (cat.domains.some(d => url.hostname.includes(d) || url.href.includes(d))) {
                    cat.scripts.push({
                        domain: url.hostname,
                        src: url.pathname.split('/').pop().substring(0, 30)
                    });
                    categorized = true;
                    break;
                }
            }
            if (!categorized) {
                categories.other.scripts.push({
                    domain: url.hostname,
                    src: url.pathname.split('/').pop().substring(0, 30)
                });
            }
        } catch {}
    });

    console.log('\n');
    for (const [key, cat] of Object.entries(categories)) {
        if (cat.scripts.length > 0) {
            const emoji = {
                analytics: '📊',
                advertising: '📢',
                social: '👥',
                chat: '💬',
                payment: '💳',
                other: '❓'
            }[key];

            console.log(`%c${emoji} ${cat.name}: ${cat.scripts.length}`, 'font-weight: bold;');
            cat.scripts.forEach(s => console.log(`   - ${s.domain}`));
            console.log('');
        }
    }

    return categories;
}

// Ausführen:
categorizeThirdParty();


// ============================================================
// 3. Performance Impact berechnen
// ============================================================

/**
 * Schätzt den Performance-Impact der Third-Party Scripts
 */
function estimateThirdPartyImpact() {
    console.log('%c⚡ THIRD-PARTY PERFORMANCE IMPACT', 'font-size: 16px; font-weight: bold; color: #FF9800;');

    const resources = performance.getEntriesByType('resource');
    const hostname = location.hostname;

    // First-Party vs Third-Party
    const firstParty = resources.filter(r => {
        try {
            return new URL(r.name).hostname === hostname;
        } catch { return true; }
    });

    const thirdParty = resources.filter(r => {
        try {
            return new URL(r.name).hostname !== hostname;
        } catch { return false; }
    });

    const fpSize = firstParty.reduce((s, r) => s + r.transferSize, 0) / 1024;
    const tpSize = thirdParty.reduce((s, r) => s + r.transferSize, 0) / 1024;
    const totalSize = fpSize + tpSize;

    const fpDuration = Math.max(...firstParty.map(r => r.responseEnd)) || 0;
    const tpDuration = Math.max(...thirdParty.map(r => r.responseEnd)) || 0;

    console.log('\n%c📊 Ressourcen-Verteilung:', 'font-weight: bold;');
    console.log(`  First-Party: ${Math.round(fpSize)} KB (${Math.round(fpSize/totalSize*100)}%)`);
    console.log(`  Third-Party: ${Math.round(tpSize)} KB (${Math.round(tpSize/totalSize*100)}%)`);

    console.log('\n%c⏱️ Ladezeit-Impact:', 'font-weight: bold;');
    console.log(`  First-Party fertig: ${Math.round(fpDuration)}ms`);
    console.log(`  Third-Party fertig: ${Math.round(tpDuration)}ms`);

    // Bewertung
    const tpPercent = Math.round(tpSize/totalSize*100);
    if (tpPercent > 50) {
        console.log('\n%c❌ Third-Party macht >50% aus - kritisch!', 'color: #F44336; font-weight: bold;');
    } else if (tpPercent > 30) {
        console.log('\n%c⚠️ Third-Party macht >30% aus - optimierbar', 'color: #FF9800; font-weight: bold;');
    } else {
        console.log('\n%c✅ Third-Party unter Kontrolle (<30%)', 'color: #4CAF50; font-weight: bold;');
    }

    // Empfehlungen
    console.log('\n%c💡 Optimierungs-Empfehlungen:', 'font-weight: bold;');
    console.log('  1. Analytics/Tracking nach User-Interaktion laden');
    console.log('  2. Chat-Widgets on-demand bei Klick laden');
    console.log('  3. GTM mit setTimeout(2000) verzögern');
    console.log('  4. Unnötige Scripts komplett entfernen');

    return {
        firstParty: { size: fpSize, duration: fpDuration },
        thirdParty: { size: tpSize, duration: tpDuration }
    };
}

// Ausführen:
estimateThirdPartyImpact();


// ============================================================
// 4. Vollständiger Third-Party Audit
// ============================================================

function fullThirdPartyAudit() {
    console.clear();
    console.log('%c🔍 VOLLSTÄNDIGER THIRD-PARTY AUDIT', 'font-size: 20px; font-weight: bold; color: #FF5722;');
    console.log('═══════════════════════════════════════════════════════\n');

    auditThirdPartyScripts();
    console.log('\n');

    categorizeThirdParty();
    console.log('\n');

    estimateThirdPartyImpact();

    console.log('\n═══════════════════════════════════════════════════════');
}

// Für vollständigen Audit:
// fullThirdPartyAudit();
