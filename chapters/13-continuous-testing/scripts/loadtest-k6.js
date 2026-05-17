// loadtest-k6.js — Last-Test für Shopware 6 (Grafana k6, Open Source)
// Kapitel 13: Continuous Testing
//
// Ausführen:   k6 run loadtest-k6.js
// Gegen URL:   k6 run -e BASE_URL=https://staging.example.com loadtest-k6.js
//
// WICHTIG: niemals gegen Production — Staging mit produktionsnaher
// Datenmenge und identischer Cache-Konfiguration.
//
// @see https://github.com/MehmetGoekce/shopware-performance-examples

/* global __ENV */ // k6-Runtime-Global (von der k6-Engine bereitgestellt)

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';

export const options = {
    stages: [
        { duration: '1m', target: 50 },   // Ramp-up
        { duration: '3m', target: 50 },   // Plateau
        { duration: '1m', target: 0 },    // Ramp-down
    ],
    thresholds: {
        http_req_duration: ['p(95)<800'], // 95 % der Requests < 800 ms
        http_req_failed: ['rate<0.01'],   // < 1 % Fehler
    },
};

export default function () {
    // Gecachter Pfad (Startseite)
    const home = http.get(`${BASE_URL}/`);
    check(home, { 'home 200': (r) => r.status === 200 });

    // Uncachebarer Pfad (Suche) — hier zeigt sich DB/PHP-Last
    const search = http.get(`${BASE_URL}/search?search=shirt`);
    check(search, { 'search 200': (r) => r.status === 200 });

    sleep(1);
}
