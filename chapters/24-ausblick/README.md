# Kapitel 24: Ausblick – Neue Technologien und Trends

Code-Beispiele und Konfigurationen für zukunftsweisende Performance-Technologien.

## Inhalt

| Thema | Dateien | Beschreibung |
|-------|---------|--------------|
| HTTP/3 & QUIC | `config/nginx-http3.conf` | HTTP/3-Delta zum vHost aus Anhang C (per `include`, kein eigener server-Block) |
| Edge Computing | `edge-functions/` | Cloudflare Workers Beispiele |
| Anomalie-Erkennung | `scripts/detect-anomalies.py` | Werte über einem Vielfachen des Medians (MEM-321) |
| INP-Optimierung | `scripts/analyze-inp.js` | Browser-Script für INP-Analyse |
| Green IT | `scripts/measure-carbon.sh` | CO2 je Seitenaufruf schätzen (Website Carbon, SWDM v4) |

## Voraussetzungen

### HTTP/3 mit Nginx

Braucht nginx ab 1.25.1 mit HTTP/3-Modul und den vHost aus Anhang C. Ubuntu
24.04 (nginx 1.24) hat das Modul nicht. Ubuntu 26.04 hat es, bringt aber PHP 8.5
statt 8.3 (Pfade aus Kapitel 9 anpassen). Die nginx.org-Pakete haben es, aber
weder `snippets/` noch `sites-available/`/`sites-enabled/`, und ihre
`nginx.conf` liest nur `conf.d/`: dort die Ordner anlegen und
`include /etc/nginx/sites-enabled/*;` in den http-Block setzen. Die Datei ist
kein eigener vHost, sondern ergänzt den aus Anhang C. Eine frühere Fassung als
eigener vHost muss vorher aus `sites-enabled/` raus:

```bash
nginx -V 2>&1 | grep -o with-http_v3_module
sudo cp config/nginx-http3.conf /etc/nginx/snippets/shopware-http3.conf
# In /etc/nginx/sites-available/shopware.conf, im server-Block für 443,
# direkt unter die beiden listen-Zeilen:
#     include snippets/shopware-http3.conf;
sudo nginx -t 2>&1 | grep -E 'emerg|conflicting server name'
sudo systemctl reload nginx
```

Ohne das Modul: HTTP/3 am CDN terminieren (Kapitel 11).

### Edge Functions

```bash
# Cloudflare Wrangler CLI
npm install -g wrangler
wrangler login

# Deployment
cd edge-functions/ab-testing
wrangler deploy
```

### Anomalie-Erkennung

Braucht nur Python 3 (Standardbibliothek, getestet mit 3.12, `tests/Python`).
Auffällig ist, was über `--min-factor` × Median der Reihe liegt (Vorgabe 2).
Kein Isolation Forest: Mit festem `contamination`-Wert gibt er den Anteil der
Anomalien vor, und mit `"auto"` markierte er auch in Reihen ohne Ausreisser
Werte (Messung im Skriptkopf).

```bash
# Beispiel aus Kapitel 24
python scripts/detect-anomalies.py --example

# Script ausführen (--url braucht zusätzlich: pip install requests)
python scripts/detect-anomalies.py --url https://shop.example.com
```

## Quick Start

### 1. HTTP/3 aktivieren (Cloudflare)

Einfachste Variante - keine Server-Änderungen nötig:

1. Domain zu Cloudflare hinzufügen
2. Speed → Settings → Protocol Optimization → HTTP/3 einschalten (Stand September 2026)
3. Fertig

### 2. Edge-basiertes A/B-Testing

```bash
cd edge-functions/ab-testing
cp wrangler.toml.example wrangler.toml
# wrangler.toml anpassen
wrangler deploy
```

A/B- und Geo-Worker schicken dem Origin nur einen Header. Shopware muss ihn
auswerten und in den Cache-Key aufnehmen (Kapitel 20), sonst liefert der
HTTP-Cache die zuerst gecachte Variante oder Währung an alle.

### 3. CO2 je Seitenaufruf schätzen

Der Endpoint `/site` der Website Carbon API (URL rein, Messung dort) ist seit
dem 14.07.2025 nicht mehr öffentlich (HTTP 401). Das Skript fragt `/data` mit
der übertragenen Seitengrösse ab; die messen Sie mit Lighthouse:

```bash
lighthouse https://shop.example.com --output=json --output-path=lh.json
./scripts/measure-carbon.sh --views 100000 lh.json      # oder direkt: 1500000 (Bytes)
./scripts/measure-carbon.sh --green lh.json             # Hosting mit erneuerbarer Energie
```

Braucht `curl` und `jq`. Exit-Codes: `0` Ergebnis, `1` Aufruffehler, `2` API
oder Werkzeug gescheitert. SWDM v4 rechnet linear in Bytes: Das Ergebnis ist
eine Modellschätzung, keine Messung.

### 4. Performance-Anomalien erkennen

```bash
# Historische Daten sammeln (7 Tage empfohlen)
./scripts/collect-metrics.sh https://shop.example.com

# Anomalien analysieren
python scripts/detect-anomalies.py --input metrics.json
```

## Verzeichnisstruktur

```
chapters/24-ausblick/
├── README.md
├── config/
│   └── nginx-http3.conf        # HTTP/3-Delta zum vHost aus Anhang C
├── edge-functions/
│   ├── ab-testing/             # A/B-Testing auf der Edge
│   │   ├── src/index.js        # mehrere Tests, Gewichtung
│   │   ├── src/minimal.js      # Fassung aus dem Buch
│   │   └── wrangler.toml.example
│   ├── geo-routing/            # Geo-basiertes Routing
│   │   ├── src/index.js        # Währung, Sprache, Override-Cookie
│   │   ├── src/minimal.js      # Fassung aus dem Buch
│   │   └── wrangler.toml.example
│   └── rate-limit/             # Suche/Login je IP bremsen (Rate Limiting Binding)
│       ├── src/index.js        # Fassung aus dem Buch
│       └── wrangler.toml.example
└── scripts/
    ├── detect-anomalies.py     # Anomalie-Erkennung (Median)
    ├── analyze-inp.js          # INP-Analyse im Browser
    ├── measure-carbon.sh       # CO2-Schätzung aus übertragenen Bytes
    └── collect-metrics.sh      # Metrik-Sammlung für detect-anomalies.py
```

## Zukunftstechnologien im Überblick

### Was jetzt schon produktionsreif ist

| Technologie | Status | Empfehlung |
|-------------|--------|------------|
| HTTP/3 | ✅ Produktionsreif | Cloudflare aktivieren |
| INP (statt FID) | ✅ Seit März 2024 | Unbedingt messen |
| Edge Computing | ✅ Produktionsreif | Für A/B, Geo, Bot-Schutz |
| AVIF-Bilder | ✅ rund 94 % der Browser ([caniuse](https://caniuse.com/avif), Safari ab 16.4) | Erst messen: im Test-Shop von Kapitel 4 war AVIF etwa so gross wie JPEG (Encoder-abhängig) |

### Was beobachtet werden sollte

| Technologie | Status | Ausblick |
|-------------|--------|----------|
| WebAssembly | ✅ in allen aktuellen Browsern ([caniuse](https://caniuse.com/wasm)) und in Cloudflare Workers | Kein Standardfall im Shop-Frontend, nur für rechenintensive Teile |
| AI-gestützte Optimierung | 🔄 Frühe Phase | Anomalie-Erkennung jetzt möglich |
| Composable Commerce | 🔄 Enterprise-only | Für große Shops relevant |

## Weiterführende Ressourcen

- [HTTP/3 Explained](https://http3-explained.haxx.se/)
- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [web.dev INP Guide](https://web.dev/inp/)
- [Website Carbon Calculator](https://websitecarbon.com/)

---

**Professionelles Zukunfts-Audit:** [memotech.ch/performance-audit](https://memotech.ch/performance-audit)
