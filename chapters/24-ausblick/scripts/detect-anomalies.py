#!/usr/bin/env python3
"""
Kapitel 24: Performance-Anomalie-Erkennung
Ausblick – Neue Technologien und Trends

Erkennt ungewöhnlich hohe Performance-Werte automatisch: auffällig ist,
was mehr als --min-factor × Median der Reihe beträgt (Vorgabe 2).

Grenze der Regel: Sie findet Ausreisser, solange weniger als die Hälfte der
Reihe erhöht ist. Liegt ein Niveausprung (etwa nach einem Deploy) über der
halben Reihe, wandert der Median mit, und nichts wird gemeldet. Dafür die
neue Reihe gegen den Median eines Referenzzeitraums (z. B. Vorwoche) halten.

Warum kein Isolation Forest (scikit-learn 1.6.1, random_state=42, MEM-321):
Ein fester contamination-Wert gibt den Anteil vor. 0.25 markierte in einer
Reihe ohne Ausreisser 2 von 8 Werten und fand von drei Ausreissern unter
acht nur zwei. "auto" markierte in jeder gemessenen Reihe ohne Ausreisser
mindestens 2 von 8 Werten und nach einem Niveausprung (fünf Werte um 100,
vier um 300 ms) auch normale Werte. Mit der Mediangrenze dahinter trug das
Modell nichts bei.

Voraussetzungen: Python 3 (getestet mit 3.12), nur Standardbibliothek.

Verwendung:
    python detect-anomalies.py --input metrics.json   # aus collect-metrics.sh
    python detect-anomalies.py --example              # Beispiel aus Kapitel 24
    python detect-anomalies.py                        # Demo-Daten

Exit-Codes: 0 = keine Anomalie, 1 = mindestens eine Anomalie,
            2 = Aufruf- oder Eingabefehler
"""

import argparse
import json
import math
from datetime import datetime
from statistics import median
from typing import Dict, List

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
    """Beispiel aus Kapitel 24 (Faktor 2)."""
    ttfb_values = [120, 115, 118, 450, 122, 119, 890, 121]  # ms
    anomalies = detect_performance_anomalies(ttfb_values)
    print(anomalies)


def is_number(value) -> bool:
    """Endliche Zahl; bool zählt nicht (JSON true wäre sonst 1)."""
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def analyze_metrics(metrics_history: List[Dict], min_factor: float = 2.0) -> Dict:
    """
    Analysiert historische Metriken auf Anomalien.

    Args:
        metrics_history: Liste von Metrik-Snapshots
        min_factor: Mindestabstand zum Median als Faktor

    Returns:
        Analyse-Ergebnis je Metrik: 'anomalies' (Liste), oder 'skipped' mit Grund.
        'measurement' ist die Position in metrics_history, ab 1 gezählt.
    """
    results = {}

    for metric_name in METRIC_NAMES:
        rows = [(i, m.get(metric_name)) for i, m in enumerate(metrics_history, 1)]
        rows = [(i, v) for i, v in rows if is_number(v)]
        values = [v for _, v in rows]

        if len(values) < 5:
            continue

        mid = median(values)
        if mid <= 0:
            # TBT oder CLS eines schnellen Shops: Median 0, die Grenze
            # min_factor × Median hielte jeden Wert über 0 für auffällig
            results[metric_name] = {'skipped': 'Median ≤ 0, kein Mindestabstand möglich'}
            continue

        flags = detect_performance_anomalies(values, min_factor)
        results[metric_name] = {
            'anomalies': [
                {
                    'measurement': i,
                    'timestamp': metrics_history[i - 1].get('timestamp'),
                    'value': v,
                    'factor': round(v / mid, 1),
                }
                for (i, v), flag in zip(rows, flags) if flag
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
            when = f" ({anomaly['timestamp']})" if anomaly['timestamp'] else ""
            print(f"  Anomalie: Messung {anomaly['measurement']}{when}: {anomaly['value']} "
                  f"({anomaly['factor']} × Median)")

    print("\n" + "=" * 60)


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Performance-Anomalie-Erkennung (Vielfaches des Medians)'
    )
    parser.add_argument(
        '--input',
        help='JSON-Datei mit historischen Metriken (collect-metrics.sh)'
    )
    parser.add_argument(
        '--example',
        action='store_true',
        help='Beispiel aus Kapitel 24 ausgeben (immer mit Faktor 2)'
    )
    parser.add_argument(
        '--min-factor',
        type=float,
        default=2.0,
        help='Gemeldet wird nur, was über diesem Vielfachen des Medians liegt (default: 2.0)'
    )

    args = parser.parse_args()
    if not args.min_factor > 1:
        parser.error('--min-factor muss grösser als 1 sein')

    if args.example:
        example()
        return 0

    if args.input:
        # Aus Datei laden
        try:
            with open(args.input, 'r') as f:
                metrics_history = json.load(f)
        except (OSError, ValueError) as e:
            parser.exit(2, f"Fehler: {args.input} nicht lesbar: {e}\n")
        if not isinstance(metrics_history, list) or not all(isinstance(m, dict) for m in metrics_history):
            parser.exit(2, f"Fehler: {args.input} ist keine Liste von Messungen (collect-metrics.sh)\n")
    else:
        # Demo-Daten
        print("Kein Input angegeben. Verwende Demo-Daten...")
        metrics_history = [
            {'TTFB': 120, 'LCP': 1800, 'FCP': 800, 'CLS': 0.05},
            {'TTFB': 115, 'LCP': 1750, 'FCP': 780, 'CLS': 0.04},
            {'TTFB': 118, 'LCP': 1820, 'FCP': 810, 'CLS': 0.05},
            {'TTFB': 450, 'LCP': 3500, 'FCP': 1200, 'CLS': 0.08},  # Anomalie nur TTFB (LCP 1,9 × Median)
            {'TTFB': 122, 'LCP': 1780, 'FCP': 795, 'CLS': 0.05},
            {'TTFB': 119, 'LCP': 1810, 'FCP': 805, 'CLS': 0.04},
            {'TTFB': 890, 'LCP': 4200, 'FCP': 1800, 'CLS': 0.15},  # Anomalie in allen vier
            {'TTFB': 121, 'LCP': 1795, 'FCP': 800, 'CLS': 0.05},
            {'TTFB': 117, 'LCP': 1770, 'FCP': 785, 'CLS': 0.04},
            {'TTFB': 123, 'LCP': 1830, 'FCP': 815, 'CLS': 0.05},
        ]

    results = analyze_metrics(metrics_history, args.min_factor)
    print_report(results, args.min_factor)
    return 1 if any(data.get('anomalies') for data in results.values()) else 0


if __name__ == '__main__':
    raise SystemExit(main())
