# Kapitel 10: Redis fuer Hochverfuegbarkeit

Companion-Code zum Buch **"Shop-Performance in 30 Tagen"**

## Inhalt

Dieses Verzeichnis enthaelt alle Redis-Konfigurationen und Scripts aus Kapitel 10:

### config/
- `redis-master.conf` - Redis Master Konfiguration
- `redis-replica.conf` - Redis Replica Konfiguration
- `sentinel.conf` - Redis Sentinel Konfiguration (fuer alle 3 Nodes)
- `redis-auth.example.conf` - Skeleton fuer Secrets-Datei (requirepass + masterauth)
- `sentinel-auth.example.conf` - Skeleton fuer Sentinel-Secrets (sentinel auth-pass)
- `users.acl.example` - Skeleton fuer Redis 7.x ACL-Persistenz (default off + shopware-User + sentinel-watcher)
- `redis-tls.example.conf` - Skeleton fuer TLS-Direktiven (tls-port, cert-files, mutual TLS, TLS 1.2+1.3)
- `shopware-redis.yaml` - Shopware/Symfony Sentinel-Integration

### scripts/
- `redis-impact-test.sh` - Misst Auswirkung eines Redis-Ausfalls
- `test-failover.sh` - Testet automatisches Sentinel-Failover
- `redis-monitor.sh` - Health-Check und Monitoring Script (erwartet REDIS_AUTH_PASSWORD in der Env)
- `generate-tls-certs.example.sh` - Test-CA + Server-/Client-Cert fuer TLS-Setup (NICHT fuer Production)

### Root
- `.env.example` - Shopware/Symfony Env-Vars (REDIS_AUTH_PASSWORD, Sentinel-Hosts, Service-Name)

## Architektur

```
                    +---------------------+
                    |   Sentinel Quorum   |
                    |  (3 Sentinel Nodes) |
                    +----------+----------+
                               | ueberwacht
         +---------------------+---------------------+
         v                     v                     v
+-----------------+   +-----------------+   +-----------------+
|  Redis Master   |-->|  Redis Replica  |   |  Redis Replica  |
|  192.168.1.1    |   |  192.168.1.2    |   |  192.168.1.3    |
|  Port 6379      |   |  Port 6379      |   |  Port 6379      |
+-----------------+   +-----------------+   +-----------------+
```

## Schnellstart

### 1. Redis auf allen 3 Nodes installieren

```bash
sudo apt update
sudo apt install redis-server redis-sentinel
```

### 2. Konfigurationen verteilen

```bash
# Node 1 (Master)
sudo cp config/redis-master.conf /etc/redis/redis.conf

# Node 2 + 3 (Replicas)
sudo cp config/redis-replica.conf /etc/redis/redis.conf
# WICHTIG: IP des Masters anpassen!

# Alle Nodes (Sentinel)
sudo cp config/sentinel.conf /etc/redis/sentinel.conf
```

### 3. Secrets Management — Passwort generieren und externalisieren

Niemals Passwoerter direkt in `redis-master.conf` / `redis-replica.conf` /
`sentinel.conf` eintragen oder committen. Stattdessen separate Secrets-Datei
(`/etc/redis/redis-auth.conf` + `/etc/redis/sentinel-auth.conf`) anlegen und
per `include`-Direktive einbinden — siehe Buch Kap 10, Subsection
"Secrets Management".

```bash
# 1. Sicheres Passwort generieren
REDIS_PWD=$(openssl rand -base64 32)

# 2. Secrets-Dateien anlegen (auf jedem Node, gleiches Passwort!)
sudo tee /etc/redis/redis-auth.conf > /dev/null <<EOF
requirepass "${REDIS_PWD}"
masterauth "${REDIS_PWD}"
EOF
sudo tee /etc/redis/sentinel-auth.conf > /dev/null <<EOF
sentinel auth-pass shopware-master ${REDIS_PWD}
EOF
sudo chown root:redis /etc/redis/{redis,sentinel}-auth.conf
sudo chmod 640 /etc/redis/{redis,sentinel}-auth.conf

# 3. Fuer CLI-Aufrufe: REDIS_AUTH_PASSWORD in /etc/profile.d/redis-credentials.sh exportieren
sudo tee /etc/profile.d/redis-credentials.sh > /dev/null <<'EOF'
export REDIS_AUTH_PASSWORD=$(grep ^requirepass /etc/redis/redis-auth.conf | cut -d'"' -f2)
EOF
sudo chmod 600 /etc/profile.d/redis-credentials.sh

# 4. Fuer Shopware: Passwort in .env.local setzen (siehe .env.example)
```

### 4. Dienste starten

```bash
sudo systemctl restart redis-server
sudo systemctl start redis-sentinel
sudo systemctl enable redis-sentinel
```

### 5. Status pruefen

```bash
# Replikation pruefen (auf Master, REDIS_AUTH_PASSWORD aus Env)
redis-cli -a "${REDIS_AUTH_PASSWORD}" INFO replication

# Sentinel Quorum pruefen
redis-cli -p 26379 SENTINEL ckquorum shopware-master
```

### 6. Failover testen

```bash
./scripts/test-failover.sh
```

## Voraussetzungen

- 3 Server/VMs (koennen auch Shopware-Server sein)
- Ubuntu 22.04/24.04 oder Debian 12
- Mindestens 2GB RAM pro Redis-Node
- Ports 6379 und 26379 zwischen Nodes geoeffnet

## Wichtige Befehle

```bash
# Aktuellen Master ermitteln
redis-cli -p 26379 SENTINEL get-master-addr-by-name shopware-master

# Replicas anzeigen
redis-cli -p 26379 SENTINEL replicas shopware-master

# Manuelles Failover ausloesen
redis-cli -p 26379 SENTINEL failover shopware-master

# Sentinel-Logs beobachten
tail -f /var/log/redis/sentinel.log

# Health-Check (erwartet REDIS_AUTH_PASSWORD in der Env)
source /etc/profile.d/redis-credentials.sh
./scripts/redis-monitor.sh
```

## Erwartete Ergebnisse

| Metrik | Single Redis | Mit Sentinel |
|--------|--------------|--------------|
| Verfuegbarkeit | ~99% | 99.9%+ |
| Failover-Zeit | Manuell (Minuten) | Automatisch (5-30 Sek) |
| Datenverlust-Risiko | Hoch | Minimal |

## Predis vs phpredis — Kurz-Entscheidung

| Kontext | Empfehlung | Grund |
|---|---|---|
| Sentinel-HA (dieses Setup) | Predis | Vollstaendiger Sentinel-Support seit v1.1.0; phpredis 5.3.2+ hat Symfony-Issue #63261 (Master-Credentials an Sentinel) |
| Single-Redis + High-Throughput lokal | phpredis | 5-6x schneller bei localhost-Redis (~150k vs ~30k ops/sec) |
| Shared-Hosting ohne ext-redis | Predis | Keine PHP-Extension noetig |

Beide implementieren dasselbe Symfony-Cache-Adapter-Interface, also
spaeterer Wechsel ohne YAML-Aenderungen moeglich.

Details: Buch Kap 10, Subsection "Predis vs phpredis — Client-Wahl".

## Referenzen

- [Redis Sentinel Documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)
- [Shopware Redis Configuration](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html)
- [Predis Sentinel Support](https://github.com/predis/predis)
- [phpredis Sentinel](https://github.com/phpredis/phpredis/blob/develop/sentinel.markdown)
- [Symfony Cache Redis Adapter](https://symfony.com/doc/current/components/cache/adapters/redis_adapter.html)
- [Symfony Sentinel Bug #63261](https://github.com/symfony/symfony/issues/63261)
