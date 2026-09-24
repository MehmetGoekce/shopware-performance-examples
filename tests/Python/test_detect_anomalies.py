"""
Kapitel 24: scripts/detect-anomalies.py (MEM-321).

Laeuft im CI-Job python (python:3.12-slim), das Skript braucht nur die
Standardbibliothek:
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


def run_input(tmp_path, rows, *args):
    path = tmp_path / 'metrics.json'
    path.write_text(json.dumps(rows))
    return run('--input', str(path), *args)


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


def test_level_shift_below_half_the_series_is_reported():
    # Isolation Forest + Grenze meldete hier nur 305 und 298
    assert flagged([100, 100, 102, 98, 101, 300, 305, 298, 302]) == [300, 305, 298, 302]


def test_level_shift_over_half_the_series_is_not_reported():
    # Grenze der Regel (Skriptkopf, Kapitel 24): der Median wandert mit
    assert flagged([100, 100, 102, 98, 300, 305, 298, 302]) == []
    assert flagged([100, 100, 102, 98, 300, 305, 298, 302, 301]) == []


def test_min_factor_raises_the_floor():
    assert flagged(CHAPTER_EXAMPLE, min_factor=5.0) == [890]


def test_floor_is_strictly_above_min_factor_times_median():
    # Median 120, Grenze 240: genau 240 zaehlt nicht
    assert flagged([120, 120, 120, 120, 240, 120, 120, 120]) == []


def test_input_file_from_collect_metrics(tmp_path):
    rows = [{'timestamp': f't{i}', 'TTFB': v, 'TBT': 0, 'SI': 1500} for i, v in enumerate(CHAPTER_EXAMPLE, 1)]
    rows[2]['TBT'] = 300

    result = run_input(tmp_path, rows)
    lines = result.stdout.splitlines()

    assert result.returncode == 1
    assert 'Gemeldet wird: über 2.0 × Median' in lines
    assert lines[lines.index('TTFB') + 2:lines.index('TTFB') + 5] == [
        '  Werte: 8, Median: 120.5, Bereich: 115 - 890',
        '  Anomalie: Messung 4 (t4): 450 (3.7 × Median)',
        '  Anomalie: Messung 7 (t7): 890 (7.4 × Median)',
    ]
    # TBT mit Median 0: keine Grenze moeglich, also nicht bewertet statt "auffaellig"
    assert lines[lines.index('TBT') + 2] == '  Nicht bewertet: Median ≤ 0, kein Mindestabstand möglich'
    assert lines[lines.index('SI') + 2:lines.index('SI') + 4] == [
        '  Werte: 8, Median: 1500.0, Bereich: 1500 - 1500',
        '  Keine Anomalien.',
    ]


def test_null_rows_keep_the_measurement_number(tmp_path):
    # collect-metrics.sh schreibt null, wenn ein Audit fehlt: Messung 5 bleibt Messung 5
    rows = [{'TTFB': v} for v in [120, 115, 118, None, 450, 122, 119, 121]]

    lines = run_input(tmp_path, rows).stdout.splitlines()

    # 7 Werte, Median 120
    assert '  Anomalie: Messung 5: 450 (3.8 × Median)' in lines


def test_all_six_collected_metrics_are_analysed(tmp_path):
    rows = [{name: 100 for name in ['TTFB', 'FCP', 'LCP', 'CLS', 'TBT', 'SI']} for _ in range(5)]

    lines = run_input(tmp_path, rows).stdout.splitlines()

    assert [line for line in lines if line in ['TTFB', 'FCP', 'LCP', 'CLS', 'TBT', 'SI']] == ['TTFB', 'FCP', 'LCP', 'CLS', 'TBT', 'SI']


def test_exactly_five_values_are_analysed_four_are_not():
    assert list(detect.analyze_metrics([{'TTFB': 100}] * 5)) == ['TTFB']
    assert detect.analyze_metrics([{'TTFB': 100}] * 4) == {}


def test_lowercase_keys_bools_nan_and_strings_do_not_count():
    rows = [{'TTFB': 100}] * 4 + [{'ttfb': 900}, {'TTFB': True}, {'TTFB': float('nan')}, {'TTFB': '900'}]

    assert detect.analyze_metrics(rows) == {}


def test_negative_median_is_not_rated():
    assert detect.analyze_metrics([{'CLS': -1}] * 5) == {'CLS': {'skipped': 'Median ≤ 0, kein Mindestabstand möglich'}}


def test_min_factor_option_reaches_the_analysis(tmp_path):
    result = run_input(tmp_path, [{'TTFB': v} for v in CHAPTER_EXAMPLE], '--min-factor', '5')
    lines = result.stdout.splitlines()

    assert result.returncode == 1
    assert '  Anomalie: Messung 7: 890 (7.4 × Median)' in lines
    assert not any('Messung 4' in line for line in lines)
    assert 'Gemeldet wird: über 5.0 × Median' in lines


def test_no_anomaly_is_exit_0(tmp_path):
    result = run_input(tmp_path, [{'TTFB': v} for v in WITHOUT_OUTLIERS])

    assert result.returncode == 0
    assert '  Keine Anomalien.' in result.stdout.splitlines()


def test_too_few_values_is_exit_0_with_message(tmp_path):
    result = run_input(tmp_path, [{'TTFB': 100}] * 4)

    assert result.returncode == 0
    assert 'Keine Metrik mit mindestens 5 Werten.' in result.stdout.splitlines()


@pytest.mark.parametrize('content, message', [
    ('{"TTFB": 100}', 'ist keine Liste von Messungen'),
    ('[1, 2, 3]', 'ist keine Liste von Messungen'),
    ('[{"TTFB": 1', 'nicht lesbar'),
])
def test_broken_input_is_exit_2(tmp_path, content, message):
    path = tmp_path / 'metrics.json'
    path.write_text(content)

    result = run('--input', str(path))

    assert result.returncode == 2
    assert message in result.stderr
    assert 'Traceback' not in result.stderr


def test_missing_input_file_is_exit_2(tmp_path):
    result = run('--input', str(tmp_path / 'fehlt.json'))

    assert result.returncode == 2
    assert 'nicht lesbar' in result.stderr


def test_demo_data_reports_ttfb_and_the_big_spike(tmp_path):
    result = run()
    lines = result.stdout.splitlines()

    assert result.returncode == 1
    assert '  Anomalie: Messung 4: 450 (3.7 × Median)' in lines
    assert lines[lines.index('LCP') + 2:lines.index('LCP') + 4] == [
        '  Werte: 10, Median: 1805.0, Bereich: 1750 - 4200',
        '  Anomalie: Messung 7: 4200 (2.3 × Median)',
    ]


@pytest.mark.parametrize('factor', ['1', '0.5', 'nan'])
def test_min_factor_must_be_above_one(factor):
    result = run('--example', '--min-factor', factor)

    assert result.returncode == 2
    assert '--min-factor muss grösser als 1 sein' in result.stderr
