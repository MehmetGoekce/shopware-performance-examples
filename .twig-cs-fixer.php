<?php

declare(strict_types=1);

use TwigCsFixer\Config\Config;
use TwigCsFixer\File\Finder;
use TwigCsFixer\Ruleset\Ruleset;
use TwigCsFixer\Standard\TwigCsFixer;
use TwigCsFixer\Rules\Literal\SingleQuoteRule;
use TwigCsFixer\Rules\Whitespace\EmptyLinesRule;
use TwigCsFixer\Rules\Function\IncludeFunctionRule;
use TwigCsFixer\Rules\Punctuation\TrailingCommaMultiLineRule;
use TwigCsFixer\Rules\Delimiter\DelimiterSpacingRule;

$finder = Finder::create()
    ->in(__DIR__ . '/chapters')
    ->name('*.html.twig')
    // Exclude templates with Shopware-specific tags (sw_thumbnails, sw_extends)
    // that the standard Twig parser cannot handle
    ->notPath('04-image-optimization/templates/cms-element-image.html.twig')
    ->notPath('04-image-optimization/templates/sw-thumbnails-examples.html.twig');

$ruleset = new Ruleset();
$ruleset->addStandard(new TwigCsFixer());

// Remove rules that conflict with book examples and Shopware conventions:
// - SingleQuoteRule: Book examples use double quotes for visibility
// - EmptyLinesRule: Extra blank lines used for section separation in teaching code
// - IncludeFunctionRule: Shopware convention uses {% include %} tag, not {{ include() }}
// - TrailingCommaMultiLineRule: Not strictly enforced in examples
$ruleset->removeRule(SingleQuoteRule::class);
$ruleset->removeRule(EmptyLinesRule::class);
$ruleset->removeRule(IncludeFunctionRule::class);
$ruleset->removeRule(TrailingCommaMultiLineRule::class);
// - DelimiterSpacingRule: Book uses right-aligned comments for visual structure
$ruleset->removeRule(DelimiterSpacingRule::class);

$config = new Config();
$config->setFinder($finder);
$config->setRuleset($ruleset);

return $config;
