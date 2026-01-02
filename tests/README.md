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

### Phase 3: Unit Tests erweitern (Done)

**Status:** 247 tests (166 PHP + 81 JavaScript)

#### PHP Unit Tests (166 tests)
- [x] `StatisticalAnalyzer.php` - 15 tests (Welch's t-test, Bayesian, Sample Size)
- [x] `FeatureFlagService.php` - 17 tests (11 pass, 6 skipped due to readonly)
- [x] `ThemePerformanceAnalyzer.php` - 28 tests (with Shopware stubs)
- [x] Existing tests - 31 tests
- [x] Twig Snapshot Tests - 75 tests (15 templates x 5 test types)

#### JavaScript Unit Tests (81 tests)
- [x] `analyze-experiment.test.js` - 22 tests (statistical analysis, CLI parsing)
- [x] `coverage-analysis.test.js` - 27 tests (render-blocking, bundle analysis)
- [x] `network-aware-images.test.js` - 23 tests (existing)
- [x] `config-validation.test.js` - 9 tests (existing)

### Phase 4: E2E & Integration Tests (Done)

**Status:** Playwright E2E tests + Twig Snapshots created

#### Playwright E2E Tests
- [x] `swipe-gestures.spec.ts` - Touch gesture detection, ProductGallery, SwipeToDelete
- [x] `service-worker.spec.ts` - SW lifecycle, caching strategies, offline behavior
- [x] `rum-tracker.spec.ts` - Web Vitals collection, analytics integration

#### Test Fixtures
- [x] `fixtures/swipe-gestures.html` - Touch gesture test page
- [x] `fixtures/service-worker.html` - Service Worker test page
- [x] `fixtures/rum-tracker.html` - RUM tracker test page

#### Twig Snapshot Tests (75 tests)
- [x] 15 templates with snapshot verification
- [x] Block structure validation
- [x] Twig syntax validation
- [x] UTF-8 encoding checks
- [x] Performance pattern analysis

### Phase 5: Neue Kapitel (20-25) (Done)

**Status:** Templates, Hooks, und Tools eingerichtet

#### Templates
- [x] `templates/php-service.template.php` - PHP Service-Klasse
- [x] `templates/php-test.template.php` - PHPUnit Test
- [x] `templates/js-class.template.js` - JavaScript ES6 Klasse
- [x] `templates/js-test.template.test.js` - Vitest Test
- [x] `templates/shell-script.template.sh` - Bash Script
- [x] `templates/twig-storefront.template.html.twig` - Shopware Storefront

#### Pre-commit Hook
- [x] Husky fuer Git Hooks
- [x] lint-staged fuer staged files
- [x] ESLint fuer JavaScript
- [x] ShellCheck fuer Bash Scripts

#### Scripts
- [x] `scripts/update-snapshots.sh` - Automatische Snapshot-Updates
- [x] `scripts/coverage-by-chapter.sh` - Coverage-Report pro Kapitel

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

# Coverage per chapter
./scripts/coverage-by-chapter.sh
./scripts/coverage-by-chapter.sh --json

# Snapshot management
./scripts/update-snapshots.sh         # Update all snapshots
./scripts/update-snapshots.sh --check # Check if snapshots are outdated
```
