# Kapitel 10: Redis fuer Hochverfuegbarkeit

Companion-Code zum Buch **"Shop-Performance in 30 Tagen"**

## Inhalt

Dieses Verzeichnis enthaelt die Redis-Konfigurationen und Scripts aus Kapitel 10.

Das Setup benutzt **zwei getrennte Redis-Instanzen**, nicht eine mit zwei
Datenbanken: `maxmemory-policy` und Persistenz gelten pro Instanz. Der Cache
braucht `volatile-lru` ohne Persistenz (sonst speichert
`cache.adapter.redis_tag_aware` gar nichts), Sessions brauchen `allkeys-lru`
mit Persistenz. Jede Instanz hat einen eigenen Sentinel-Master-Namen.

### config/
- `redis-cache.conf` - Cache-Instanz, Port 6379, `volatile-lru`, ohne Persistenz
- `redis-session.conf` - Session-Instanz, Port 6380, `allkeys-lru`, RDB + AOF
- `sentinel.conf` - Sentinel, ueberwacht beide Master (fuer alle 3 Nodes gleich)
- `redis-auth.example.conf` - Skeleton fuer Secrets-Datei (requirepass + masterauth)
- `sentinel-auth.example.conf` - Skeleton fuer Sentinel-Secrets (sentinel auth-pass)
- `users.acl.example` - Skeleton fuer Redis 7.x ACL-Persistenz (shopware-User + sentinel-watcher)
- `redis-tls.example.conf` - Skeleton fuer TLS-Direktiven (tls-port, cert-files, mutual TLS, TLS 1.2+1.3)
- `shopware-redis.yaml` - Shopware/Symfony Sentinel-Integration

### scripts/
- `redis-impact-test.sh` - Misst die Antwortzeiten mit und ohne Redis
- `test-failover.sh` - Loest je Master ein Failover aus und misst die Zeit
- `redis-monitor.sh` - Health-Check ueber beide Instanzen (Exit-Codes fuer Cron)
- `generate-tls-certs.example.sh` - Test-CA + Server-/Client-Cert (NICHT fuer Production)

### Root
- `.env.example` - Shopware/Symfony Env-Vars (Passwort, Sentinel-Hosts, Master-Namen)

## Architektur

Drei Nodes, auf jedem laufen drei Dienste: die Cache-Instanz, die
Session-Instanz und ein Sentinel. Master und Replicas muessen nicht auf
demselben Node liegen — Sentinel verteilt die Rollen beim Failover neu.

```
                    +---------------------------+
                    |   Sentinel Quorum (3x)     |
                    |   Port 26379, quorum 2     |
                    +-------------+-------------+
                                  | ueberwacht BEIDE Master
          +-----------------------+-----------------------+
          v                                               v
+---------------------------+              +---------------------------+
| shopware-cache  Port 6379 |              | shopware-session Port 6380|
| volatile-lru, keine       |              | allkeys-lru, RDB + AOF    |
| Persistenz                |              |                           |
+---------------------------+              +---------------------------+
| Node 1 Master             |              | Node 1 Master             |
| Node 2 Replica            |              | Node 2 Replica            |
| Node 3 Replica            |              | Node 3 Replica            |
+---------------------------+              +---------------------------+
```

## Schnellstart

### 1. Redis auf allen 3 Nodes installieren

```bash
sudo apt update
sudo apt install redis-server redis-sentinel
```

Ubuntu 22.04 installiert damit Redis 6.0. Alle Konfigurationen hier starten
auf 6.0 und 7.4; keine benutzte Direktive ist neuer als 6.0.

### 2. Datenverzeichnisse anlegen

Beide Instanzen schreiben unterhalb von `/var/lib/redis`. Das ist keine
Geschmacksfrage: die Unit `redis-server@.service` des Distributions-Pakets
haengt das Dateisystem read-only ein (`ReadOnlyDirectories=/`) und gibt nur
`/var/lib/redis`, `/var/log/redis` und `/var/run/redis-<instanz>` wieder frei.
Liegt `dir` ausserhalb, startet die Session-Instanz gar nicht
(`Can't open or create append-only dir appendonlydir: Read-only file system`),
und die Cache-Replicas kommen nie durch den Full-Resync
(`Opening the temp file needed for MASTER <-> REPLICA synchronization:
Read-only file system`) — die Replikation bleibt dauerhaft `down`.

```bash
sudo mkdir -p /var/lib/redis/cache /var/lib/redis/session
sudo chown redis:redis /var/lib/redis/cache /var/lib/redis/session
```

### 3. Konfigurationen verteilen

`redis-server@<name>` liest `/etc/redis/redis-<name>.conf`, deshalb muessen die
Dateinamen so bleiben.

```bash
# Alle 3 Nodes, beide Instanzen
sudo cp config/redis-cache.conf   /etc/redis/redis-cache.conf
sudo cp config/redis-session.conf /etc/redis/redis-session.conf

# Auf Node 2 und 3: den replicaof-Block am Dateiende aktivieren
# und die Master-IP eintragen.

# Alle 3 Nodes (Sentinel)
sudo cp config/sentinel.conf /etc/redis/sentinel.conf
# WICHTIG: Master-IPs in den beiden "sentinel monitor"-Zeilen anpassen.
```

### 4. Secrets Management — Passwort generieren und externalisieren

Niemals Passwoerter direkt in `redis-cache.conf` / `redis-session.conf` /
`sentinel.conf` eintragen oder committen. Stattdessen separate Secrets-Dateien
(`/etc/redis/redis-auth.conf` + `/etc/redis/sentinel-auth.conf`) anlegen und
per `include` einbinden — siehe Buch Kap. 10, Subsection "Secrets Management".

```bash
# 1. Sicheres Passwort generieren
REDIS_PWD=$(openssl rand -base64 32)

# 2. Secrets-Dateien anlegen (auf jedem Node, gleiches Passwort!)
sudo tee /etc/redis/redis-auth.conf > /dev/null <<EOF
requirepass "${REDIS_PWD}"
masterauth "${REDIS_PWD}"
EOF
sudo tee /etc/redis/sentinel-auth.conf > /dev/null <<EOF
sentinel auth-pass shopware-cache   ${REDIS_PWD}
sentinel auth-pass shopware-session ${REDIS_PWD}
EOF
sudo chown root:redis /etc/redis/{redis,sentinel}-auth.conf
sudo chmod 640 /etc/redis/{redis,sentinel}-auth.conf

# 3. Fuer CLI-Aufrufe: REDIS_AUTH_PASSWORD exportieren
sudo tee /etc/profile.d/redis-credentials.sh > /dev/null <<'EOF'
export REDIS_AUTH_PASSWORD=$(grep ^requirepass /etc/redis/redis-auth.conf | cut -d'"' -f2)
EOF
sudo chmod 600 /etc/profile.d/redis-credentials.sh

# 4. Fuer Shopware: Passwort in .env.local setzen (siehe .env.example).
#    Dort URL-kodiert eintragen — aus "geheim!2026" wird "geheim%212026".
```

### Secrets und Rewrite

Das `include`-Muster haelt das Passwort **nicht** aus `sentinel.conf` heraus.
Sentinel schreibt seine Konfiguration bei jeder Zustandsaenderung neu und
haengt dabei einen Block `# Generated by CONFIG REWRITE` an, in dem
`sentinel auth-pass <name> <Klartext>` steht. Die `include`-Zeile bleibt zwar
erhalten, das Geheimnis steht ab dem ersten Rewrite aber trotzdem in der
Hauptdatei. Deshalb:

```bash
sudo chown root:redis /etc/redis/sentinel.conf
sudo chmod 640 /etc/redis/sentinel.conf
```

Der Nutzen des `include` liegt damit beim Verteilen und Rotieren, nicht beim
Verbergen vor lokalen Lesern.

### 5. Dienste starten

```bash
sudo systemctl enable --now redis-server@cache redis-server@session
sudo systemctl enable --now redis-sentinel

# Die vorkonfigurierte Einzelinstanz des Pakets wird nicht gebraucht:
sudo systemctl disable --now redis-server
```

### 6. Status pruefen

```bash
source /etc/profile.d/redis-credentials.sh

# Replikation je Instanz (auf dem jeweiligen Master)
redis-cli -p 6379 INFO replication
redis-cli -p 6380 INFO replication

# Sentinel-Quorum. Sentinel bekommt das Master-Passwort NICHT — ein
# unerwartetes AUTH beantwortet er mit "Warning: AUTH failed".
env -u REDISCLI_AUTH redis-cli -p 26379 SENTINEL ckquorum shopware-cache
env -u REDISCLI_AUTH redis-cli -p 26379 SENTINEL ckquorum shopware-session

# Health-Check ueber beide Instanzen
./scripts/redis-monitor.sh
```

`SENTINEL ckquorum` antwortet auf Redis 7.4 mit
`OK 3 usable Sentinels. Quorum and failover authorization can be reached`.
Der Wortlaut nach dem `OK` hat sich zwischen Redis-Versionen geaendert —
Skripte sollten nur auf das fuehrende `OK` pruefen.

### 7. Failover testen

```bash
./scripts/test-failover.sh                  # beide Master nacheinander
./scripts/test-failover.sh shopware-cache   # nur einer
```

Nach einem Failover startet Sentinel fuer denselben Master
`2 * failover-timeout` lang **keinen automatischen** neuen. Ein harter
Ausfalltest direkt nach dem manuellen Test sieht deshalb aus wie ein Defekt,
ist aber nur die Wartezeit. Ein weiteres manuelles `SENTINEL failover` geht
dagegen sofort durch — es umgeht diese Sperre.

## Voraussetzungen

- 3 Server/VMs (koennen auch Shopware-Server sein)
- Ubuntu 22.04/24.04 oder Debian 12
- Ports 6379, 6380 und 26379 zwischen den Nodes geoeffnet
- `ext-redis >= 5.2` **oder** `predis/predis` **oder** `ext-relay` in PHP

## Wichtige Befehle

```bash
# Aktuellen Master ermitteln
env -u REDISCLI_AUTH redis-cli -p 26379 SENTINEL get-master-addr-by-name shopware-cache

# Replicas anzeigen
env -u REDISCLI_AUTH redis-cli -p 26379 SENTINEL replicas shopware-cache

# Manuelles Failover ausloesen
env -u REDISCLI_AUTH redis-cli -p 26379 SENTINEL failover shopware-cache

# Sentinel-Logs beobachten
sudo journalctl -u redis-sentinel -f

# Health-Check als Cronjob (Exit 0/1/2, 64 bei Aufruffehler)
*/5 * * * * . /etc/profile.d/redis-credentials.sh && /opt/redis/redis-monitor.sh >> /var/log/redis/health.log 2>&1
```

## Was `rename-command` hier anrichtet

Fruehere Fassungen dieses Verzeichnisses benannten `CONFIG` per
`rename-command` um. Das macht den Failover unmoeglich: Sentinel braucht
`CONFIG` und `SLAVEOF` auf den ueberwachten Instanzen. Im Test blieb Sentinel
danach in `+failover-state-wait-promotion` haengen, nach zwei Minuten war der
tote Knoten immer noch als Master eingetragen und beide Replicas zeigten
weiter auf ihn. Wer umbenennen will, muss es Sentinel mit
`SENTINEL rename-command <master> CONFIG <neuerName>` mitteilen. Upstream ist
`rename-command` ohnehin als deprecated markiert — stattdessen ACLs benutzen,
siehe `users.acl.example`.

## Gemessene Werte

Testaufbau: Dockware 6.6.10.6 (`APP_ENV=prod`), Demo-Daten, drei Cache- und
drei Session-Instanzen auf Redis 7.4.11, `down-after-milliseconds 5000`,
`failover-timeout 60000`. Sequenzielle Requests mit `curl`, **kein Lasttest**.
Die Zahlen gelten fuer diesen Aufbau, nicht allgemein.

| Messung | Ergebnis |
|---|---|
| Storefront mit Redis | Median 12 ms (min 8, max 19), 0 Fehler bei 15 Requests |
| Storefront mit gestoppten Redis-Instanzen | Median 5.151 ms (min 3.157, max 6.047), 0 Fehler — der Shop bleibt erreichbar, nur langsam |
| Manuelles `SENTINEL failover` | neuer Master nach ~2,1 s (beide Instanzen) |
| Harter Master-Ausfall bis Promotion | ~7 s |
| Storefront waehrend des harten Ausfalls, DSN **ohne** `timeout` | ein Request haengt >= 30 s (Symfony-Default `timeout = 30`) |
| Storefront waehrend des harten Ausfalls, DSN **mit** `&timeout=2&read_timeout=2` | ein Request 8,12 s, alle uebrigen < 150 ms, keine Fehler |

Die sichtbare Ausfallzeit haengt damit nicht an Sentinel, sondern an den
Client-Timeouts in der DSN.

## Predis vs phpredis — Kurz-Entscheidung

Fuer den Sentinel-Betrieb verlangt Symfony **eines von** `predis/predis`,
`ext-redis >= 5.2` oder `ext-relay`. Predis ist **nicht** Pflicht; das im
Kapitel frueher genannte Symfony-Issue #63261 war eine Symfony-Regression in
7.4.4 / 8.0.4, kein phpredis-Fehler, ist geschlossen, und Shopware 6.6.10.6
(symfony/cache 7.2.8) war nie betroffen.

| Kontext | Empfehlung | Grund |
|---|---|---|
| Sentinel-HA mit vorhandener `ext-redis >= 5.2` | phpredis | Kein zusaetzliches Paket, deutlich schneller als der PHP-Client |
| Shared-Hosting ohne `ext-redis` | Predis | Reine PHP-Implementierung, keine Extension noetig |
| Optionen, die die DSN nicht abbildet (z. B. TLS-Kontext) | Predis | Als eigener Service definierbar — siehe `shopware-redis.yaml` |

Beide implementieren dasselbe Symfony-Cache-Adapter-Interface, ein spaeterer
Wechsel geht ohne YAML-Aenderung.

Details: Buch Kap. 10, Subsection "Predis vs phpredis — Client-Wahl".

## Referenzen

- [Redis Sentinel Documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)
- [Shopware Redis Configuration](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html)
- [Predis](https://github.com/predis/predis)
- [phpredis Sentinel](https://github.com/phpredis/phpredis/blob/develop/sentinel.md)
- [Symfony Cache Redis Adapter](https://symfony.com/doc/current/components/cache/adapters/redis_adapter.html)
