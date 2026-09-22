<?php

declare(strict_types=1);

namespace AbTesting\Log;

use AbTesting\Experiment\ExperimentConfig;
use Monolog\LogRecord;
use Monolog\Processor\ProcessorInterface;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * Schreibt die Variante in jede Zeile des RUM-Logs aus Kapitel 12.
 *
 * Der Beacon an /api/rum ist ein Aufruf derselben Domain, der Browser schickt
 * das Experiment-Cookie mit. Aus {"metric":"LCP",...} wird
 * {"metric":"LCP",...,"exp_listing_images":"eager"}.
 */
final class ExperimentLogProcessor implements ProcessorInterface
{
    public function __construct(
        private readonly RequestStack $requestStack,
        private readonly ExperimentConfig $config,
    ) {
    }

    public function __invoke(LogRecord $record): LogRecord
    {
        $request = $this->requestStack->getCurrentRequest();

        if ($request === null) {
            return $record;
        }

        $context = $record->context;
        foreach ($this->config->all() as $key => $experiment) {
            $name = ExperimentConfig::cookieName($key);
            $variant = $request->cookies->get($name);

            if ($this->config->isVariant($key, $variant)) {
                $context[$name] = $variant;
            }
        }

        return $record->with(context: $context);
    }
}
