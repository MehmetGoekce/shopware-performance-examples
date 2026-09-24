#!/usr/bin/env python3
"""
Kapitel 24: Performance-Anomalie-Erkennung
Ausblick – Neue Technologien und Trends

Erkennt ungewöhnlich hohe Performance-Werte automatisch: auffällig ist,
was mehr als --min-factor × Median der Reihe beträgt (Vorgabe 2).

Warum kein Isolation Forest (scikit-learn 1.6.1, random_state=42, MEM-321):
Ein fester contamination-Wert gibt den Anteil vor. 0.25 markierte in einer
Reihe ohne Ausreisser 2 von 8 Werten und fand von drei Ausreissern unter
acht nur zwei; "auto" markierte in der Reihe ohne Ausreisser 3 von 8. Mit
der Mediangrenze dahinter trug das Modell nichts bei, bei einem
Niveausprung wählte es nur einen Teil der gleich hohen Werte aus.

Voraussetzungen: Python 3 (getestet mit 3.12), nur Standardbibliothek.
    Für --url zusätzlich: pip install requests

Verwendung:
    python detect-anomalies.py --input metrics.json   # aus collect-metrics.sh
    python detect-anomalies.py --example              # Beispiel aus Kapitel 24
    python detect-anomalies.py                        # Demo-Daten
    python detect-anomalies.py --url https://shop.example.com
"""

import argparse
import json
import sys
from datetime import datetime
from statistics import median
from typing import Dict, List

try:
    import requests
except ImportError:
    requests = None

# Felder aus collect-metrics.sh (Lighthouse über die PageSpeed API)
METRIC_NAMES = ['TTFB', 'FCP', 'LCP', 'CLS', 'TBT', 'SI']


def detect_performance_anomalies(metrics: list[float], min_factor: float = 2.0) -> list[bool]:
    """
    Erkennt Ausreisser in Performance-Metriken (höher = schlechter).

    Args:
        metrics: Liste von TTFB-Werten (oder andere Metriken)
        min_factor: gemeldet wird nur, was über min_factor × Median liegt

    Returns:
        Liste von Booleans: True = Anomalie
    """
    floor = min_factor * median(metrics)
    return [value > floor for value in metrics]


def example() -> None:
    """Beispiel aus Kapitel 24."""
    ttfb_values = [120, 115, 118, 450, 122, 119, 890, 121]  # ms
    anomalies = detect_performance_anomalies(ttfb_values)
    print(anomalies)


def fetch_metrics_from_crux(url: str) -> Dict:
    """
    Holt CrUX-Daten von der PageSpeed API.

    Args:
        url: Shop-URL

    Returns:
        Dict mit Core Web Vitals
    """
    if requests is None:
        print("Fehler: 'requests' Modul nicht installiert.")
        print("Für Live-Daten: pip install requests")
        return None

    api_url = f"https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url={url}&strategy=mobile"

    try:
        response = requests.get(api_url, timeout=60)
        data = response.json()

        metrics = {}
        if 'loadingExperience' in data:
            le = data['loadingExperience']
            if 'metrics' in le:
                for key, value in le['metrics'].items():
                    if 'percentile' in value:
                        metrics[key] = value['percentile']

        return metrics
    except Exception as e:
        print(f"Fehler beim Abrufen der Metriken: {e}")
        return None


def analyze_metrics(metrics_history: List[Dict], min_factor: float = 2.0) -> Dict:
    """
    Analysiert historische Metriken auf Anomalien.

    Args:
        metrics_history: Liste von Metrik-Snapshots
        min_factor: Mindestabstand zum Median als Faktor

    Returns:
        Analyse-Ergebnis je Metrik: 'anomalies' (Liste), oder 'skipped' mit Grund
    """
    results = {}

    for metric_name in METRIC_NAMES:
        values = [m.get(metric_name, m.get(metric_name.lower())) for m in metrics_history]
        values = [v for v in values if v is not None]

        if len(values) < 5:
            continue

        mid = median(values)
        if mid <= 0:
            # TBT oder CLS eines schnellen Shops: Median 0, die Grenze
            # min_factor × Median hielte jeden Wert über 0 für auffällig
            results[metric_name] = {'skipped': 'Median 0, kein Mindestabstand möglich'}
            continue

        flags = detect_performance_anomalies(values, min_factor)
        results[metric_name] = {
            'anomalies': [
                {'index': i, 'value': v, 'factor': round(v / mid, 1)}
                for i, (v, flag) in enumerate(zip(values, flags)) if flag
            ],
            'count': len(values),
            'median': round(mid, 2),
            'min': round(min(values), 2),
            'max': round(max(values), 2),
        }

    return results


def print_report(results: Dict, min_factor: float) -> None:
    """Gibt Anomalie-Report aus."""
    print("\n" + "=" * 60)
    print("PERFORMANCE ANOMALIE-REPORT")
    print("=" * 60)
    print(f"Generiert: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Gemeldet wird: über {min_factor} × Median")

    if not results:
        print("\nKeine Metrik mit mindestens 5 Werten.")
        return

    for metric, data in results.items():
        print(f"\n{metric}")
        print("-" * 40)
        if 'skipped' in data:
            print(f"  Nicht bewertet: {data['skipped']}")
            continue
        print(f"  Werte: {data['count']}, Median: {data['median']}, Bereich: {data['min']} - {data['max']}")
        if not data['anomalies']:
            print("  Keine Anomalien.")
        for anomaly in data['anomalies']:
            print(f"  Anomalie: Index {anomaly['index']}: {anomaly['value']} "
                  f"({anomaly['factor']} × Median)")

    print("\n" + "=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description='Performance-Anomalie-Erkennung (Vielfaches des Medians)'
    )
    parser.add_argument(
        '--url',
        help='Shop-URL für Live-Analyse (PageSpeed API)'
    )
    parser.add_argument(
        '--input',
        help='JSON-Datei mit historischen Metriken (collect-metrics.sh)'
    )
    parser.add_argument(
        '--example',
        action='store_true',
        help='Beispiel aus Kapitel 24 ausgeben'
    )
    parser.add_argument(
        '--min-factor',
        type=float,
        default=2.0,
        help='Gemeldet wird nur, was über diesem Vielfachen des Medians liegt (default: 2.0)'
    )

    args = parser.parse_args()
    if args.min_factor <= 1:
        parser.error('--min-factor muss grösser als 1 sein')

    if args.example:
        example()
        return

    if args.input:
        # Aus Datei laden
        with open(args.input, 'r') as f:
            metrics_history = json.load(f)
    elif args.url:
        # Live-Daten (nur aktueller Snapshot)
        print(f"Hole Metriken für: {args.url}")
        metrics = fetch_metrics_from_crux(args.url)
        if metrics:
            print(f"Gefundene Metriken: {metrics}")
            print("\nHinweis: Für Anomalie-Erkennung werden historische Daten benötigt.")
            print("Sammeln Sie Daten über Zeit mit: ./collect-metrics.sh")
        return
    else:
        # Demo-Daten
        print("Kein Input angegeben. Verwende Demo-Daten...")
        metrics_history = [
            {'TTFB': 120, 'LCP': 1800, 'FCP': 800, 'CLS': 0.05},
            {'TTFB': 115, 'LCP': 1750, 'FCP': 780, 'CLS': 0.04},
            {'TTFB': 118, 'LCP': 1820, 'FCP': 810, 'CLS': 0.05},
            {'TTFB': 450, 'LCP': 3500, 'FCP': 1200, 'CLS': 0.08},  # Anomalie!
            {'TTFB': 122, 'LCP': 1780, 'FCP': 795, 'CLS': 0.05},
            {'TTFB': 119, 'LCP': 1810, 'FCP': 805, 'CLS': 0.04},
            {'TTFB': 890, 'LCP': 4200, 'FCP': 1800, 'CLS': 0.15},  # Anomalie!
            {'TTFB': 121, 'LCP': 1795, 'FCP': 800, 'CLS': 0.05},
            {'TTFB': 117, 'LCP': 1770, 'FCP': 785, 'CLS': 0.04},
            {'TTFB': 123, 'LCP': 1830, 'FCP': 815, 'CLS': 0.05},
        ]

    results = analyze_metrics(metrics_history, args.min_factor)
    print_report(results, args.min_factor)


if __name__ == '__main__':
    main()
