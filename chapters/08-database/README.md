# Kapitel 8: Datenbank-Optimierung für Shopware

MySQL/MariaDB-Konfiguration und Query-Optimierung für Shopware 6.

Alles hier ist gegen Shopware 6.6.10.6, MySQL 8.0.46 und MariaDB 10.11.19 in
Docker getestet. Wo sich die beiden Datenbanken unterscheiden, steht es dabei —
es gibt an mehreren Stellen keine Abfrage, die auf beiden läuft.

## Dateien

```
08-database/
├── config/
│   └── shopware.cnf           # MySQL-Konfiguration für Shopware
├── scripts/
│   ├── db-health-check.sh     # Datenbank-Gesundheitscheck (MySQL 8.0)
│   ├── slow-query-analyze.sh  # Slow-Query-Analyse (MySQL + MariaDB)
│   ├── buffer-pool-check.sql  # Buffer Pool und Hit-Rate (MySQL 8.0)
│   ├── index-analysis.sql     # Index-Nutzung und -Größen
│   └── chapter-queries.sql    # Die SQL-Kurzformen aus dem Kapitel, wie gedruckt
└── src/Service/
    ├── BatchProcessor.php     # Batch-Verarbeitung für grosse Datenmengen
    ├── CachedProductService.php # Eigenes Caching für teure Abfragen
    └── DalExamples.php        # DAL-Paare SCHLECHT/BESSER aus Abschnitt 8.5
```

`chapter-queries.sql` ist die Quelle der sechs SQL-Kurzformen aus 8.2, 8.4 und
8.8, `DalExamples.php` die der vier DAL-Paare aus 8.5; das Snippet-Gate des
Buchs hält beides gegeneinander. Gegenbeispiele und Einzelbefehle stehen nur im
Buch, die ausführlichen Werkzeuge sind die anderen Dateien.
`chapter-queries.sql` liest den Datenbanknamen aus `DATABASE()` und braucht
einen administrativen Zugang (`mysql.innodb_index_stats`, `sys`):
`mysql -u root -p shopware < scripts/chapter-queries.sql`. Ubuntus Paket
`mysql-server` und MariaDB aus Debian oder Ubuntu richten root ab Werk über
den Unix-Socket ein; dort endet dieser Aufruf für jeden Systembenutzer ausser
root mit `ERROR 1698`, und es heisst
`sudo mysql shopware < scripts/chapter-queries.sql`. Die
`OPTIMIZE TABLE`-Zeilen darin sind auskommentiert.

## Schnellstart

### 1. MySQL-Konfiguration anpassen

```bash
sudo cp config/shopware.cnf /etc/mysql/mysql.conf.d/
sudo chown root:root /etc/mysql/mysql.conf.d/shopware.cnf
sudo chmod 644 /etc/mysql/mysql.conf.d/shopware.cnf
sudo systemctl restart mysql
```

Die beiden Rechte-Zeilen sind kein Zierrat. Kann der `mysqld`-Prozess die Datei
nicht lesen, bricht MySQL die ganze `!includedir`-Direktive ab — mit der Meldung
`Stopped processing the 'includedir' directive` und ohne dass der Server
scheitert. Er startet dann sauber mit lauter Vorgabewerten, und keine einzige
Einstellung aus der Datei ist aktiv. Danach immer gegenprüfen:

```bash
mysql -e "SELECT @@innodb_buffer_pool_size, @@group_concat_max_len;"
```

Die Werte in der Datei gelten für einen Server mit 16 GB RAM, auf dem neben
MySQL auch PHP-FPM, Redis und nginx laufen (Referenzprofil aus Anhang C).

### 2. Buffer Pool prüfen

```bash
# Datenbankname ist Pflicht - ohne ihn ist DATABASE() NULL und die
# Grössenvergleiche melden stillschweigend Unsinn
mysql shopware < scripts/buffer-pool-check.sql
```

### 3. Gesundheitscheck

```bash
./scripts/db-health-check.sh shopware

# Gegen einen Container:
MYSQL="docker exec -i db mysql -uroot -proot" ./scripts/db-health-check.sh shopware
```

### 4. Slow Queries analysieren

```bash
sudo ./scripts/slow-query-analyze.sh /var/log/mysql/slow.log
```

### 5. Indizes analysieren

```bash
mysql shopware < scripts/index-analysis.sql
```

## Zielwerte

Die Zahlen unten sind Erfahrungswerte, keine dokumentierten Normen. Die MySQL-
Dokumentation nennt für die Buffer-Pool-Hit-Rate überhaupt keinen Zielwert;
Tideways nennt „schlechter als 90 %" als Problemmarke und 99,9 % als sehr guten
Wert. Wichtiger als der absolute Wert ist die Richtung über die Zeit.

| Metrik | Richtwert | Anmerkung |
|--------|-----------|-----------|
| Buffer Pool Hit-Rate | > 99 % | Zähler gelten seit Serverstart — Uptime prüfen |
| Slow Queries/Tag | < 5 | nur aussagekräftig ohne `log_queries_not_using_indexes` |
| Tabellen-Fragmentierung | < 10 % | `data_free` gehört in den Nenner, sonst > 100 % möglich |

## Read Replicas

Shopware bündelt **kein** DoctrineBundle — ein `doctrine:`-Block in
`config/packages/` erzeugt einen Container-Build-Fehler. Read Replicas werden
über die `.env` konfiguriert, und die Variablen sind durchnummeriert:

```bash
DATABASE_URL=mysql://user:pass@primary:3306/shopware
DATABASE_REPLICA_0_URL=mysql://user:pass@replica-1:3306/shopware
DATABASE_REPLICA_1_URL=mysql://user:pass@replica-2:3306/shopware
```

Shopware liest sie in `Framework/Adapter/Database/MySQLFactory.php` und legt
eine `PrimaryReadReplicaConnection` an. Lesezugriffe gehen auf die Replicas,
sobald eine Verbindung aufgebaut wird; nach dem ersten Schreibvorgang bleibt die
Verbindung bis zum Transaktionsende auf dem Primary.

Für eigene Queries, die nach einem Schreibvorgang zwingend den Primary brauchen,
gibt es `ReplicaConnection::ensurePrimary()`. Die Klasse ist allerdings als
`@internal` markiert — wer sie aufruft, verlässt Shopwares
Kompatibilitätsversprechen und muss bei Minor-Updates damit rechnen, dass sie
sich ändert.

**Replikationslatenz:** Schreibt ein Kunde eine Bestellung, sieht er sie bei
sofortigem Lesen von der Replica unter Umständen noch nicht. Shopware selbst
behandelt das korrekt; eigene Queries müssen es berücksichtigen.

## Was hier bewusst fehlt

- **Kein `mysqldumpslow -t 10`.** Das Werkzeug stirbt mit Exit 255
  (`Died at /usr/bin/mysqldumpslow line 163`), sobald der Wert hinter `-t`
  grösser ist als die Zahl der verschiedenen Query-Muster im Log. Es gibt
  vorher alles aus, was es gefunden hat — interaktiv fällt das kaum auf, in
  einem Cron-Job bricht der Rest weg. `slow-query-analyze.sh` begrenzt deshalb
  mit `awk` statt mit `-t`.
- **Kein `grep -c "filesort"` und kein `grep -c "Full scan"`** im Slow-Log.
  „filesort" ist eine EXPLAIN-Ausgabe. `Full_scan: Yes` ist ein MariaDB-Feld aus
  `log_slow_verbosity=query_plan`; MySQL 8.0 schreibt es auch mit
  `log_slow_extra = ON` nicht, dort heissen die Felder `Read_rnd_next`,
  `Sort_scan_count` und `Created_tmp_tables`.
- **Kein `log_queries_not_using_indexes = 1` als Dauerempfehlung.** Die Option
  ignoriert `long_query_time` und protokolliert jede Query ohne Index-Zugriff.
  Gemessen: mit `long_query_time = 10` landeten 40 von 40 trivialen Queries im
  Log. Für eine gezielte Index-Jagd stundenweise einschalten, sonst aus.
- **Kein `innodb_log_file_size`.** Seit MySQL 8.0.30 abgekündigt, in 8.4
  entfernt — und es wirkt weiter, nur anders als gemeint: MySQL rechnet daraus
  `innodb_redo_log_capacity = Wert × innodb_log_files_in_group` (ab Werk 2).
  Aus `2G` werden 4 GB auf der Platte, während `SHOW VARIABLES` weiter die
  Vorgabe 100 MB meldet. `db-health-check.sh` schlägt darauf an.

## MySQL und MariaDB

| Thema | MySQL 8.0 | MariaDB 10.11 |
|---|---|---|
| Statuswerte | `performance_schema.global_status` | beides: `performance_schema.global_status` (bei `performance_schema = ON`) und `information_schema.global_status` |
| `performance_schema` | ab Werk an | ab Werk **aus**, Neustart nötig |
| `sys`-Schema | vorhanden | ebenfalls vorhanden, inkl. `schema_unused_indexes`, `schema_redundant_indexes`, `schema_index_statistics` |
| `innodb_buffer_pool_instances` | vorhanden | mit 10.6 **entfernt** |
| Ausführungsplan mit Messung | `EXPLAIN ANALYZE` | `ANALYZE SELECT` |
| CTE-Rekursionstiefe | `cte_max_recursion_depth` | `max_recursive_iterations` |
| Slow-Log-Zusatzfelder | `log_slow_extra = ON` | `log_slow_verbosity = 'query_plan'` |
| Index weich abschalten | `ALTER INDEX … INVISIBLE` | `ALTER INDEX … IGNORED` |

## Tests

```bash
docker run --rm -v "$PWD:/code" -w /code bats/bats:latest tests/Shell/database-scripts.bats
shellcheck -S warning chapters/08-database/scripts/*.sh
```

## Weiterführende Ressourcen

- [Shopware DAL Documentation](https://developer.shopware.com/docs/concepts/framework/data-abstraction-layer.html)
- [Shopware Performance Tweaks](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html)
- [MySQL InnoDB Buffer Pool](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html)
- [Percona Toolkit — pt-query-digest](https://docs.percona.com/percona-toolkit/pt-query-digest.html)
- [MariaDB: Ignored Indexes](https://mariadb.com/kb/en/ignored-indexes/)
