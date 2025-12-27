#!/usr/bin/env node

/**
 * Performance Comparison - Vergleicht Performance zwischen Varianten
 *
 * @description
 * Visualisiert Performance-Unterschiede und generiert Reports.
 * Identifiziert Performance-Regressions automatisch.
 *
 * @usage
 * node performance-comparison.js <experiment-key> [--threshold=10]
 *
 * @example
 * node performance-comparison.js checkout_test --threshold=5
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */

const mysql = require('mysql2/promise');

// Konfiguration
const CONFIG = {
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER || 'shopware',
    password: process.env.DB_PASSWORD || 'shopware',
    database: process.env.DB_NAME || 'shopware',
  },
  defaultThreshold: 10, // Prozent
  coreWebVitals: {
    lcp: { good: 2500, poor: 4000 },
    fid: { good: 100, poor: 300 },
    cls: { good: 0.1, poor: 0.25 },
  },
};

/**
 * Main Function
 */
async function main() {
  const args = parseArgs();

  if (!args.experimentKey) {
    console.error('Usage: performance-comparison.js <experiment-key> [options]');
    console.error('Options:');
    console.error('  --threshold=10    Regression threshold in percent (default: 10)');
    console.error('  --detailed        Show detailed breakdown');
    console.error('  --device=TYPE     Filter by device type');
    process.exit(1);
  }

  const connection = await mysql.createConnection(CONFIG.database);

  try {
    console.log(`\n🔍 Performance Comparison: ${args.experimentKey}\n`);
    console.log('='.repeat(80) + '\n');

    // Daten laden
    const data = await loadAggregatedMetrics(connection, args);

    if (data.length === 0) {
      console.error('❌ No data found');
      process.exit(1);
    }

    // Gruppieren nach Variante
    const variants = groupByVariant(data);
    const variantNames = Object.keys(variants);

    if (variantNames.length < 2) {
      console.error('❌ Need at least 2 variants for comparison');
      process.exit(1);
    }

    // Control = erste Variante
    const controlName = variantNames[0];
    const control = variants[controlName];

    console.log(`Control: ${controlName}\n`);

    // Vergleiche jede Variante mit Control
    for (const variantName of variantNames.slice(1)) {
      const variant = variants[variantName];

      console.log(`\n📊 ${variantName} vs ${controlName}`);
      console.log('-'.repeat(80));

      compareVariants(control, variant, args.threshold, args.detailed);
    }

    // Core Web Vitals Assessment
    console.log('\n\n🎯 Core Web Vitals Assessment\n');
    console.log('='.repeat(80));

    assessCoreWebVitals(variants);

    // Performance Regressions
    console.log('\n\n⚠️  Performance Regressions\n');
    console.log('='.repeat(80));

    const regressions = findRegressions(variants, controlName, args.threshold);

    if (regressions.length === 0) {
      console.log('\n✅ No performance regressions detected');
    } else {
      for (const regression of regressions) {
        console.log(`\n❌ ${regression.variant} - ${regression.metric}`);
        console.log(`   Control: ${regression.controlValue}`);
        console.log(`   Variant: ${regression.variantValue}`);
        console.log(`   Regression: +${regression.regressionPercent.toFixed(2)}%`);
      }
    }

    console.log('\n' + '='.repeat(80) + '\n');
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  } finally {
    await connection.end();
  }
}

/**
 * Lädt aggregierte Metriken
 */
async function loadAggregatedMetrics(connection, args) {
  let sql = `
    SELECT
      variant,
      metric,
      device_type,
      COUNT(*) as sample_count,
      AVG(value) as mean,
      STDDEV(value) as stddev,
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY value) as p75,
      PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value) as p95
    FROM experiment_metrics
    WHERE experiment_id = ?
  `;

  const params = [args.experimentKey];

  if (args.device) {
    sql += ' AND device_type = ?';
    params.push(args.device);
  }

  sql += ' GROUP BY variant, metric, device_type';

  const [rows] = await connection.execute(sql, params);

  return rows;
}

/**
 * Gruppiert Daten nach Variante
 */
function groupByVariant(data) {
  const grouped = {};

  for (const row of data) {
    const { variant, metric, mean, p75, p95, sample_count } = row;

    if (!grouped[variant]) {
      grouped[variant] = {};
    }

    grouped[variant][metric] = {
      mean: parseFloat(mean),
      p75: parseFloat(p75),
      p95: parseFloat(p95),
      sampleCount: parseInt(sample_count),
    };
  }

  return grouped;
}

/**
 * Vergleicht zwei Varianten
 */
function compareVariants(control, variant, threshold, detailed) {
  const metrics = Object.keys(control);

  for (const metric of metrics) {
    const controlData = control[metric];
    const variantData = variant[metric];

    if (!variantData) continue;

    const improvement = ((controlData.mean - variantData.mean) / controlData.mean) * 100;
    const isRegression = improvement < -threshold;
    const isImprovement = improvement > threshold;

    // Icon & Color
    let icon = '⚪';
    if (isImprovement) icon = '✅';
    if (isRegression) icon = '❌';

    console.log(`\n${icon} ${metric.toUpperCase()}`);
    console.log(`   Control Mean: ${controlData.mean.toFixed(2)}`);
    console.log(`   Variant Mean: ${variantData.mean.toFixed(2)}`);
    console.log(`   Improvement: ${improvement > 0 ? '+' : ''}${improvement.toFixed(2)}%`);

    if (detailed) {
      console.log(`   Control P75: ${controlData.p75.toFixed(2)}`);
      console.log(`   Variant P75: ${variantData.p75.toFixed(2)}`);
      console.log(`   Control P95: ${controlData.p95.toFixed(2)}`);
      console.log(`   Variant P95: ${variantData.p95.toFixed(2)}`);
      console.log(`   Samples: Control=${controlData.sampleCount}, Variant=${variantData.sampleCount}`);
    }

    if (isRegression) {
      console.log(`   ⚠️  REGRESSION: Exceeds threshold (${threshold}%)`);
    }
  }
}

/**
 * Bewertet Core Web Vitals
 */
function assessCoreWebVitals(variants) {
  for (const [variantName, metrics] of Object.entries(variants)) {
    console.log(`\n${variantName}:`);

    // LCP
    if (metrics.lcp) {
      const status = getCWVStatus('lcp', metrics.lcp.p75);
      console.log(`  LCP (P75): ${metrics.lcp.p75.toFixed(2)}ms - ${status}`);
    }

    // FID
    if (metrics.fid) {
      const status = getCWVStatus('fid', metrics.fid.p75);
      console.log(`  FID (P75): ${metrics.fid.p75.toFixed(2)}ms - ${status}`);
    }

    // CLS
    if (metrics.cls) {
      const status = getCWVStatus('cls', metrics.cls.p75);
      console.log(`  CLS (P75): ${metrics.cls.p75.toFixed(3)} - ${status}`);
    }
  }
}

/**
 * Gibt Core Web Vital Status zurück
 */
function getCWVStatus(metric, value) {
  const thresholds = CONFIG.coreWebVitals[metric];

  if (!thresholds) return 'Unknown';

  if (value <= thresholds.good) {
    return '✅ Good';
  } else if (value <= thresholds.poor) {
    return '⚠️  Needs Improvement';
  } else {
    return '❌ Poor';
  }
}

/**
 * Findet Performance-Regressions
 */
function findRegressions(variants, controlName, threshold) {
  const regressions = [];
  const control = variants[controlName];

  for (const [variantName, metrics] of Object.entries(variants)) {
    if (variantName === controlName) continue;

    for (const [metric, data] of Object.entries(metrics)) {
      const controlData = control[metric];

      if (!controlData) continue;

      const regressionPercent = ((data.mean - controlData.mean) / controlData.mean) * 100;

      if (regressionPercent > threshold) {
        regressions.push({
          variant: variantName,
          metric,
          controlValue: controlData.mean.toFixed(2),
          variantValue: data.mean.toFixed(2),
          regressionPercent,
        });
      }
    }
  }

  return regressions;
}

/**
 * Parse Arguments
 */
function parseArgs() {
  const args = {
    experimentKey: process.argv[2],
    threshold: CONFIG.defaultThreshold,
    detailed: false,
    device: null,
  };

  for (let i = 3; i < process.argv.length; i++) {
    const arg = process.argv[i];

    if (arg.startsWith('--threshold=')) {
      args.threshold = parseFloat(arg.split('=')[1]);
    } else if (arg === '--detailed') {
      args.detailed = true;
    } else if (arg.startsWith('--device=')) {
      args.device = arg.split('=')[1];
    }
  }

  return args;
}

// Run
main().catch(console.error);
