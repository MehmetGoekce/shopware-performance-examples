# Performance Onboarding für neue Teammitglieder

Diese Checklist hilft neuen Entwicklern, sich mit unseren Performance-Praktiken
vertraut zu machen.

---

## Tag 1-3: Erste Orientierung

### Entwicklungsumgebung

- [ ] Lokale Shopware-Installation läuft
- [ ] Kann `bin/console` Befehle ausführen
- [ ] Browser DevTools funktionieren

### Grundverständnis

- [ ] **Was sind Core Web Vitals?** (15 min)
  - Kurze Erklärung: LCP, INP, CLS
  - Warum sind sie wichtig? (Google Ranking, User Experience)
  - Unsere aktuellen Werte kennen

- [ ] **Performance-Slack-Channel** beigetreten
  - [ ] #performance Channel finden
  - [ ] Pinned Messages lesen
  - [ ] Performance Champion kennenlernen

### Erste Berührung

- [ ] **Lighthouse Audit durchführen**
  - Chrome DevTools öffnen
  - Lighthouse Tab
  - "Generate Report" für Startseite
  - Report überfliegen

---

## Woche 1: Tools kennenlernen

### Chrome DevTools

- [ ] **Performance Tab** (mit Mentor)
  - Recording starten
  - Einfache Flame Chart Interpretation
  - Wissen: Hier findet man Performance-Probleme

- [ ] **Network Tab**
  - Wasserfall-Ansicht verstehen
  - Große/langsame Requests finden
  - Cache deaktivieren können

### Interne Tools

- [ ] **RUM-Dashboard Zugang**
  - Login funktioniert
  - Startseite verstehen
  - Wissen: Hier sehen wir echte User-Daten

- [ ] **CI-Pipeline**
  - Wissen: Performance-Tests laufen automatisch
  - Wo findet man Ergebnisse?

---

## Woche 2: Prozesse verstehen

### Code Review

- [ ] **Performance-Checklist** erhalten
  - Checklist durchlesen
  - Bei eigenem PR beachten
  - Wissen: Performance ist Teil jedes Reviews

- [ ] **PR-Template** kennen
  - Performance-Abschnitt verstehen
  - Wissen: Was muss ich ausfüllen?

### Definition of Done

- [ ] **Performance-Kriterien** kennen
  - Was muss erfüllt sein?
  - Wann ist ein Feature "fertig"?

### Eskalation

- [ ] **Wen frage ich bei Performance-Fragen?**
  - Performance Champion: [Name]
  - Slack: #performance
  - Dokumentation: [Link]

---

## Monat 1: Erste Praxis

### Eigene PR mit Performance-Fokus

- [ ] **Vor dem Commit**
  - Lighthouse lokal laufen lassen
  - Offensichtliche Probleme beheben
  - Performance-Checklist durchgehen

- [ ] **Im PR**
  - Performance-Überlegungen dokumentieren
  - Bilder optimiert?
  - Neue Dependencies klein?

### Performance-Optimierung

- [ ] **Kleine Verbesserung umsetzen**
  - Mit Champion ein Issue identifizieren
  - Fix implementieren
  - Before/After messen
  - PR erstellen

### Knowledge Sharing

- [ ] **Brown Bag besuchen**
  - Mindestens eine Session besuchen
  - Fragen stellen

---

## Nach Monat 1

### Selbsteinschätzung

Ich kann...

- [ ] erklären, was LCP, INP und CLS sind
- [ ] Chrome DevTools für Performance nutzen
- [ ] einen Lighthouse-Audit durchführen und verstehen
- [ ] unsere Performance-Checklist bei PRs anwenden
- [ ] wissen, wen ich bei Fragen kontaktiere

### Offene Fragen klären

- [ ] Feedback-Gespräch mit Mentor
- [ ] Offene Fragen dokumentiert
- [ ] Nächste Lernziele gesetzt

---

## Ressourcen für Selbststudium

### Empfohlen (nach Onboarding)

1. **web.dev/learn** - Performance-Modul
2. **Shopware Academy** - Performance-Kurse (falls verfügbar)
3. **Interne Wiki** - [Link einfügen]

### Bei Interesse

4. **Chrome DevTools Dokumentation**
5. **web.dev/vitals** - Deep Dive
6. **Performance Calendar** (jährlich im Dezember)

---

## Mentor-Notizen

*Für den Onboarding-Buddy:*

- [ ] Erster Tag: 30 min Performance-Intro gegeben
- [ ] Woche 1: DevTools Session (1h)
- [ ] Woche 2: Prozess-Walkthrough
- [ ] Monat 1: Erstes Performance-PR begleitet
- [ ] Check-in: Offene Fragen geklärt

---

*Onboarding Version 1.0 | Dauer: ~5-10 Stunden über 4 Wochen*
