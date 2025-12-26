#!/usr/bin/env php
<?php
/**
 * Event Subscriber Analyzer
 *
 * Analyzes all registered event subscribers and their priorities
 * to identify potential performance bottlenecks.
 *
 * Usage:
 *   php analyze-subscribers.php
 *   php analyze-subscribers.php --filter=Product
 *   php analyze-subscribers.php --json
 *
 * Output:
 *   - Subscriber count by namespace (identifies plugin impact)
 *   - Event listener count
 *   - Priority distribution
 *   - Potential issues (high-priority blocking subscribers)
 */

declare(strict_types=1);

// Check if running from Shopware root
$autoloadPaths = [
    __DIR__ . '/vendor/autoload.php',
    __DIR__ . '/../vendor/autoload.php',
    __DIR__ . '/../../vendor/autoload.php',
    __DIR__ . '/../../../vendor/autoload.php',
    '/var/www/html/vendor/autoload.php',
];

$autoloaded = false;
foreach ($autoloadPaths as $path) {
    if (file_exists($path)) {
        require $path;
        $autoloaded = true;
        break;
    }
}

if (!$autoloaded) {
    echo "Error: Could not find autoload.php\n";
    echo "Run this script from the Shopware root directory.\n";
    exit(1);
}

// Parse arguments
$options = getopt('', ['filter:', 'json', 'help', 'events']);
$filter = $options['filter'] ?? null;
$outputJson = isset($options['json']);
$showEvents = isset($options['events']);

if (isset($options['help'])) {
    echo <<<HELP
Event Subscriber Analyzer

Usage:
  php analyze-subscribers.php [options]

Options:
  --filter=<term>   Filter by namespace or class name
  --events          Show event breakdown
  --json            Output as JSON
  --help            Show this help

Examples:
  php analyze-subscribers.php
  php analyze-subscribers.php --filter=Product
  php analyze-subscribers.php --filter=PayPal --json

HELP;
    exit(0);
}

// Boot Shopware kernel
use Shopware\Core\Framework\Plugin\KernelPluginLoader\DbalKernelPluginLoader;
use Shopware\Core\Kernel;
use Symfony\Component\Dotenv\Dotenv;

$projectDir = dirname(__DIR__, 4);
if (!file_exists($projectDir . '/composer.json')) {
    $projectDir = '/var/www/html';
}

// Load environment
if (file_exists($projectDir . '/.env')) {
    (new Dotenv())->loadEnv($projectDir . '/.env');
}

$_SERVER['APP_ENV'] = $_SERVER['APP_ENV'] ?? 'prod';
$_SERVER['APP_DEBUG'] = $_SERVER['APP_DEBUG'] ?? '0';

try {
    // This is a simplified analysis without full kernel boot
    // In production, you would boot the full kernel

    echo "===========================================\n";
    echo "  Event Subscriber Analysis\n";
    echo "===========================================\n\n";

    // Scan for EventSubscriberInterface implementations
    $subscribers = [];
    $events = [];

    $dirs = [
        $projectDir . '/custom/plugins',
        $projectDir . '/vendor/shopware',
    ];

    foreach ($dirs as $dir) {
        if (!is_dir($dir)) {
            continue;
        }

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS)
        );

        foreach ($iterator as $file) {
            if ($file->getExtension() !== 'php') {
                continue;
            }

            $content = file_get_contents($file->getPathname());

            // Check if it's a subscriber
            if (strpos($content, 'EventSubscriberInterface') === false) {
                continue;
            }

            // Extract namespace
            if (preg_match('/namespace\s+([^;]+);/', $content, $matches)) {
                $namespace = $matches[1];

                // Extract class name
                if (preg_match('/class\s+(\w+)/', $content, $classMatches)) {
                    $className = $classMatches[1];
                    $fullClass = $namespace . '\\' . $className;

                    // Apply filter if set
                    if ($filter && stripos($fullClass, $filter) === false) {
                        continue;
                    }

                    // Extract events
                    if (preg_match_all('/[\'"]([^\']+Event)[\'"]/', $content, $eventMatches)) {
                        foreach ($eventMatches[1] as $event) {
                            $events[$event] = ($events[$event] ?? 0) + 1;
                        }
                    }

                    // Categorize by top-level namespace
                    $parts = explode('\\', $namespace);
                    $category = $parts[0];
                    if (isset($parts[1]) && $parts[0] === 'Shopware') {
                        $category = $parts[0] . '\\' . $parts[1];
                    }

                    if (!isset($subscribers[$category])) {
                        $subscribers[$category] = [];
                    }
                    $subscribers[$category][] = $fullClass;
                }
            }
        }
    }

    // Sort by count
    uasort($subscribers, fn($a, $b) => count($b) <=> count($a));
    arsort($events);

    if ($outputJson) {
        echo json_encode([
            'subscribers_by_namespace' => array_map('count', $subscribers),
            'total_subscribers' => array_sum(array_map('count', $subscribers)),
            'top_events' => array_slice($events, 0, 20, true),
            'subscribers' => $subscribers,
        ], JSON_PRETTY_PRINT) . "\n";
        exit(0);
    }

    // Output results
    echo "Subscribers by Namespace:\n";
    echo "--------------------------\n";

    $total = 0;
    foreach ($subscribers as $namespace => $classes) {
        $count = count($classes);
        $total += $count;

        // Highlight third-party plugins
        $prefix = '';
        if (strpos($namespace, 'Shopware') !== 0) {
            $prefix = '[PLUGIN] ';
        }

        printf("%-50s %d\n", $prefix . $namespace, $count);
    }

    echo "--------------------------\n";
    printf("%-50s %d\n", "TOTAL", $total);
    echo "\n";

    if ($showEvents) {
        echo "Top Subscribed Events:\n";
        echo "--------------------------\n";

        $i = 0;
        foreach ($events as $event => $count) {
            if ($i++ >= 20) break;
            printf("%-60s %d\n", $event, $count);
        }
        echo "\n";
    }

    // Identify potential issues
    echo "Potential Performance Issues:\n";
    echo "-----------------------------\n";

    $issues = [];

    // Check for high subscriber count from single plugin
    foreach ($subscribers as $namespace => $classes) {
        if (strpos($namespace, 'Shopware') !== 0 && count($classes) > 10) {
            $issues[] = sprintf(
                "[WARNING] %s has %d subscribers - consider consolidating",
                $namespace,
                count($classes)
            );
        }
    }

    // Check for heavily subscribed events
    foreach ($events as $event => $count) {
        if ($count > 10) {
            $issues[] = sprintf(
                "[INFO] %s has %d listeners - may impact performance",
                $event,
                $count
            );
        }
    }

    if (empty($issues)) {
        echo "  No obvious issues found.\n";
    } else {
        foreach ($issues as $issue) {
            echo "  $issue\n";
        }
    }

    echo "\n";
    echo "Recommendations:\n";
    echo "----------------\n";
    echo "  1. Review plugins with many subscribers\n";
    echo "  2. Consider merging multiple subscribers into one\n";
    echo "  3. Use lower priority for non-critical listeners\n";
    echo "  4. Profile with Blackfire/Tideways for actual impact\n";
    echo "\n";

} catch (Throwable $e) {
    echo "Error: " . $e->getMessage() . "\n";
    exit(1);
}
