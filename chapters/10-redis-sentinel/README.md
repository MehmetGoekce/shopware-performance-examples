# Kapitel 10: Redis fuer Hochverfuegbarkeit

Companion-Code zum Buch **"Shop-Performance in 30 Tagen"**

## Inhalt

Dieses Verzeichnis enthaelt alle Redis-Konfigurationen und Scripts aus Kapitel 10:

### config/
- `redis-master.conf` - Redis Master Konfiguration
- `redis-replica.conf` - Redis Replica Konfiguration
- `sentinel.conf` - Redis Sentinel Konfiguration (fuer alle 3 Nodes)
- `shopware-redis.yaml` - Shopware/Symfony Sentinel-Integration

### scripts/
- `redis-impact-test.sh` - Misst Auswirkung eines Redis-Ausfalls
- `test-failover.sh` - Testet automatisches Sentinel-Failover
- `redis-monitor.sh` - Health-Check und Monitoring Script

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

### 3. Passwort generieren und einsetzen

```bash
# Sicheres Passwort generieren
openssl rand -base64 32

# In allen Konfigurationsdateien ersetzen:
# - redis-master.conf: requirepass + masterauth
# - redis-replica.conf: requirepass + masterauth
# - sentinel.conf: sentinel auth-pass
```

### 4. Dienste starten

```bash
sudo systemctl restart redis-server
sudo systemctl start redis-sentinel
sudo systemctl enable redis-sentinel
```

### 5. Status pruefen

```bash
# Replikation pruefen (auf Master)
redis-cli -a "IhrPasswort" INFO replication

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
```

## Erwartete Ergebnisse

| Metrik | Single Redis | Mit Sentinel |
|--------|--------------|--------------|
| Verfuegbarkeit | ~99% | 99.9%+ |
| Failover-Zeit | Manuell (Minuten) | Automatisch (5-30 Sek) |
| Datenverlust-Risiko | Hoch | Minimal |

## Referenzen

- [Redis Sentinel Documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)
- [Shopware Redis Configuration](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html)
- [Predis Sentinel Support](https://github.com/predis/predis)
