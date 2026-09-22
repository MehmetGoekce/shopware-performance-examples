<?php

declare(strict_types=1);

namespace AbTesting\Subscriber;

use AbTesting\Experiment\ExperimentConfig;
use Shopware\Core\Framework\Adapter\Cache\Event\HttpCacheKeyEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Ein Cache-Eintrag je Variante im eingebauten HTTP-Cache.
 *
 * HttpCacheKeyEvent gibt es ab Shopware 6.5.8.0. Der Cache-Key entsteht vor dem
 * Routing, die Route ist hier also nicht bekannt: Jede Seite bekommt fuer
 * Besucher mit Experiment-Cookie einen eigenen Eintrag je Variante. Hinter
 * Varnish wirkt das Event nicht (dort entscheidet die VCL).
 */
class CacheKeySubscriber implements EventSubscriberInterface
{
    public function __construct(private readonly ExperimentConfig $config)
    {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            HttpCacheKeyEvent::class => 'onCacheKey',
        ];
    }

    public function onCacheKey(HttpCacheKeyEvent $event): void
    {
        foreach ($this->config->all() as $key => $experiment) {
            $name = ExperimentConfig::cookieName($key);
            $variant = $event->request->cookies->get($name);

            // Nur bekannte Varianten, sonst legt jeder erfundene Wert einen Eintrag an
            if ($this->config->isVariant($key, $variant)) {
                $event->add($name, $variant);
            }
        }
    }
}
