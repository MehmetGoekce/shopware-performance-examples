# Performance Incident Postmortem

> **Reminder**: Dies ist ein BLAMELESS Postmortem. Wir analysieren Systeme und
> Prozesse, nicht das Verhalten einzelner Personen. Fehler sind Lernmöglichkeiten.

## Metadata

| Feld | Wert |
|------|------|
| **Incident-ID** | PERF-YYYY-NNN |
| **Datum** | YYYY-MM-DD |
| **Dauer** | X Stunden Y Minuten |
| **Severity** | P1 / P2 / P3 |
| **Facilitator** | @name |
| **Autor** | @name |
| **Reviewer** | @name |
| **Status** | Draft / In Review / Final |

## Executive Summary

<!-- 2-3 Sätze: Was ist passiert, was war der Impact? -->

Am [Datum] um [Uhrzeit] kam es zu einer Performance-Degradation auf [betroffene Seiten].
Die Ursache war [Root Cause]. Der Incident dauerte [Dauer] und betraf ca. [X] Nutzer.

## Impact

### Betroffene Nutzer

- **Geschätzte Anzahl**: ~X Nutzer / X% des Traffics
- **Geografische Verteilung**: DACH / Global
- **Geräte**: Mobile / Desktop / Alle

### Performance-Metriken

| Metrik | Normal | Während Incident | Verschlechterung |
|--------|--------|------------------|------------------|
| LCP (p75) | Xms | Yms | +Z% |
| INP (p75) | Xms | Yms | +Z% |
| CLS (p75) | X | Y | +Z% |

### Business-Impact

- **Conversion Rate**: Normal X% → Incident Y% (ΔZ%)
- **Geschätzter Umsatzverlust**: ~CHF X
- **Support-Tickets**: X neue Tickets
- **SEO-Auswirkung**: Keine / Potentiell / Bestätigt

## Timeline

*Alle Zeiten in CET/CEST*

| Zeit | Ereignis | Aktion |
|------|----------|--------|
| HH:MM | Deployment von PR #XXX | - |
| HH:MM | Erste Anomalie in RUM-Daten | Automatisch erkannt |
| HH:MM | Alert in #performance | PagerDuty/Slack |
| HH:MM | Incident acknowledged | @name |
| HH:MM | Root Cause identifiziert | Investigation |
| HH:MM | Rollback initiiert | Mitigation |
| HH:MM | Performance wiederhergestellt | Verified |
| HH:MM | Incident closed | All-clear |

## Root Cause Analysis

### Was ist passiert?

<!-- Technische Beschreibung - neutral, ohne Schuldzuweisung -->

### 5 Whys

1. **Warum** war [Symptom]?
   → Weil [Ursache 1]

2. **Warum** [Ursache 1]?
   → Weil [Ursache 2]

3. **Warum** [Ursache 2]?
   → Weil [Ursache 3]

4. **Warum** [Ursache 3]?
   → Weil [Ursache 4]

5. **Warum** [Ursache 4]?
   → Weil [Root Cause]

### Contributing Factors

<!-- Was hat zum Incident beigetragen (nicht verursacht)? -->

- [ ] Fehlende Automatisierung
- [ ] Unzureichende Tests
- [ ] Dokumentationslücke
- [ ] Monitoring-Gap
- [ ] Review-Prozess unvollständig
- [ ] Zeitdruck
- [ ] Komplexität des Systems
- [ ] Andere: ___________

## Detection

### Wie wurde der Incident erkannt?

- [ ] Automatischer Alert (RUM)
- [ ] Automatischer Alert (Lighthouse CI)
- [ ] Manuell (interner Nutzer)
- [ ] Extern (Kunde)
- [ ] Support-Ticket

### Detection Time

- **Time to Detection (TTD)**: X Minuten nach Deployment
- **War das schnell genug?**: Ja / Nein - weil ___

## Response

### Was lief gut?

<!-- Positive Aspekte der Incident-Response -->

- Schnelle Erkennung durch RUM-Alerts
- Klare Kommunikation im Team
- Rollback-Prozess funktionierte reibungslos
- ...

### Was hätte besser laufen können?

<!-- Verbesserungspotential - keine Schuldzuweisungen -->

- Klarere Eskalationswege
- Bessere Runbooks
- Schnellere Rollback-Entscheidung
- ...

## Mitigation & Resolution

### Sofortmaßnahmen

| Maßnahme | Status |
|----------|--------|
| Rollback auf Version X.Y.Z | Erledigt |
| Cache invalidiert | Erledigt |
| Kunden informiert | Erledigt |

### Langfristige Fixes

| Maßnahme | PR/Ticket | Status |
|----------|-----------|--------|
| [Beschreibung] | #XXX | Open/Merged |

## Action Items

| ID | Aktion | Typ | Owner | Due Date | Status |
|----|--------|-----|-------|----------|--------|
| 1 | [Konkreter Action Item] | Prevent | @name | YYYY-MM-DD | Open |
| 2 | [Konkreter Action Item] | Detect | @name | YYYY-MM-DD | Open |
| 3 | [Konkreter Action Item] | Mitigate | @name | YYYY-MM-DD | Open |

### Action Item Typen

- **Prevent**: Verhindert, dass dieser Incident erneut auftritt
- **Detect**: Verbessert die Erkennung ähnlicher Probleme
- **Mitigate**: Reduziert den Impact bei ähnlichen Incidents

## Lessons Learned

### Was haben wir gelernt?

<!-- Erkenntnisse, die für andere Teams/Projekte relevant sind -->

1. ...
2. ...
3. ...

### Was sollten wir anderen mitteilen?

<!-- Für All-Hands, Wiki, andere Teams -->

## Supporting Information

### Logs & Screenshots

<!-- Links zu relevanten Logs, Grafana-Dashboards, Screenshots -->

- [RUM Dashboard zum Zeitpunkt](link)
- [Error Logs](link)
- [Deployment Logs](link)

### Related Incidents

<!-- Gab es ähnliche Incidents in der Vergangenheit? -->

- PERF-YYYY-NNN: [Kurzbeschreibung]

---

## Approval

| Rolle | Name | Datum | Signatur |
|-------|------|-------|----------|
| Facilitator | @name | YYYY-MM-DD | ✓ |
| Technical Lead | @name | YYYY-MM-DD | ✓ |
| Product Owner | @name | YYYY-MM-DD | ✓ |

---

*Postmortem erstellt: YYYY-MM-DD*
*Letzte Aktualisierung: YYYY-MM-DD*
*Nächste Review: In 30 Tagen (Action Items Check)*
