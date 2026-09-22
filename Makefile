.PHONY: help install start stop restart benchmark cache-warmup redis-failover analyze-queries logs shell

# Farben
GREEN  := $(shell tput setaf 2)
YELLOW := $(shell tput setaf 3)
RESET  := $(shell tput sgr0)

help: ## Zeigt diese Hilfe
	@echo "$(GREEN)Shopware Performance Examples$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}'

install: ## Shopware installieren (nur beim ersten Start)
	docker-compose exec app bin/console system:install --create-database --basic-setup

start: ## Container starten
	docker-compose up -d

stop: ## Container stoppen
	docker-compose down

restart: stop start ## Container neu starten

benchmark: ## Performance-Tests ausführen
	./scripts/benchmark.sh

# Kapitel 6: wärmt den HTTP-Cache aus der Sitemap (vorher bin/console sitemap:generate).
# Leert keinen Cache und baut keinen Index neu.
PARALLEL ?= 2
LIMIT    ?= 100
cache-warmup: ## HTTP-Cache aus der Sitemap vorwärmen (URL=https://ihr-shop.ch [PARALLEL=4] [LIMIT=500])
	@if [ -z "$(URL)" ]; then echo "Usage: make cache-warmup URL=https://ihr-shop.ch [PARALLEL=4] [LIMIT=500]"; exit 1; fi
	./chapters/06-http-cache/scripts/cache-warmup.sh "$(URL)" --sitemap --parallel $(PARALLEL) --limit $(LIMIT)

redis-failover: ## Redis Failover simulieren (benötigt docker-compose.redis.yml)
	@echo "$(YELLOW)Stoppe Redis Master...$(RESET)"
	docker stop redis-master
	@echo "$(GREEN)Warte auf Failover (5 Sekunden)...$(RESET)"
	sleep 5
	@echo "$(GREEN)Prüfe neuen Master:$(RESET)"
	docker exec sentinel1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster

redis-recover: ## Redis Master wiederherstellen
	@echo "$(GREEN)Starte Redis Master...$(RESET)"
	docker start redis-master
	@echo "$(GREEN)Master ist jetzt Replica des neuen Masters$(RESET)"

analyze-queries: ## Langsame Queries finden
	./scripts/analyze-queries.sh

logs: ## Container-Logs anzeigen
	docker-compose logs -f

logs-redis: ## Redis Sentinel Logs
	docker-compose -f docker-compose.redis.yml logs -f

shell: ## Shell im App-Container öffnen
	docker-compose exec app bash

mysql: ## MySQL-Client öffnen
	docker-compose exec app mysql -u root -proot shopware

redis-cli: ## Redis-CLI öffnen
	docker exec -it shopware-redis redis-cli

# Redis Sentinel Setup
redis-sentinel-up: ## Redis Sentinel Cluster starten
	docker-compose -f docker-compose.redis.yml up -d

redis-sentinel-down: ## Redis Sentinel Cluster stoppen
	docker-compose -f docker-compose.redis.yml down

redis-sentinel-status: ## Sentinel Status prüfen
	@echo "$(GREEN)Master:$(RESET)"
	@docker exec sentinel1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
	@echo ""
	@echo "$(GREEN)Replicas:$(RESET)"
	@docker exec sentinel1 redis-cli -p 26379 SENTINEL replicas mymaster
