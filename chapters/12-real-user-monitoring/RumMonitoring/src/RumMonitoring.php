<?php

declare(strict_types=1);

namespace RumMonitoring;

use Shopware\Core\Framework\Plugin;
use Symfony\Component\DependencyInjection\ContainerBuilder;

/**
 * Kapitel 12: Real User Monitoring
 *
 * build() laedt zusaetzlich Resources/config/packages/*.yaml - dort liegt der
 * Monolog-Kanal "rum". Ohne diesen Aufruf ignoriert Shopware den Ordner bei
 * Plugins still.
 *
 * @see \Shopware\Core\Framework\Bundle::buildDefaultConfig()
 */
class RumMonitoring extends Plugin
{
    public function build(ContainerBuilder $container): void
    {
        parent::build($container);

        $this->buildDefaultConfig($container);
    }
}
