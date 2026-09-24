"""
Kapitel 24: scripts/detect-anomalies.py (MEM-321).

Laeuft im CI-Job python-anomalies (python:3.12-slim), das Skript braucht nur
die Standardbibliothek:
    pip install pytest==8.4.2
    python -m pytest tests/Python
"""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'chapters/24-ausblick/scripts/detect-anomalies.py'

spec = importlib.util.spec_from_file_location('detect_anomalies', SCRIPT)
detect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detect)

CHAPTER_EXAMPLE = [120, 115, 118, 450, 122, 119, 890, 121]
WITHOUT_OUTLIERS = [120, 115, 118, 124, 122, 119, 116, 121]


def run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)


def flagged(values, **kwargs):
    return [v for v, flag in zip(values, detect.detect_performance_anomalies(values, **kwargs)) if flag]


def test_example_prints_the_chapter_output():
    result = run('--example')

    assert result.returncode == 0
    assert result.stdout == '[False, False, False, True, False, False, True, False]\n'


def test_series_without_outliers_has_no_anomalies():
    # Isolation Forest markierte hier 3 von 8 ("auto") bzw. 2 von 8 (0.25)
    assert flagged(WITHOUT_OUTLIERS) == []


def test_share_is_not_fixed_three_outliers_among_eight():
    # Isolation Forest mit contamination=0.25 fand zwei, mit 0.1 einen
    assert flagged([120, 115, 118, 450, 122, 400, 890, 121]) == [450, 400, 890]


def test_level_shift_reports_every_raised_value():
    # Isolation Forest + Grenze meldete hier nur 305 und 298
    assert flagged([100, 100, 102, 98, 101, 300, 305, 298, 302]) == [300, 305, 298, 302]


def test_min_factor_raises_the_floor():
    assert flagged(CHAPTER_EXAMPLE, min_factor=5.0) == [890]


def test_floor_is_strictly_above_min_factor_times_median():
    # Median 120, Grenze 240: genau 240 zaehlt nicht
    assert flagged([120, 120, 120, 120, 240, 120, 120, 120]) == []


def test_input_file_from_collect_metrics(tmp_path):
    rows = [{'timestamp': f't{i}', 'TTFB': v, 'TBT': 0, 'SI': 1500} for i, v in enumerate(CHAPTER_EXAMPLE)]
    rows[2]['TBT'] = 300
    path = tmp_path / 'metrics.json'
    path.write_text(json.dumps(rows))

    result = run('--input', str(path))
    lines = result.stdout.splitlines()

    assert result.returncode == 0
    assert 'Gemeldet wird: über 2.0 × Median' in lines
    assert '  Anomalie: Index 3: 450 (3.7 × Median)' in lines
    assert '  Anomalie: Index 6: 890 (7.4 × Median)' in lines
    # TBT mit Median 0: keine Grenze moeglich, also nicht bewertet statt "auffaellig"
    assert lines[lines.index('TBT') + 2] == '  Nicht bewertet: Median 0, kein Mindestabstand möglich'
    assert lines[lines.index('SI') + 3] == '  Keine Anomalien.'


def test_min_factor_option_reaches_the_analysis(tmp_path):
    path = tmp_path / 'metrics.json'
    path.write_text(json.dumps([{'TTFB': v} for v in CHAPTER_EXAMPLE]))

    lines = run('--input', str(path), '--min-factor', '5').stdout.splitlines()

    assert '  Anomalie: Index 6: 890 (7.4 × Median)' in lines
    assert not any('Index 3' in line for line in lines)
    assert 'Gemeldet wird: über 5.0 × Median' in lines


def test_fewer_than_five_values_are_not_analysed():
    assert detect.analyze_metrics([{'TTFB': 100}] * 4) == {}


@pytest.mark.parametrize('factor', ['1', '0.5'])
def test_min_factor_must_be_above_one(factor):
    result = run('--example', '--min-factor', factor)

    assert result.returncode == 2
    assert '--min-factor muss grösser als 1 sein' in result.stderr
