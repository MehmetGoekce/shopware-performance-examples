<?php

declare(strict_types=1);

namespace AbTesting;

use Shopware\Core\Framework\Plugin;
use Symfony\Component\DependencyInjection\ContainerBuilder;

/**
 * Kapitel 20: A/B Testing & Performance-Experimente
 *
 * build() laedt zusaetzlich Resources/config/packages/*.yaml - dort liegt der
 * Monolog-Kanal "ab_testing". Ohne diesen Aufruf ignoriert Shopware den Ordner
 * bei Plugins still (wie bei RumMonitoring aus Kapitel 12).
 *
 * @see \Shopware\Core\Framework\Bundle::buildDefaultConfig()
 */
class AbTesting extends Plugin
{
    public function build(ContainerBuilder $container): void
    {
        parent::build($container);

        $this->buildDefaultConfig($container);
    }
}
