#!/usr/bin/env node

/**
 * Experiment Analyzer - Statistische Auswertung von A/B Tests
 *
 * @description
 * Analysiert Experiment-Daten, berechnet Signifikanz und gibt Empfehlungen.
 * Unterstützt Welch's t-Test und Bayesian Analysis.
 *
 * @usage
 * node analyze-experiment.js <experiment-key> [--bayesian] [--confidence=0.95]
 *
 * @example
 * node analyze-experiment.js checkout_optimization --confidence=0.99
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */

const mysql = require('mysql2/promise');
const { mean, std, tTest } = require('simple-statistics');

// Konfiguration
const CONFIG = {
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER || 'shopware',
    password: process.env.DB_PASSWORD || 'shopware',
    database: process.env.DB_NAME || 'shopware',
  },
  defaultConfidence: 0.95,
  minSampleSize: 30,
};

/**
 * Main Function
 */
async function main() {
  const args = parseArgs();

  if (!args.experimentKey) {
    console.error('Usage: analyze-experiment.js <experiment-key> [options]');
    console.error('Options:');
    console.error('  --bayesian           Use Bayesian analysis');
    console.error('  --confidence=0.95    Confidence level (default: 0.95)');
    console.error('  --metric=lcp         Specific metric (default: all)');
    console.error('  --export=results.csv Export to CSV');
    process.exit(1);
  }

  const connection = await mysql.createConnection(CONFIG.database);

  try {
    console.log(`\n📊 Analyzing Experiment: ${args.experimentKey}\n`);
    console.log('='.repeat(80) + '\n');

    // 1. Experiment laden
    const experiment = await loadExperiment(connection, args.experimentKey);

    if (!experiment) {
      console.error(`❌ Experiment not found: ${args.experimentKey}`);
      process.exit(1);
    }

    printExperimentInfo(experiment);

    // 2. Metriken laden
    const metrics = await loadMetrics(connection, args.experimentKey, args.metric);

    if (metrics.length === 0) {
      console.error('❌ No metrics data found');
      process.exit(1);
    }

    // 3. Daten gruppieren nach Variante
    const variantData = groupByVariant(metrics);

    // 4. Sample Size prüfen
    validateSampleSizes(variantData);

    // 5. Analyse durchführen
    if (args.bayesian) {
      await performBayesianAnalysis(variantData, args.confidence);
    } else {
      await performFrequentistAnalysis(variantData, args.confidence);
    }

    // 6. Business Impact
    await analyzeBusiнessImpact(connection, args.experimentKey);

    // 7. Export (optional)
    if (args.export) {
      await exportResults(metrics, args.export);
      console.log(`\n✅ Results exported to ${args.export}`);
    }

    console.log('\n' + '='.repeat(80));
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  } finally {
    await connection.end();
  }
}

/**
 * Lädt Experiment aus Datenbank
 */
async function loadExperiment(connection, experimentKey) {
  const [rows] = await connection.execute(
    'SELECT * FROM experiment WHERE `key` = ?',
    [experimentKey]
  );

  return rows[0] || null;
}

/**
 * Lädt Metriken aus Datenbank
 */
async function loadMetrics(connection, experimentKey, metricFilter = null) {
  let sql = `
    SELECT variant, metric, value, device_type, created_at
    FROM experiment_metrics
    WHERE experiment_id = ?
  `;

  const params = [experimentKey];

  if (metricFilter) {
    sql += ' AND metric = ?';
    params.push(metricFilter);
  }

  const [rows] = await connection.execute(sql, params);

  return rows;
}

/**
 * Gruppiert Metriken nach Variante
 */
function groupByVariant(metrics) {
  const grouped = {};

  for (const metric of metrics) {
    const { variant, metric: metricName, value } = metric;

    if (!grouped[variant]) {
      grouped[variant] = {};
    }

    if (!grouped[variant][metricName]) {
      grouped[variant][metricName] = [];
    }

    grouped[variant][metricName].push(parseFloat(value));
  }

  return grouped;
}

/**
 * Validiert Sample Sizes
 */
function validateSampleSizes(variantData) {
  console.log('📈 Sample Sizes:\n');

  for (const [variant, metrics] of Object.entries(variantData)) {
    const sampleSizes = Object.entries(metrics).map(([metric, values]) => {
      return `  ${metric}: ${values.length}`;
    });

    console.log(`${variant}:`);
    console.log(sampleSizes.join('\n'));

    // Warnung bei kleiner Sample Size
    const minSize = Math.min(...Object.values(metrics).map(v => v.length));
    if (minSize < CONFIG.minSampleSize) {
      console.log(`  ⚠️  Warning: Sample size below minimum (${CONFIG.minSampleSize})`);
    }

    console.log('');
  }
}

/**
 * Frequentist Analysis (t-Test)
 */
async function performFrequentistAnalysis(variantData, confidence) {
  console.log(`\n🔬 Frequentist Analysis (Confidence: ${confidence * 100}%)\n`);

  const variants = Object.keys(variantData);
  const control = variants[0]; // Erste Variante = Control

  console.log(`Control: ${control}\n`);

  // Für jede Metrik
  const metrics = Object.keys(variantData[control]);

  for (const metric of metrics) {
    console.log(`\n📊 Metric: ${metric.toUpperCase()}`);
    console.log('-'.repeat(80));

    const controlData = variantData[control][metric];
    const controlMean = mean(controlData);
    const controlStd = std(controlData);

    console.log(`\n${control}:`);
    console.log(`  Mean: ${controlMean.toFixed(2)}`);
    console.log(`  Std Dev: ${controlStd.toFixed(2)}`);
    console.log(`  Samples: ${controlData.length}`);

    // Vergleiche mit anderen Varianten
    for (const variant of variants.slice(1)) {
      const variantData_ = variantData[variant][metric];

      if (!variantData_) continue;

      const variantMean = mean(variantData_);
      const variantStd = std(variantData_);

      console.log(`\n${variant}:`);
      console.log(`  Mean: ${variantMean.toFixed(2)}`);
      console.log(`  Std Dev: ${variantStd.toFixed(2)}`);
      console.log(`  Samples: ${variantData_.length}`);

      // Statistische Analyse
      const improvement = ((controlMean - variantMean) / controlMean) * 100;
      const result = calculateSignificance(controlData, variantData_, confidence);

      console.log(`\n  Improvement: ${improvement > 0 ? '+' : ''}${improvement.toFixed(2)}%`);
      console.log(`  p-value: ${result.pValue.toFixed(4)}`);
      console.log(`  Effect Size (Cohen's d): ${result.effectSize.toFixed(3)}`);

      if (result.isSignificant) {
        console.log(`  ✅ SIGNIFICANT (${confidence * 100}% confidence)`);

        if (improvement > 0) {
          console.log(`  🏆 Winner: ${variant}`);
        } else {
          console.log(`  ❌ Worse than control`);
        }
      } else {
        console.log(`  ⚪ Not significant - continue testing`);
      }
    }
  }
}

/**
 * Bayesian Analysis
 */
async function performBayesianAnalysis(variantData, threshold = 0.95) {
  console.log(`\n🎲 Bayesian Analysis (Threshold: ${threshold * 100}%)\n`);

  const variants = Object.keys(variantData);
  const control = variants[0];

  console.log(`Control: ${control}\n`);

  const metrics = Object.keys(variantData[control]);

  for (const metric of metrics) {
    console.log(`\n📊 Metric: ${metric.toUpperCase()}`);
    console.log('-'.repeat(80));

    const controlData = variantData[control][metric];

    for (const variant of variants.slice(1)) {
      const variantData_ = variantData[variant][metric];

      if (!variantData_) continue;

      const result = bayesianComparison(controlData, variantData_);

      console.log(`\n${variant}:`);
      console.log(`  Probability to be best: ${(result.probabilityToBeBest * 100).toFixed(2)}%`);
      console.log(`  Expected Loss: ${result.expectedLoss.toFixed(2)}`);
      console.log(`  Credible Interval (95%): [${result.credibleInterval.lower.toFixed(2)}, ${result.credibleInterval.upper.toFixed(2)}]`);

      if (result.probabilityToBeBest >= threshold) {
        console.log(`  ✅ DEPLOY - High confidence winner`);
      } else if (result.probabilityToBeBest >= 0.80) {
        console.log(`  ⚠️  PROMISING - Continue testing`);
      } else {
        console.log(`  ❌ NOT RECOMMENDED - Insufficient evidence`);
      }
    }
  }
}

/**
 * Berechnet statistische Signifikanz (Welch's t-Test approximiert)
 */
function calculateSignificance(control, variant, confidence) {
  const controlMean = mean(control);
  const variantMean = mean(variant);
  const controlStd = std(control);
  const variantStd = std(variant);

  // Welch's t-statistic
  const pooledSE = Math.sqrt(
    (controlStd ** 2 / control.length) + (variantStd ** 2 / variant.length)
  );

  const tStat = Math.abs((controlMean - variantMean) / pooledSE);

  // Approximierter p-value (für große Samples)
  const pValue = 2 * (1 - normalCDF(tStat));

  // Effect Size (Cohen's d)
  const pooledStd = Math.sqrt(
    ((control.length - 1) * controlStd ** 2 + (variant.length - 1) * variantStd ** 2) /
    (control.length + variant.length - 2)
  );

  const effectSize = (controlMean - variantMean) / pooledStd;

  const alpha = 1 - confidence;
  const isSignificant = pValue < alpha;

  return { pValue, effectSize, isSignificant };
}

/**
 * Bayesian Comparison (Monte Carlo)
 */
function bayesianComparison(control, variant, simulations = 10000) {
  const controlMean = mean(control);
  const variantMean = mean(variant);
  const controlStd = std(control);
  const variantStd = std(variant);

  let variantWins = 0;

  for (let i = 0; i < simulations; i++) {
    const controlSample = sampleNormal(controlMean, controlStd);
    const variantSample = sampleNormal(variantMean, variantStd);

    if (variantSample < controlSample) {
      variantWins++;
    }
  }

  const probabilityToBeBest = variantWins / simulations;
  const expectedLoss = Math.max(0, variantMean - controlMean);

  // 95% Credible Interval (approximiert)
  const margin = 1.96 * (variantStd / Math.sqrt(variant.length));

  return {
    probabilityToBeBest,
    expectedLoss,
    credibleInterval: {
      lower: variantMean - margin,
      upper: variantMean + margin,
    },
  };
}

/**
 * Analysiert Business Impact
 */
async function analyzeBusiнessImpact(connection, experimentKey) {
  console.log('\n\n💰 Business Impact Analysis\n');
  console.log('='.repeat(80));

  const [conversions] = await connection.execute(
    `
    SELECT
      a.variant,
      COUNT(DISTINCT a.customer_id) as users,
      COUNT(DISTINCT c.id) as conversions,
      (COUNT(DISTINCT c.id)::float / COUNT(DISTINCT a.customer_id)) * 100 as conversion_rate,
      AVG(c.conversion_value) as avg_value
    FROM experiment_assignments a
    LEFT JOIN experiment_conversions c ON c.customer_id = a.customer_id
      AND c.experiment_key = a.experiment_key
      AND c.created_at >= a.created_at
    WHERE a.experiment_key = ?
    GROUP BY a.variant
    `,
    [experimentKey]
  );

  if (conversions.length === 0) {
    console.log('No conversion data available');
    return;
  }

  for (const row of conversions) {
    console.log(`\n${row.variant}:`);
    console.log(`  Users: ${row.users}`);
    console.log(`  Conversions: ${row.conversions}`);
    console.log(`  Conversion Rate: ${parseFloat(row.conversion_rate).toFixed(2)}%`);
    console.log(`  Avg Value: €${parseFloat(row.avg_value || 0).toFixed(2)}`);
  }
}

/**
 * Exportiert Ergebnisse als CSV
 */
async function exportResults(metrics, filename) {
  const fs = require('fs').promises;

  const csv = ['variant,metric,value,device_type,created_at'];

  for (const metric of metrics) {
    csv.push(
      `${metric.variant},${metric.metric},${metric.value},${metric.device_type || ''},${metric.created_at}`
    );
  }

  await fs.writeFile(filename, csv.join('\n'));
}

/**
 * Gibt Experiment-Info aus
 */
function printExperimentInfo(experiment) {
  console.log('Experiment Information:');
  console.log(`  Name: ${experiment.name}`);
  console.log(`  Status: ${experiment.status}`);
  console.log(`  Started: ${experiment.start_date || 'Not started'}`);

  if (experiment.end_date) {
    console.log(`  Ended: ${experiment.end_date}`);
  }

  console.log(`  Target Sample Size: ${experiment.target_sample_size}`);
  console.log('');
}

/**
 * Hilfsfunktionen
 */

function normalCDF(x) {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989423 * Math.exp(-x * x / 2);
  const prob = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));

  return x > 0 ? 1 - prob : prob;
}

function sampleNormal(mean, std) {
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);

  return mean + z * std;
}

function parseArgs() {
  const args = {
    experimentKey: process.argv[2],
    bayesian: false,
    confidence: CONFIG.defaultConfidence,
    metric: null,
    export: null,
  };

  for (let i = 3; i < process.argv.length; i++) {
    const arg = process.argv[i];

    if (arg === '--bayesian') {
      args.bayesian = true;
    } else if (arg.startsWith('--confidence=')) {
      args.confidence = parseFloat(arg.split('=')[1]);
    } else if (arg.startsWith('--metric=')) {
      args.metric = arg.split('=')[1];
    } else if (arg.startsWith('--export=')) {
      args.export = arg.split('=')[1];
    }
  }

  return args;
}

// Run
main().catch(console.error);
