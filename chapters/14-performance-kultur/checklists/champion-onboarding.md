# Performance Champion Onboarding Checklist

Willkommen als Performance Champion! Diese Checklist führt dich durch die
ersten 4 Wochen deiner neuen Rolle.

---

## Woche 1: Grundlagen

### Tag 1-2: Core Web Vitals

- [ ] **web.dev/vitals** durcharbeiten (2-3 Stunden)
  - [ ] LCP verstehen (was, warum, wie messen)
  - [ ] INP verstehen (ersetzt FID seit März 2024)
  - [ ] CLS verstehen (Layout Shifts)

- [ ] **Shopware-Dokumentation** lesen
  - [ ] Performance-Sektion in der Entwickler-Doku
  - [ ] HTTP-Cache Dokumentation
  - [ ] Caching-Konzepte

### Tag 3-4: Tool-Zugänge

- [ ] **Monitoring-Tools**
  - [ ] RUM-Dashboard Zugang erhalten
  - [ ] Lighthouse CI Zugang erhalten
  - [ ] Alerting-Kanäle abonniert

- [ ] **Entwickler-Tools**
  - [ ] Chrome DevTools Performance Tab erkunden
  - [ ] Lighthouse in DevTools ausprobieren
  - [ ] Network Panel verstehen

- [ ] **Kommunikation**
  - [ ] #performance Slack-Channel beitreten
  - [ ] Performance-Wiki/Confluence finden
  - [ ] Relevante E-Mail-Listen/Gruppen

### Tag 5: Shadowing

- [ ] **Erfahrenen Champion begleiten**
  - [ ] Bei Code Review zusehen
  - [ ] Dashboard-Review gemeinsam
  - [ ] Fragen stellen!

---

## Woche 2: Tools & Monitoring

### Chrome DevTools Mastery

- [ ] **Performance Tab**
  - [ ] Recording starten/stoppen
  - [ ] Flame Chart lesen
  - [ ] Main Thread Aktivität verstehen
  - [ ] Long Tasks identifizieren

- [ ] **Network Tab**
  - [ ] Waterfall verstehen
  - [ ] Resource Timing analysieren
  - [ ] Throttling verwenden
  - [ ] Cache deaktivieren für Tests

- [ ] **Lighthouse Tab**
  - [ ] Full Audit durchführen
  - [ ] Report interpretieren
  - [ ] Opportunities und Diagnostics verstehen

### RUM-Dashboard

- [ ] **Walkthrough mit Mentor**
  - [ ] Core Web Vitals Panel verstehen
  - [ ] Percentile-Konzept (p50, p75, p90)
  - [ ] Segmentierung (Gerät, Seite, Region)
  - [ ] Trend-Analyse

- [ ] **Alert-Konfiguration**
  - [ ] Bestehende Alerts verstehen
  - [ ] Wann werden wir benachrichtigt?
  - [ ] Eskalationspfade kennen

### Lighthouse CI

- [ ] **Pipeline verstehen**
  - [ ] Wann laufen Tests?
  - [ ] Was passiert bei Failure?
  - [ ] Wo sind die Reports?

- [ ] **Lokale Nutzung**
  - [ ] LHCI CLI installiert
  - [ ] Lokalen Test durchgeführt

---

## Woche 3: Praxis

### Code Reviews

- [ ] **Erste Reviews durchführen**
  - [ ] Checklist verwenden (code-review-performance.md)
  - [ ] Mindestens 3 PRs reviewen
  - [ ] Konstruktives Feedback geben

- [ ] **Feedback einholen**
  - [ ] War mein Review hilfreich?
  - [ ] Habe ich etwas übersehen?

### Performance-Issue finden

- [ ] **Proaktive Analyse**
  - [ ] Dashboard auf Auffälligkeiten prüfen
  - [ ] Langsamste Seiten identifizieren
  - [ ] Ein konkretes Issue dokumentieren

### Optimierung vorschlagen

- [ ] **Issue-Ticket erstellen**
  - [ ] Problem beschreiben
  - [ ] Impact schätzen
  - [ ] Lösungsvorschlag machen

- [ ] **Implementierung** (wenn Zeit)
  - [ ] Fix entwickeln
  - [ ] Messbar verbessern (Before/After)

### Dokumentation

- [ ] **Wiki-Beitrag schreiben**
  - [ ] Gelerntes dokumentieren
  - [ ] Für andere Champions nützlich

---

## Woche 4: Kommunikation

### Team-Präsentation

- [ ] **Brown Bag Session vorbereiten** (10-15 min)
  - [ ] Thema wählen (z.B. "Wie lese ich das Performance-Dashboard?")
  - [ ] Slides/Demo vorbereiten
  - [ ] Termin koordinieren

- [ ] **Präsentation halten**
  - [ ] Feedback sammeln
  - [ ] Q&A beantworten

### Slack-Moderation

- [ ] **#performance Channel**
  - [ ] Woche lang aktiv moderieren
  - [ ] Fragen beantworten (oder weiterleiten)
  - [ ] Relevante News/Updates posten

### Performance-Report

- [ ] **Ersten Report erstellen**
  - [ ] Template verwenden
  - [ ] Aktuelle Metriken einfügen
  - [ ] Trend analysieren
  - [ ] Mit Mentor reviewen

### Feedback-Gespräch

- [ ] **Mit Mentor/Lead besprechen**
  - [ ] Was lief gut?
  - [ ] Wo brauche ich mehr Support?
  - [ ] Nächste Ziele setzen

---

## Abschluss Woche 4

### Self-Assessment

- [ ] Ich verstehe Core Web Vitals und kann sie erklären
- [ ] Ich kann das RUM-Dashboard interpretieren
- [ ] Ich kann Performance-Code-Reviews durchführen
- [ ] Ich weiß, wen ich bei Fragen kontaktieren kann
- [ ] Ich fühle mich bereit, als Champion zu agieren

### Mentor-Bestätigung

- [ ] Champion hat Grundlagen verstanden
- [ ] Champion kann selbständig arbeiten
- [ ] Offene Fragen geklärt
- [ ] Support-Plan für erste 3 Monate

---

## Nach dem Onboarding

### Monat 2-3: Vertiefung

- [ ] Spezialisierung wählen (Frontend/Backend/Infra)
- [ ] Erste Postmortem-Teilnahme
- [ ] Größere Optimierung umsetzen
- [ ] Champion-Network beitreten

### Ongoing

- [ ] Wöchentliche Routine etabliert
- [ ] Regelmäßige Reviews
- [ ] Knowledge Sharing
- [ ] Kontinuierliches Lernen

---

## Ressourcen

### Pflichtlektüre
- [ ] web.dev/vitals
- [ ] Shopware Performance-Dokumentation
- [ ] Interne Wiki-Seiten

### Empfohlen
- [ ] "High Performance Browser Networking" (Ilya Grigorik)
- [ ] web.dev/learn (Performance-Abschnitt)
- [ ] Performance Calendar (perfplanet.com)

### Communities
- [ ] Interner #performance Channel
- [ ] web-perf Slack
- [ ] Twitter/X: @chromiumdev, @WebPlatformNews

---

*Checklist Version 1.0 | Letzte Aktualisierung: 2024-01*
