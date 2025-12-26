# Kapitel 8: Datenbank-Optimierung für Shopware

MySQL/MariaDB Konfiguration und Query-Optimierung für Shopware 6.

## Dateien

```
08-database/
├── config/
│   ├── shopware.cnf           # MySQL-Konfiguration für Shopware
│   └── doctrine.yaml          # Read Replica Konfiguration
├── scripts/
│   ├── db-health-check.sh     # Datenbank-Gesundheitscheck
│   ├── slow-query-analyze.sh  # Slow Query Analyse
│   ├── buffer-pool-check.sql  # Buffer Pool Hit-Rate prüfen
│   └── index-analysis.sql     # Index-Nutzung analysieren
└── src/Service/
    ├── BatchProcessor.php     # Batch-Verarbeitung für grosse Datenmengen
    └── CachedProductService.php # Query-Caching Beispiel
```

## Schnellstart

### 1. MySQL-Konfiguration anpassen

```bash
# Konfiguration kopieren
sudo cp config/shopware.cnf /etc/mysql/mysql.conf.d/

# MySQL neu starten
sudo systemctl restart mysql
```

### 2. Buffer Pool prüfen

```bash
# Buffer Pool Hit-Rate anzeigen
mysql < scripts/buffer-pool-check.sql

# Ziel: >99% Hit-Rate
```

### 3. Slow Queries analysieren

```bash
# Slow Query Log aktivieren und analysieren
./scripts/slow-query-analyze.sh
```

## Zielwerte

| Metrik | Zielwert |
|--------|----------|
| Buffer Pool Hit-Rate | >99% |
| Slow Queries/Tag | <5 |
| Durchschnittliche Query-Zeit | <10ms |
| Tabellen-Fragmentierung | <10% |

## Wichtige SQL-Befehle

### Buffer Pool Status

```sql
-- Hit-Rate berechnen
SELECT
    ROUND((1 - (
        (SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_reads') /
        (SELECT variable_value FROM performance_schema.global_status
         WHERE variable_name = 'Innodb_buffer_pool_read_requests')
    )) * 100, 2) AS 'Buffer Pool Hit Rate (%)';
```

### Slow Query Log aktivieren

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;
SET GLOBAL log_queries_not_using_indexes = 'ON';
```

### Indizes prüfen

```sql
EXPLAIN ANALYZE SELECT ...;
```

## Weiterführende Ressourcen

- [Shopware DAL Documentation](https://developer.shopware.com/docs/concepts/framework/data-abstraction-layer.html)
- [MySQL InnoDB Buffer Pool](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html)
- [Percona Toolkit](https://www.percona.com/software/database-tools/percona-toolkit)
