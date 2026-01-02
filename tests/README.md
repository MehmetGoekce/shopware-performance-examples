# Test Suite

This directory contains all tests for the Shopware Performance Examples.

## Test Types

| Directory | Framework | Description |
|-----------|-----------|-------------|
| `Unit/` | PHPUnit | PHP unit tests |
| `Integration/` | PHPUnit | Shopware integration tests |
| `JavaScript/` | Vitest | Node.js tests |
| `E2E/` | Playwright | Browser tests |
| `Shell/` | BATS | Shell script tests |
| `Snapshots/` | PHPUnit | Twig template snapshots |

## Running Tests

### PHP Tests

```bash
# Install dependencies
composer install

# Run all PHP tests
composer test

# Run with coverage
composer test:coverage

# Run static analysis
composer analyze
```

### JavaScript Tests

```bash
# Install dependencies
npm install

# Run Vitest tests
npm test

# Run with coverage
npm run test:coverage

# Run Playwright E2E tests
npm run test:e2e
```

### Shell Script Tests

```bash
# Lint all shell scripts
npm run shellcheck

# Run BATS tests
npm run bats
```

## CI/CD

All tests run automatically on push/PR via GitHub Actions.

See `.github/workflows/test.yml` for configuration.

## Coverage Goals

| Metric | Target |
|--------|--------|
| PHP Coverage | ≥80% |
| JS Coverage | ≥70% |
| Shell Lint | 0 errors |

---

## Roadmap / Next Steps

### Phase 1: Setup (Done)
- [x] composer.json mit PHPUnit, PHPStan
- [x] package.json mit Vitest, Playwright, ESLint
- [x] .shellcheckrc Konfiguration
- [x] GitHub Actions CI Workflow
- [x] Basis-Tests erstellt

### Phase 2: Static Analysis (Done)
- [x] ShellCheck alle 69 Scripts - 0 Warnings (40 Warnings gefixt)
- [x] PHPStan Level 6 standalone - 0 Errors (922 → 0)
- [x] PHPStan mit Shopware 6.6 - 0 Errors (54 API-Issues dokumentiert)
- [x] ESLint Konfiguration - 0 Errors (24 JS-Dateien, nur Warnings fuer unused vars)
- [x] Twig Linting - 0 Errors (13 Dateien, 2 Shopware-spezifische ausgeschlossen)

#### PHPStan Konfigurationen

| Config | Beschreibung | Command |
|--------|--------------|---------|
| `phpstan.neon` | Standalone (ohne Shopware) | `composer analyze` |
| `phpstan-shopware.neon` | Mit Shopware 6.6 Autoloader | `composer analyze:shopware` |

#### Bekannte Shopware 6.6 Inkompatibilitäten

Die folgenden API-Änderungen wurden dokumentiert (temporär ignoriert):

| Issue | Betroffene Dateien | Fix |
|-------|-------------------|-----|
| `CacheTagCollector` → `CacheTagCollection` | CacheTagSubscriber.php | ✅ Gefixt |
| `Entity::getStock()` etc. | CachedProductService.php | Type-Hint `ProductEntity` |
| `Context::getSalesChannelId()` | CachedProductService.php | `SalesChannelContext` nutzen |
| `Criteria::addCriteria()` | OptimizedProductService.php | Existiert nicht |
| `StorefrontRenderEvent::setParameters()` | ScriptLoadingSubscriber.php | Deprecated |

### Phase 3: Unit Tests erweitern (Pending)
- [ ] Tests fuer alle PHP Services (29 Dateien)
  - [ ] `08-database/src/Service/CachedProductService.php`
  - [ ] `17-shopware-plugins/src/Service/*.php`
  - [ ] `18-shopware-elasticsearch/src/*.php`
- [ ] Tests fuer alle JavaScript Utilities (15 Dateien)
  - [ ] `03-core-web-vitals/scripts/cwv-diagnostics.js`
  - [ ] `05-css-javascript/scripts/*.js`
  - [ ] `16-shopware-themes/src/*.js`
- [ ] BATS Tests fuer kritische Shell Scripts
  - [ ] `07-shopware-cache/scripts/cache-warmup.php`
  - [ ] `18-shopware-elasticsearch/scripts/es-reindex.sh`

### Phase 4: Integration Tests (Pending)
- [ ] Shopware Integration Tests (mit Mocks)
- [ ] Playwright E2E Tests fuer Browser-Code
  - [ ] Service Worker Tests
  - [ ] Touch Gesture Tests
  - [ ] RUM Tracker Tests
- [ ] Twig Snapshot Tests

### Phase 5: Neue Kapitel (20-25)
- [ ] Test-Template pro Dateityp bereitstellen
- [ ] Pre-commit Hook fuer Linting
- [ ] Automatische Snapshot-Updates
- [ ] Coverage-Report pro Kapitel

---

## Quick Commands

```bash
# Alles auf einmal testen
composer install && npm install
composer test && npm test && npm run shellcheck

# Nur Linting
composer analyze               # PHPStan standalone
composer analyze:shopware      # PHPStan mit Shopware 6.6 Types
npm run lint
npm run shellcheck

# Coverage Reports generieren
composer test:coverage  # -> coverage/index.html
npm run test:coverage   # -> coverage/index.html
```
