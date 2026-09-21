<?php declare(strict_types=1);

namespace PerformanceTheme;

use Shopware\Core\Framework\Plugin;
use Shopware\Storefront\Framework\ThemeInterface;

/**
 * Theme-Plugin zu Kapitel 16.
 *
 * ThemeInterface macht das Plugin zum Theme: Es erscheint unter
 * «Inhalte > Themes» und lässt sich per `theme:change` zuweisen.
 */
class PerformanceTheme extends Plugin implements ThemeInterface
{
}
