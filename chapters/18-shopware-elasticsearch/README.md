# Chapter 18: Shopware 6 Elasticsearch

Companion code for Chapter 18 of "Shop-Performance in 30 Tagen".

This chapter covers Elasticsearch/OpenSearch configuration and optimization for Shopware 6, including heap sizing, German language analysis, custom mappings, and performance monitoring.

## Why Elasticsearch?

| Products | MySQL | Elasticsearch | Factor |
|----------|-------|---------------|--------|
| 10,000 | 2-4s | 20ms | 100-200x |
| 100,000 | 10-20s | 29ms | 350-700x |
| 200,000+ | Timeout | 35ms | ∞ |

**Rule of thumb**: Start evaluating Elasticsearch at 30,000+ products.

## Directory Structure

```
chapters/18-shopware-elasticsearch/
├── config/
│   ├── elasticsearch.yaml     # Shopware ES configuration
│   ├── elasticsearch.yml      # ES server configuration
│   └── jvm.options            # Heap and JVM settings
├── scripts/
│   ├── es-health-check.sh     # Cluster health monitoring
│   ├── es-reindex.sh          # Optimized reindexing
│   ├── es-index-stats.sh      # Index statistics
│   └── es-benchmark.sh        # Performance benchmarks
├── src/
│   └── ElasticsearchExtension/
│       ├── ProductMappingExtension.php   # Custom field mapping
│       ├── CustomAnalyzerDefinition.php  # German analyzers
│       ├── SearchBoostSubscriber.php     # Relevance tuning
│       └── IndexingOptimizer.php         # Bulk indexing
└── README.md
```

## Quick Start

### 1. Install Elasticsearch/OpenSearch

```bash
# For Shopware 6.6+: Use OpenSearch
wget https://artifacts.opensearch.org/releases/bundle/opensearch/2.11.1/opensearch-2.11.1-linux-x64.tar.gz
tar -xzf opensearch-2.11.1-linux-x64.tar.gz
```

### 2. Configure Heap (Critical!)

```bash
# /etc/opensearch/jvm.options.d/heap.options
# Set to 50% of RAM, max 31GB
-Xms8g
-Xmx8g
```

### 3. Configure Shopware

```bash
# .env
ELASTICSEARCH_URL=http://localhost:9200
```

```yaml
# config/packages/elasticsearch.yaml
elasticsearch:
    enabled: true
    hosts: ['%env(ELASTICSEARCH_URL)%']
    index_settings:
        number_of_shards: 1
        number_of_replicas: 0
```

### 4. Initial Index

```bash
bin/console es:create:alias
bin/console es:index --no-queue
```

## Scripts

### Health Check

```bash
./scripts/es-health-check.sh
# Shows cluster status, heap usage, index stats
```

### Optimized Reindex

```bash
./scripts/es-reindex.sh
# Disables refresh, indexes, force merges, re-enables
```

### Performance Benchmark

```bash
./scripts/es-benchmark.sh
# Tests various query types with timing
```

## Configuration Files

### elasticsearch.yaml (Shopware)

Key settings for production:
- `number_of_shards: 1` - Single node
- `number_of_replicas: 0` - No replication needed
- `refresh_interval: 5s` - Balance freshness/performance

### jvm.options (Heap)

The 50% rule:
- Set heap to 50% of available RAM
- Never exceed 31GB (Compressed OOPs limit)
- Always set Xms = Xmx

### elasticsearch.yml (Server)

For single-node setups:
```yaml
discovery.type: single-node
bootstrap.memory_lock: true
```

## PHP Extensions

### ProductMappingExtension

Adds custom fields for:
- Exact product number matching
- Autocomplete optimization
- Custom sorting values
- Nested attributes

### CustomAnalyzerDefinition

German language optimization:
- Stemming (Bücher → Buch)
- Stopword removal
- Edge n-grams for autocomplete
- Cologne phonetic for fuzzy matching

### SearchBoostSubscriber

Relevance tuning:
- Exact match boost (100x)
- Product number boost (80x)
- In-stock boost (1.2x)

### IndexingOptimizer

Bulk indexing helpers:
- Disable refresh during import
- Force merge after completion
- Cache management

## Performance Tips

1. **Heap sizing**: 50% of RAM, max 31GB
2. **Single node**: `shards=1, replicas=0`
3. **Refresh interval**: 30s during indexing, 5s normal
4. **Filter vs Query**: Use `filter` for yes/no, `query` for relevance
5. **Force merge**: After large imports
6. **German analyzer**: Use light_german stemmer

## Monitoring

Check these metrics regularly:
- Heap usage: Keep < 85%
- Segment count: Force merge if > 10
- Search latency: Should be < 100ms
- Indexing rate: Watch for queue buildup

## Troubleshooting

### Cluster Yellow

```bash
# Single node with replicas configured
curl -X PUT "localhost:9200/_settings" \
    -d '{"index": {"number_of_replicas": 0}}'
```

### High Heap Usage

```bash
# Force merge to reduce segments
curl -X POST "localhost:9200/_forcemerge?max_num_segments=1"

# Clear caches
curl -X POST "localhost:9200/_cache/clear"
```

### Slow Queries

Enable slow log:
```yaml
index.search.slowlog.threshold.query.warn: 1s
```

## Resources

- [Shopware ES Docs](https://developer.shopware.com/docs/guides/plugins/plugins/elasticsearch/)
- [OpenSearch Documentation](https://opensearch.org/docs/latest/)
- [Elastic Heap Sizing](https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html)
