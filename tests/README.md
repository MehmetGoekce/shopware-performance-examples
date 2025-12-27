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

### Phase 2: Static Analysis (Pending)
- [ ] ShellCheck alle 39 Scripts fixen (Warnings beheben)
- [ ] PHPStan Level 6 Errors fixen
- [ ] ESLint Konfiguration + Fixes
- [ ] Twig Linting einrichten

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
composer analyze
npm run lint
npm run shellcheck

# Coverage Reports generieren
composer test:coverage  # -> coverage/index.html
npm run test:coverage   # -> coverage/index.html
```
