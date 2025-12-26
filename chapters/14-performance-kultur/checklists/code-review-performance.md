# Performance Code Review Checklist

Diese Checklist hilft bei der systematischen Prüfung von PRs auf Performance-Aspekte.

> **Tipp**: Nicht jeder PR braucht eine vollständige Prüfung. Fokussiere dich auf
> die relevanten Abschnitte basierend auf den geänderten Dateien.

---

## Quick Check (für jeden PR)

- [ ] **Neue Dependencies**: Wurden neue npm/composer Packages hinzugefügt?
  - [ ] Bundle-Size geprüft (bundlephobia.com)
  - [ ] Alternative leichtere Packages evaluiert?
- [ ] **Große Dateien**: Wurden große Assets (Bilder, Videos) hinzugefügt?
  - [ ] Optimiert und komprimiert?
  - [ ] Lazy Loading implementiert?
- [ ] **Offensichtliche Red Flags**:
  - [ ] Keine synchronen Remote-Calls im Request-Lifecycle
  - [ ] Keine unbegrenzten Loops/Queries
  - [ ] Keine `console.log` in Production-Code

---

## JavaScript / TypeScript

### Bundle Size
- [ ] Keine unnötigen Imports (Tree-Shaking möglich?)
- [ ] Dynamische Imports für nicht-kritische Module (`import()`)
- [ ] Keine ganzen Libraries importiert wenn nur eine Funktion benötigt
  ```javascript
  // Schlecht
  import _ from 'lodash';
  // Gut
  import debounce from 'lodash/debounce';
  ```

### Async Operations
- [ ] I/O-Operationen sind async (`async/await`, Promises)
- [ ] Parallele Requests werden mit `Promise.all` gebündelt
- [ ] Error-Handling blockiert nicht

### Event Handling
- [ ] Scroll/Resize Events: `debounce` oder `throttle` verwendet
- [ ] Keine teuren Operationen in Event-Loops
- [ ] Event-Listener werden korrekt entfernt (Memory Leaks)

### Critical Path
- [ ] Kritischer JavaScript-Code ist minimal
- [ ] Nicht-kritischer Code ist `defer` oder `async`
- [ ] Third-Party Scripts werden asynchron geladen

### DOM Operations
- [ ] Batch-Updates statt einzelner DOM-Manipulationen
- [ ] `requestAnimationFrame` für Animationen
- [ ] Virtual Scrolling für lange Listen

---

## PHP / Symfony

### Datenbankabfragen
- [ ] **N+1 Problem**: Keine Queries in Loops
  ```php
  // Schlecht
  foreach ($products as $product) {
      $product->getManufacturer()->getName();  // Query pro Iteration
  }
  // Gut: Eager Loading mit Criteria
  $criteria->addAssociation('manufacturer');
  ```
- [ ] **Nur nötige Felder**: `addFields()` statt ganzer Entities
- [ ] **Limit gesetzt**: Keine unbegrenzten Queries
- [ ] **Indexes**: Werden neue Queries von Indexes abgedeckt?

### Caching
- [ ] Cache-Keys sind sinnvoll gewählt
- [ ] TTL ist angemessen (nicht zu kurz, nicht zu lang)
- [ ] Cache-Invalidierung ist korrekt implementiert
- [ ] Keine Circular Dependencies bei Cache-Tags

### Memory
- [ ] Große Datenmengen werden gestreamt, nicht komplett geladen
- [ ] Temporäre Variablen werden freigegeben
- [ ] Keine Memory Leaks durch Static-Properties

### Blocking I/O
- [ ] Keine synchronen HTTP-Calls in Request-Lifecycle
- [ ] Externe APIs werden mit Timeouts aufgerufen
- [ ] Fallbacks bei externen Service-Ausfällen

---

## Templates (Twig)

### Layout Shifts (CLS)
- [ ] Bilder haben `width` und `height` Attribute
- [ ] Fonts haben `font-display: swap` oder `optional`
- [ ] Dynamische Inhalte haben Platzhalter/Skeleton

### Asset Loading
- [ ] Kritisches CSS ist inline
- [ ] Non-kritisches CSS ist async geladen
- [ ] JavaScript ist `defer` oder am Ende des Body
- [ ] Fonts sind preloaded (`<link rel="preload">`)

### Images
- [ ] WebP mit Fallback verwendet
- [ ] Responsive Images (`srcset`, `sizes`)
- [ ] Lazy Loading für Below-the-fold (`loading="lazy"`)
- [ ] Keine überdimensionierten Bilder

### Third-Party
- [ ] Externe Scripts sind async
- [ ] `rel="preconnect"` für externe Domains
- [ ] Fallback wenn Third-Party nicht lädt

---

## Assets

### Bilder
- [ ] Format: WebP (mit JPEG/PNG Fallback)
- [ ] Größe: Nicht größer als Display-Größe
- [ ] Komprimierung: Qualität vs. Dateigröße optimiert
- [ ] Alt-Text vorhanden (Accessibility + SEO)

### SVGs
- [ ] Optimiert (SVGO)
- [ ] Keine unnötigen Metadaten
- [ ] Inline vs. External je nach Use Case

### Fonts
- [ ] Nur verwendete Weights/Styles
- [ ] Subset wenn möglich (nur lateinische Zeichen)
- [ ] Preload für kritische Fonts
- [ ] Fallback-Fonts definiert

---

## Caching & CDN

### HTTP-Header
- [ ] Cache-Control korrekt gesetzt
- [ ] ETags verwendet
- [ ] Vary-Header wo nötig

### Shopware Cache
- [ ] Cache-Tags sind korrekt
- [ ] Invalidierung ist präzise (nicht zu breit)
- [ ] HTTP-Cache vs. Object-Cache richtig gewählt

### CDN
- [ ] Assets gehen über CDN
- [ ] Invalidierung bei Deployment bedacht
- [ ] Edge-Caching für statische Seiten

---

## Shopware-spezifisch

### DAL (Data Abstraction Layer)
- [ ] Criteria sind optimiert
- [ ] Nur nötige Associations geladen
- [ ] Aggregationen statt Post-Processing

### Plugins
- [ ] Events/Hooks sind performant
- [ ] Keine Subscriber die bei jedem Request laufen
- [ ] Cache-Decorator wo sinnvoll

### Storefront
- [ ] Twig-Extensions sind gecached
- [ ] Keine teuren Operationen in Snippets
- [ ] Theme-Kompilierung beachtet

---

## Review-Ergebnis

### Approve wenn:
- [ ] Keine Performance-Regressions zu erwarten
- [ ] Best Practices befolgt
- [ ] Verbesserungen ggf. als Follow-up geplant

### Request Changes wenn:
- [ ] Klare Performance-Regression
- [ ] Kritische Best Practices verletzt
- [ ] Einfacher Fix möglich

### Kommentare hinzufügen wenn:
- [ ] Verbesserungspotential, aber kein Blocker
- [ ] Education-Opportunity
- [ ] Follow-up Ticket sinnvoll

---

## Kommentar-Templates

### Performance-Bedenken
```markdown
## Performance-Bedenken

**Was**: [Beschreibung]
**Wo**: `datei.php:123`
**Impact**: [LCP/INP/CLS/Memory/...]

### Vorschlag
\`\`\`diff
- // Problematischer Code
+ // Optimierter Code
\`\`\`

### Ressourcen
- [Link zu Dokumentation]
```

### Performance-Lob
```markdown
## Gute Performance-Entscheidung

Danke für [spezifische Optimierung]. Das verbessert [Metrik] weil [Begründung].
```

### Follow-up Vorschlag
```markdown
## Follow-up Opportunity

Kein Blocker, aber wir könnten [Verbesserung] als nächsten Schritt machen.

Soll ich ein Ticket erstellen?
```
