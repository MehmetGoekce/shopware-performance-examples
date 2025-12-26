# Kapitel 10: Redis High Availability

Code-Beispiele für Redis Sentinel Setup in Shopware 6.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `../../docker-compose.redis.yml` | Redis Sentinel Cluster (3 Nodes) |
| `../../src/Service/RedisSentinelFactory.php` | PHP Factory für Sentinel-Verbindungen |
| `../../config/packages/redis.yaml` | Shopware Redis-Konfiguration |

## Quick Start

```bash
# Redis Sentinel Cluster starten
docker-compose -f docker-compose.redis.yml up -d

# Status prüfen
docker exec sentinel1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster

# Failover simulieren
docker stop redis-master

# Neuen Master prüfen (nach ~5 Sekunden)
docker exec sentinel1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
```

## Architektur

```
                    ┌─────────────┐
                    │  Shopware   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────┴─────┐ ┌────┴────┐ ┌─────┴─────┐
        │ Sentinel1 │ │Sentinel2│ │ Sentinel3 │
        │  :26379   │ │ :26380  │ │  :26381   │
        └─────┬─────┘ └────┬────┘ └─────┬─────┘
              │            │            │
              └────────────┼────────────┘
                           │
                    ┌──────┴──────┐
                    │   Master    │
                    │   :6379     │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
        ┌─────┴─────┐             ┌─────┴─────┐
        │  Replica1 │             │  Replica2 │
        │   :6380   │             │   :6381   │
        └───────────┘             └───────────┘
```

## Sentinel Parameter

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `quorum` | 2 | Min. Sentinels für Failover-Entscheidung |
| `down-after-milliseconds` | 5000 | Master gilt als down nach 5s |
| `failover-timeout` | 10000 | Max. Zeit für Failover |
| `parallel-syncs` | 1 | Replicas die gleichzeitig synchen |

## Shopware-Integration

```php
// In services.xml
$sentinelFactory = new RedisSentinelFactory(
    ['localhost:26379', 'localhost:26380', 'localhost:26381'],
    'mymaster',
    null,
    $logger
);

$redis = $sentinelFactory->createConnection();
$redis->set('test', 'value');
```

## Weiterführende Dokumentation

- [Redis Sentinel Docs](https://redis.io/docs/management/sentinel/)
- [Shopware Cache Docs](https://developer.shopware.com/docs/guides/hosting/performance/caching)
- Buch Kapitel 10: Redis High Availability
