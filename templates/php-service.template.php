<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;

/**
 * [SERVICE_NAME] - [KURZE_BESCHREIBUNG]
 *
 * [LÄNGERE_BESCHREIBUNG_MIT_KONTEXT]
 *
 * Verwendung:
 *   $service = new [SERVICE_NAME]($logger);
 *   $result = $service->process($input);
 *
 * @see [KAPITEL_REFERENZ]
 */
class ServiceTemplate
{
    public function __construct(
        private readonly LoggerInterface $logger
    ) {}

    /**
     * [METHODEN_BESCHREIBUNG]
     *
     * @param array<string, mixed> $input Eingabedaten
     * @return array{success: bool, data: mixed, error?: string}
     */
    public function process(array $input): array
    {
        try {
            // Implementierung hier
            $result = $this->doProcess($input);

            return [
                'success' => true,
                'data' => $result,
            ];
        } catch (\Throwable $e) {
            $this->logger->error('Process failed', [
                'error' => $e->getMessage(),
                'input' => $input,
            ]);

            return [
                'success' => false,
                'data' => null,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * @param array<string, mixed> $input
     * @return mixed
     */
    private function doProcess(array $input): mixed
    {
        // TODO: Implementierung
        return $input;
    }
}
