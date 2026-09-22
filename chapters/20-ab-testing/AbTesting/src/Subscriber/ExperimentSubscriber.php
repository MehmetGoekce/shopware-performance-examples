<?php

declare(strict_types=1);

namespace AbTesting\Subscriber;

use AbTesting\Experiment\ExperimentConfig;
use AbTesting\Experiment\VariantPicker;
use Psr\Log\LoggerInterface;
use Shopware\Storefront\Event\StorefrontRenderEvent;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\Cookie;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Weist Besucher auf den Routen eines Experiments einer Variante zu und
 * stellt sie den Templates als experimentVariants bereit.
 *
 * Eine neue Zuweisung darf nicht in den HTTP-Cache: Die Antwort traegt das
 * Set-Cookie, und der Cache wuerde es an jeden weiteren Besucher ohne Cookie
 * ausliefern - alle bekaemen die Variante des ersten. Deshalb wird genau diese
 * Antwort "private". Ab dem zweiten Aufruf hat der Besucher das Cookie, und
 * der CacheKeySubscriber legt je Variante einen eigenen Cache-Eintrag an.
 */
class ExperimentSubscriber implements EventSubscriberInterface
{
    private const NEW_ASSIGNMENTS = '_ab_testing_new';

    private const COOKIE_LIFETIME = 30 * 24 * 3600;

    public function __construct(
        private readonly ExperimentConfig $config,
        private readonly LoggerInterface $assignmentLogger,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            StorefrontRenderEvent::class => 'onRender',
            // Nach Shopwares CacheResponseSubscriber::setResponseCache (-1500),
            // der die Antwort sonst wieder "public" macht
            KernelEvents::RESPONSE => ['onResponse', -2000],
        ];
    }

    public function onRender(StorefrontRenderEvent $event): void
    {
        $request = $event->getRequest();
        $experiments = $this->config->forRoute((string) $request->attributes->get('_route'));

        if ($experiments === []) {
            return;
        }

        $variants = [];
        $new = $request->attributes->get(self::NEW_ASSIGNMENTS, []);

        foreach ($experiments as $key => $experiment) {
            $cookie = $request->cookies->get(ExperimentConfig::cookieName($key));

            if ($this->config->isVariant($key, $cookie)) {
                $variants[$key] = $cookie;
                continue;
            }

            $variants[$key] = $new[$key] ??= VariantPicker::random($experiment['variants']);
        }

        $request->attributes->set(self::NEW_ASSIGNMENTS, $new);
        $event->setParameter('experimentVariants', $variants);
    }

    public function onResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        $new = $request->attributes->get(self::NEW_ASSIGNMENTS, []);

        if ($new === []) {
            return;
        }

        $response = $event->getResponse();

        foreach ($new as $key => $variant) {
            $response->headers->setCookie(
                Cookie::create(ExperimentConfig::cookieName($key), $variant)
                    ->withExpires(time() + self::COOKIE_LIFETIME)
                    ->withSecure($request->isSecure())
                    ->withSameSite(Cookie::SAMESITE_LAX)
            );

            // Fuer den SRM-Test in ab:analyze: eine Zeile je Zuweisung
            $this->assignmentLogger->info('assignment', ['experiment' => $key, 'variant' => $variant]);
        }

        $response->setPrivate();
    }
}
