<?php

declare(strict_types=1);

/**
 * Naht zum Einbettungs-Backend fuer den additiven Vektorpfad
 * Kapitel 18: Shopware 6 mit Elasticsearch, Abschnitt 18.12
 *
 * Eigene Datei, nicht ans Ende von ProductEmbeddingSubscriber.php gehaengt:
 * Shopware-Plugins laden per PSR-4 ueber den Klassennamen. Eine zweite
 * Klasse in einer fremd benannten Datei wird nur zufaellig gefunden — naemlich
 * dann, wenn die erste Klasse aus derselben Datei schon geladen ist. Ein
 * Service, der auf dieses Interface typisiert ist, laeuft sonst in
 * «class not found».
 *
 * @see https://github.com/MehmetGoekce/shopware-performance-examples
 */

namespace YourPlugin\ElasticsearchExtension;

/**
 * Implementierung gehoert ins eigene Bundle; die Abwaegungen (Latenzbudget,
 * DSGVO/AVV, Cache fuer Anfrage-Vektoren) stehen in 18.12.
 */
interface EmbeddingClient
{
    /**
     * @param list<string> $ids
     *
     * @return array<string, string> productId => einzubettender Text
     */
    public function loadProductTexts(array $ids): array;

    /**
     * @param list<string> $texts
     *
     * @return list<list<float>> ein Vektor je Text, gleiche Reihenfolge
     */
    public function embed(array $texts): array;
}
