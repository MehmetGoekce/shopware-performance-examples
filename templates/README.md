# Code Templates

Vorlagen für neue Dateien in den Kapiteln 20-25.

## Verwendung

1. Template kopieren
2. Platzhalter `[...]` ersetzen
3. In passendes Kapitel-Verzeichnis verschieben
4. Tests schreiben

## Verfügbare Templates

| Template | Beschreibung | Ziel |
|----------|--------------|------|
| `php-service.template.php` | PHP Service-Klasse | `chapters/XX/src/` |
| `php-test.template.php` | PHPUnit Test | `tests/Unit/` |
| `js-class.template.js` | JavaScript ES6 Klasse | `chapters/XX/src/` |
| `js-test.template.test.js` | Vitest Test | `tests/JavaScript/` |
| `shell-script.template.sh` | Bash Script | `chapters/XX/scripts/` |
| `twig-storefront.template.html.twig` | Shopware Storefront | `chapters/XX/templates/` |

## Qualitätsstandards

Alle Dateien müssen folgende Prüfungen bestehen:

```bash
# PHP
composer analyze                    # PHPStan Level 6
composer test                       # PHPUnit

# JavaScript
npm run lint                        # ESLint
npm test                            # Vitest

# Shell
npm run shellcheck                  # ShellCheck

# Twig
composer twig                       # Twig CS Fixer
```

## Beispiel: Neues Kapitel hinzufügen

```bash
# 1. Verzeichnis erstellen
mkdir -p chapters/25-new-topic/{src,scripts,templates,config}

# 2. Templates kopieren und anpassen
cp templates/php-service.template.php chapters/25-new-topic/src/NewService.php
cp templates/shell-script.template.sh chapters/25-new-topic/scripts/setup.sh

# 3. Tests erstellen
cp templates/php-test.template.php tests/Unit/NewServiceTest.php
cp templates/js-test.template.test.js tests/JavaScript/new-feature.test.js

# 4. Linting prüfen
composer analyze && npm run lint && npm run shellcheck

# 5. Tests ausführen
composer test && npm test
```

## Platzhalter-Referenz

| Platzhalter | Beschreibung |
|-------------|--------------|
| `[CLASS_NAME]` | Name der Klasse |
| `[SERVICE_NAME]` | Name des Services |
| `[KURZE_BESCHREIBUNG]` | Einzeiler-Beschreibung |
| `[LÄNGERE_BESCHREIBUNG]` | Ausführliche Beschreibung |
| `[KAPITEL_REFERENZ]` | Link zum Buch-Kapitel |
| `[AUTHOR]` | Autor-Name |
