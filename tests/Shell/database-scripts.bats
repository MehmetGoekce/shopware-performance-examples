#!/usr/bin/env bats

# BATS tests for the chapter 8 database scripts.
# mysql is replaced by a stub that answers from fixture files, so the tests
# need no running database.

DIR="./chapters/08-database/scripts"

setup() {
    TMP="$(mktemp -d)"
    FIX="$TMP/fix"
    mkdir -p "$FIX"

    # Stub: "mysql -N -B -e '<query>'" -> Datei $FIX/<normalisierte query>
    # Unbekannte Queries liefern eine leere Zeile, damit das Skript nicht
    # an einer fehlenden Fixture scheitert, sondern am Inhalt.
    cat > "$TMP/mysql" <<'STUB'
#!/bin/bash
query=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -e) query="$2"; shift 2 ;;
        *) shift ;;
    esac
done
name=$(echo "$query" | tr -cd 'A-Za-z0-9_@' | cut -c1-80)
if [[ -f "$FIX/$name" ]]; then
    cat "$FIX/$name"
else
    echo ""
fi
STUB
    chmod +x "$TMP/mysql"
    export FIX
    export MYSQL="$TMP/mysql"
    export PATH="$TMP:$PATH"

    # Gesunder MySQL-8.0-Server
    fixture "SELECT 1" "1"
    fixture "SELECT @@version" "8.0.46"
    fixture "SELECT @@performance_schema" "1"
    fixture "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'shopware'" "1"
    fixture "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime'" "864000"
    fixture "SELECT ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2)" "4.00"
    fixture "SELECT @@max_connections" "200"
    fixture "SELECT COUNT(*) FROM information_schema.processlist" "4"
    fixture "SELECT @@slow_query_log" "1"
    fixture "SELECT @@long_query_time" "1.000000"
    fixture "SELECT @@slow_query_log_file" "/var/log/mysql/slow.log"
    fixture "SELECT @@log_queries_not_using_indexes" "0"
    fixture "SELECT @@log_slow_extra" "0"
    fixture "SELECT @@innodb_log_file_size" "50331648"
    fixture "SELECT @@innodb_redo_log_capacity" "104857600"
}

teardown() {
    rm -rf "$TMP"
}

# Legt eine Fixture unter dem Namen an, den der Stub aus der Query ableitet.
fixture() {
    local name
    name=$(echo "$1" | tr -cd 'A-Za-z0-9_@' | cut -c1-80)
    printf '%s\n' "$2" > "$FIX/$name"
}

# Setzt die Hit-Rate in Promille (Fixture der zusammengesetzten Query).
set_hit_rate() {
    local f
    for f in "$FIX"/SELECTROUND1SELECTvariable_valueFROMperformance_schemaglobal_status*; do
        printf '%s\n' "$1" > "$f"
    done
    fixture "
SELECT ROUND((1 - (
    (SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') /
    NULLIF((SELECT variable_value FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
)) * 1000, 0)" "$1"
}

# ==============================================================================
# Help und Exit-Codes
# ==============================================================================

@test "both database scripts show help with --help" {
    for script in db-health-check.sh slow-query-analyze.sh; do
        run "$DIR/$script" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage:"* ]]
    done
}

@test "both database scripts reject unknown options with exit 1" {
    for script in db-health-check.sh slow-query-analyze.sh; do
        run "$DIR/$script" --nope
        [ "$status" -eq 1 ]
        [[ "$output" == *"Unbekannte Option"* ]]
    done
}

@test "both database scripts pass shellcheck at warning level" {
    command -v shellcheck > /dev/null || skip "shellcheck nicht installiert"
    run shellcheck -S warning "$DIR/db-health-check.sh" "$DIR/slow-query-analyze.sh"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# db-health-check.sh
# ==============================================================================

@test "health check refuses MariaDB with exit 2" {
    fixture "SELECT @@version" "10.11.19-MariaDB-ubu2204"
    run "$DIR/db-health-check.sh" shopware
    [ "$status" -eq 2 ]
    [[ "$output" == *"MariaDB erkannt"* ]]
}

@test "health check refuses a disabled performance_schema with exit 2" {
    fixture "SELECT @@performance_schema" "0"
    run "$DIR/db-health-check.sh" shopware
    [ "$status" -eq 2 ]
    [[ "$output" == *"performance_schema ist aus"* ]]
}

@test "health check refuses a missing database with exit 2" {
    printf '' > "$FIX/$(echo "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'shopware'" | tr -cd 'A-Za-z0-9_@' | cut -c1-80)"
    run "$DIR/db-health-check.sh" shopware
    [ "$status" -eq 2 ]
    [[ "$output" == *"existiert nicht"* ]]
}

@test "health check warns when the server was restarted less than an hour ago" {
    fixture "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime'" "120"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" == *"weniger als einer Stunde"* ]]
}

@test "health check rates the hit rate without bc" {
    set_hit_rate "1000"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" == *"sehr gut"* ]]

    set_hit_rate "940"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" == *"grenzwertig"* ]]

    set_hit_rate "800"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" == *"zu niedrig"* ]]
}

@test "health check warns about a deprecated innodb_log_file_size" {
    fixture "SELECT @@innodb_log_file_size" "2147483648"
    fixture "SELECT @@innodb_redo_log_capacity" "104857600"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" == *"innodb_log_file_size ist gesetzt"* ]]
}

@test "health check stays quiet about innodb_log_file_size when redo capacity is set" {
    fixture "SELECT @@innodb_log_file_size" "2147483648"
    fixture "SELECT @@innodb_redo_log_capacity" "1073741824"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" != *"innodb_log_file_size ist gesetzt"* ]]
}

@test "health check warns when log_queries_not_using_indexes is on" {
    fixture "SELECT @@log_queries_not_using_indexes" "1"
    run "$DIR/db-health-check.sh" shopware
    [[ "$output" == *"log_queries_not_using_indexes ist an"* ]]
}

# ==============================================================================
# slow-query-analyze.sh
# ==============================================================================

@test "slow query analysis fails on a missing log file" {
    run "$DIR/slow-query-analyze.sh" "$TMP/gibtsnicht.log"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht gefunden"* ]]
}

@test "slow query analysis exits cleanly on an empty log" {
    : > "$TMP/empty.log"
    run "$DIR/slow-query-analyze.sh" "$TMP/empty.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Keine Queries im Log"* ]]
}

@test "slow query analysis counts zero matches once, not twice" {
    # "grep -c muster datei || echo 0" gibt bei null Treffern ZWEI Nullen aus.
    cat > "$TMP/none.log" <<'LOG'
# Time: 2026-09-20T08:00:00.000000Z
# User@Host: root[root] @ localhost []  Id: 1
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 1
SET timestamp=1789891787;
SELECT id FROM product WHERE id = 1;
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/none.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIKE mit fuehrender Wildcard:"* ]]
    # genau eine Zeile mit genau einer 0 dahinter
    [ "$(printf '%s\n' "$output" | grep -c 'LIKE mit fuehrender Wildcard: *0$')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^0$')" -eq 0 ]
}

@test "slow query analysis picks the MySQL fields when log_slow_extra was on" {
    cat > "$TMP/extra.log" <<'LOG'
# Time: 2026-09-20T08:00:00.000000Z
# User@Host: root[root] @ localhost []  Id: 1
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 50  Rows_examined: 140 Read_rnd_next: 141 Sort_scan_count: 1 Created_tmp_disk_tables: 0
SET timestamp=1789891787;
SELECT * FROM product;
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/extra.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Read_rnd_next>0"* ]]
    [[ "$output" != *"Full_scan: Yes"* ]]
}

@test "slow query analysis picks the MariaDB fields when query_plan was on" {
    cat > "$TMP/maria.log" <<'LOG'
# Time: 2026-09-20  8:00:00
# User@Host: root[root] @ localhost []
# Thread_id: 18  Schema: shopware  QC_hit: No
# Query_time: 2.000000  Lock_time: 0.000000  Rows_sent: 1  Rows_examined: 1
# Full_scan: Yes  Full_join: No  Tmp_table: No  Tmp_table_on_disk: No
SET timestamp=1789891787;
SELECT * FROM t2 WHERE pad='a';
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/maria.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Full_scan: Yes"* ]]
    [[ "$output" != *"Read_rnd_next>0"* ]]
}

@test "slow query analysis says so when the log has no extra fields" {
    cat > "$TMP/plain.log" <<'LOG'
# Time: 2026-09-20T08:00:00.000000Z
# User@Host: root[root] @ localhost []  Id: 1
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 1
SET timestamp=1789891787;
SELECT * FROM product;
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/plain.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Keine Zusatzfelder im Log"* ]]
}

@test "slow query analysis counts only SELECTs that really have no WHERE" {
    # Das alte Muster "^SELECT [^;]*FROM [^;]*;$" zaehlte jede einzeilige
    # SELECT-Zeile mit, weil [^;]* die WHERE-Klausel mitfrisst.
    cat > "$TMP/where.log" <<'LOG'
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 5
SELECT id FROM product WHERE id = 1;
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 5
SELECT * FROM product;
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 5
SELECT a FROM t WHERE x=1 AND y=2;
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 5
SELECT b FROM u;
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/where.log"
    [ "$status" -eq 0 ]
    # vier SELECTs, davon genau zwei ohne WHERE
    [ "$(printf '%s\n' "$output" | grep -c 'Queries ohne WHERE: *2$')" -eq 1 ]
}

@test "slow query analysis sorts the rows-examined ranking descending" {
    cat > "$TMP/rank.log" <<'LOG'
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 5
SELECT id FROM product WHERE id = 1;
# Query_time: 3.000000  Lock_time: 0.000000 Rows_sent: 2  Rows_examined: 900000
SELECT id FROM product WHERE stock > 0;
# Query_time: 3.000000  Lock_time: 0.000000 Rows_sent: 3  Rows_examined: 77;
SELECT id FROM category;
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/rank.log"
    [ "$status" -eq 0 ]
    # die groesste Zahl muss vor der kleinsten stehen
    ranking=$(printf '%s\n' "$output" | grep 'gelesen,')
    first=$(printf '%s\n' "$ranking" | head -1)
    last=$(printf '%s\n' "$ranking" | tail -1)
    [[ "$first" == 900000* ]]
    [[ "$last" != 900000* ]]
}

@test "slow query analysis ranks by rows examined" {
    cat > "$TMP/rows.log" <<'LOG'
# Query_time: 2.000000  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 5
SELECT id FROM product WHERE id = 1;
# Query_time: 3.000000  Lock_time: 0.000000 Rows_sent: 2  Rows_examined: 900000
SELECT id FROM product WHERE stock > 0;
LOG
    run "$DIR/slow-query-analyze.sh" "$TMP/rows.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"900000 gelesen, 2 geliefert"* ]]
}
