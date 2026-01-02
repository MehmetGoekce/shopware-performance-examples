<?php

declare(strict_types=1);

/**
 * Stub classes for Shopware dependencies in unit tests.
 *
 * These stubs allow testing Shopware-dependent code without
 * requiring the full Shopware installation.
 */

namespace Shopware\Core\System\SystemConfig;

class SystemConfigService
{
    public function get(string $key, ?string $salesChannelId = null): mixed
    {
        return null;
    }

    public function set(string $key, mixed $value, ?string $salesChannelId = null): void
    {
    }
}

namespace Shopware\Storefront\Theme;

class ThemeService
{
    public function compileTheme(
        string $salesChannelId,
        string $themeId,
        \Shopware\Core\Framework\Context $context,
        ?callable $configurationCollection = null
    ): void {
    }
}

namespace Shopware\Core\Framework;

class Context
{
    public static function createDefaultContext(): self
    {
        return new self();
    }
}
