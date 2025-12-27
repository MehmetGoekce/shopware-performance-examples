#!/usr/bin/env node

/**
 * Export Metrics - Exportiert Experiment-Metriken für externe Analyse
 *
 * @description
 * Exportiert Daten in verschiedenen Formaten (CSV, JSON, Excel-kompatibel).
 * Unterstützt Filterung und Aggregation.
 *
 * @usage
 * node export-metrics.js <experiment-key> --format=csv --output=results.csv
 *
 * @example
 * node export-metrics.js checkout_test --format=json --aggregate
 *
 * @author Mehmet Gökçe
 * @since 1.0.0
 */

const mysql = require('mysql2/promise');
const fs = require('fs').promises;

// Konfiguration
const CONFIG = {
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER || 'shopware',
    password: process.env.DB_PASSWORD || 'shopware',
    database: process.env.DB_NAME || 'shopware',
  },
};

/**
 * Main Function
 */
async function main() {
  const args = parseArgs();

  if (!args.experimentKey) {
    console.error('Usage: export-metrics.js <experiment-key> [options]');
    console.error('Options:');
    console.error('  --format=csv|json      Output format (default: csv)');
    console.error('  --output=FILE          Output file (default: stdout)');
    console.error('  --aggregate            Export aggregated data');
    console.error('  --variant=NAME         Filter by variant');
    console.error('  --metric=NAME          Filter by metric');
    console.error('  --device=TYPE          Filter by device type');
    console.error('  --since=YYYY-MM-DD     Filter by date');
    process.exit(1);
  }

  const connection = await mysql.createConnection(CONFIG.database);

  try {
    console.error(`Exporting metrics for: ${args.experimentKey}`);

    let data;

    if (args.aggregate) {
      data = await exportAggregated(connection, args);
    } else {
      data = await exportRaw(connection, args);
    }

    // Format & Output
    let output;

    if (args.format === 'json') {
      output = JSON.stringify(data, null, 2);
    } else {
      output = formatCSV(data, args.aggregate);
    }

    if (args.output) {
      await fs.writeFile(args.output, output);
      console.error(`✅ Exported ${data.length} rows to ${args.output}`);
    } else {
      console.log(output);
    }
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  } finally {
    await connection.end();
  }
}

/**
 * Exportiert Raw-Daten
 */
async function exportRaw(connection, args) {
  let sql = `
    SELECT
      variant,
      metric,
      value,
      device_type,
      created_at
    FROM experiment_metrics
    WHERE experiment_id = ?
  `;

  const params = [args.experimentKey];

  if (args.variant) {
    sql += ' AND variant = ?';
    params.push(args.variant);
  }

  if (args.metric) {
    sql += ' AND metric = ?';
    params.push(args.metric);
  }

  if (args.device) {
    sql += ' AND device_type = ?';
    params.push(args.device);
  }

  if (args.since) {
    sql += ' AND created_at >= ?';
    params.push(args.since);
  }

  sql += ' ORDER BY created_at DESC';

  const [rows] = await connection.execute(sql, params);

  return rows;
}

/**
 * Exportiert aggregierte Daten
 */
async function exportAggregated(connection, args) {
  let sql = `
    SELECT
      variant,
      metric,
      device_type,
      COUNT(*) as sample_count,
      AVG(value) as mean,
      STDDEV(value) as stddev,
      MIN(value) as min,
      MAX(value) as max,
      PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY value) as p50,
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY value) as p75,
      PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value) as p95,
      PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY value) as p99
    FROM experiment_metrics
    WHERE experiment_id = ?
  `;

  const params = [args.experimentKey];

  if (args.variant) {
    sql += ' AND variant = ?';
    params.push(args.variant);
  }

  if (args.metric) {
    sql += ' AND metric = ?';
    params.push(args.metric);
  }

  if (args.device) {
    sql += ' AND device_type = ?';
    params.push(args.device);
  }

  if (args.since) {
    sql += ' AND created_at >= ?';
    params.push(args.since);
  }

  sql += ' GROUP BY variant, metric, device_type';
  sql += ' ORDER BY variant, metric';

  const [rows] = await connection.execute(sql, params);

  // Formatiere Zahlen
  return rows.map(row => ({
    ...row,
    mean: parseFloat(row.mean).toFixed(2),
    stddev: parseFloat(row.stddev).toFixed(2),
    min: parseFloat(row.min).toFixed(2),
    max: parseFloat(row.max).toFixed(2),
    p50: parseFloat(row.p50).toFixed(2),
    p75: parseFloat(row.p75).toFixed(2),
    p95: parseFloat(row.p95).toFixed(2),
    p99: parseFloat(row.p99).toFixed(2),
  }));
}

/**
 * Formatiert Daten als CSV
 */
function formatCSV(data, isAggregated) {
  if (data.length === 0) {
    return '';
  }

  // Header
  const headers = Object.keys(data[0]);
  const lines = [headers.join(',')];

  // Rows
  for (const row of data) {
    const values = headers.map(header => {
      const value = row[header];

      // Escape Kommas und Quotes
      if (typeof value === 'string' && (value.includes(',') || value.includes('"'))) {
        return `"${value.replace(/"/g, '""')}"`;
      }

      return value ?? '';
    });

    lines.push(values.join(','));
  }

  return lines.join('\n');
}

/**
 * Parse Command-Line Arguments
 */
function parseArgs() {
  const args = {
    experimentKey: process.argv[2],
    format: 'csv',
    output: null,
    aggregate: false,
    variant: null,
    metric: null,
    device: null,
    since: null,
  };

  for (let i = 3; i < process.argv.length; i++) {
    const arg = process.argv[i];

    if (arg.startsWith('--format=')) {
      args.format = arg.split('=')[1];
    } else if (arg.startsWith('--output=')) {
      args.output = arg.split('=')[1];
    } else if (arg === '--aggregate') {
      args.aggregate = true;
    } else if (arg.startsWith('--variant=')) {
      args.variant = arg.split('=')[1];
    } else if (arg.startsWith('--metric=')) {
      args.metric = arg.split('=')[1];
    } else if (arg.startsWith('--device=')) {
      args.device = arg.split('=')[1];
    } else if (arg.startsWith('--since=')) {
      args.since = arg.split('=')[1];
    }
  }

  return args;
}

// Run
main().catch(console.error);
