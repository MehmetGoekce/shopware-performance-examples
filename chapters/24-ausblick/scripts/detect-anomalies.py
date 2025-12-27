#!/usr/bin/env python3
"""
Kapitel 24: ML-basierte Performance-Anomalie-Erkennung
Ausblick – Neue Technologien und Trends

Erkennt ungewöhnliche Performance-Werte automatisch.
Nutzt Isolation Forest für Outlier-Detection.

Voraussetzungen:
    pip install numpy scikit-learn requests

Verwendung:
    python detect-anomalies.py --url https://shop.example.com
    python detect-anomalies.py --input metrics.json
"""

import argparse
import json
import sys
from datetime import datetime
from typing import List, Dict, Tuple

try:
    import numpy as np
    from sklearn.ensemble import IsolationForest
except ImportError:
    print("Fehler: Abhängigkeiten nicht installiert.")
    print("Bitte ausführen: pip install numpy scikit-learn")
    sys.exit(1)

try:
    import requests
except ImportError:
    requests = None


class PerformanceAnomalyDetector:
    """
    Erkennt Anomalien in Performance-Metriken mittels Isolation Forest.

    Isolation Forest funktioniert gut für:
    - Univariate Daten (einzelne Metrik)
    - Ohne Training auf "normale" Daten
    - Echzeit-Erkennung möglich
    """

    def __init__(self, contamination: float = 0.1):
        """
        Args:
            contamination: Erwarteter Anteil an Anomalien (0.0-0.5)
                          0.1 = 10% der Daten sind Anomalien
        """
        self.contamination = contamination
        self.model = IsolationForest(
            contamination=contamination,
            random_state=42,
            n_estimators=100
        )

    def detect(self, values: List[float]) -> List[Dict]:
        """
        Erkennt Anomalien in einer Liste von Werten.

        Args:
            values: Liste von Metriken (z.B. TTFB in ms)

        Returns:
            Liste von Anomalie-Informationen
        """
        if len(values) < 10:
            print("Warnung: Weniger als 10 Datenpunkte. Ergebnisse unzuverlässig.")

        # Reshape für sklearn
        X = np.array(values).reshape(-1, 1)

        # Fit und Predict
        predictions = self.model.fit_predict(X)

        # Anomalie-Score (-1 = Anomalie, 1 = Normal)
        anomalies = []
        for i, (value, pred) in enumerate(zip(values, predictions)):
            if pred == -1:
                # Berechne Z-Score für Kontext
                mean = np.mean(values)
                std = np.std(values)
                z_score = (value - mean) / std if std > 0 else 0

                anomalies.append({
                    'index': i,
                    'value': value,
                    'z_score': round(z_score, 2),
                    'severity': self._classify_severity(z_score),
                    'direction': 'high' if value > mean else 'low'
                })

        return anomalies

    def _classify_severity(self, z_score: float) -> str:
        """Klassifiziert Schweregrad basierend auf Z-Score."""
        abs_z = abs(z_score)
        if abs_z > 3:
            return 'critical'
        elif abs_z > 2:
            return 'warning'
        else:
            return 'info'


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


def analyze_metrics(metrics_history: List[Dict]) -> Dict:
    """
    Analysiert historische Metriken auf Anomalien.

    Args:
        metrics_history: Liste von Metrik-Snapshots

    Returns:
        Analyse-Ergebnis mit Anomalien pro Metrik
    """
    detector = PerformanceAnomalyDetector(contamination=0.1)
    results = {}

    # Metriken extrahieren
    metric_names = ['TTFB', 'FCP', 'LCP', 'FID', 'INP', 'CLS']

    for metric_name in metric_names:
        values = [m.get(metric_name, m.get(metric_name.lower())) for m in metrics_history]
        values = [v for v in values if v is not None]

        if len(values) >= 5:
            anomalies = detector.detect(values)
            if anomalies:
                results[metric_name] = {
                    'anomalies': anomalies,
                    'count': len(anomalies),
                    'mean': round(np.mean(values), 2),
                    'std': round(np.std(values), 2),
                    'min': round(min(values), 2),
                    'max': round(max(values), 2)
                }

    return results


def print_report(results: Dict) -> None:
    """Gibt Anomalie-Report aus."""
    print("\n" + "=" * 60)
    print("PERFORMANCE ANOMALIE-REPORT")
    print("=" * 60)
    print(f"Generiert: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    if not results:
        print("Keine Anomalien gefunden.")
        return

    for metric, data in results.items():
        print(f"\n{metric}")
        print("-" * 40)
        print(f"  Durchschnitt: {data['mean']}")
        print(f"  Std-Abweichung: {data['std']}")
        print(f"  Bereich: {data['min']} - {data['max']}")
        print(f"  Anomalien: {data['count']}")

        for anomaly in data['anomalies']:
            severity_icon = {
                'critical': '🔴',
                'warning': '🟡',
                'info': '🔵'
            }.get(anomaly['severity'], '⚪')

            print(f"    {severity_icon} Index {anomaly['index']}: "
                  f"{anomaly['value']} (Z-Score: {anomaly['z_score']}, "
                  f"{anomaly['direction']})")

    print("\n" + "=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description='Performance-Anomalie-Erkennung mit ML'
    )
    parser.add_argument(
        '--url',
        help='Shop-URL für Live-Analyse (PageSpeed API)'
    )
    parser.add_argument(
        '--input',
        help='JSON-Datei mit historischen Metriken'
    )
    parser.add_argument(
        '--contamination',
        type=float,
        default=0.1,
        help='Erwarteter Anomalie-Anteil (0.0-0.5, default: 0.1)'
    )

    args = parser.parse_args()

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

    results = analyze_metrics(metrics_history)
    print_report(results)


if __name__ == '__main__':
    main()
