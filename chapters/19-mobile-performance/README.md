# Chapter 19: Mobile Performance

Companion code for Chapter 19 of "Shop-Performance in 30 Tagen".

This chapter covers mobile performance optimization for Shopware 6, including Core Web Vitals, touch optimization, responsive images, Service Workers, and mobile checkout.

## The Mobile Performance Gap

| Metric | Mobile | Desktop |
|--------|--------|---------|
| Traffic Share | 75% | 25% |
| Conversion Rate | 2.85% | 3.85% |
| Cart Abandonment | 85.65% | 73.76% |

**Every 0.1s improvement = 8.4% higher conversion rate.**

## Directory Structure

```
chapters/19-mobile-performance/
├── config/
│   └── manifest.json              # PWA Web App Manifest
├── scripts/
│   ├── mobile-audit.sh            # Quick mobile audit
│   └── lighthouse-mobile.sh       # Lighthouse mobile test
├── src/
│   ├── ServiceWorker/
│   │   ├── sw.js                  # Service Worker with caching
│   │   └── register.js            # SW registration & updates
│   ├── TouchOptimization/
│   │   ├── touch-targets.css      # Touch-friendly sizes
│   │   └── swipe-gestures.js      # Swipe detection
│   └── ResponsiveImages/
│       ├── responsive-picture.html.twig  # Twig template
│       └── network-aware-images.js       # Adaptive loading
├── templates/
│   └── mobile-checkout.html.twig  # One-page mobile checkout
└── README.md
```

## Quick Start

### 1. Run Mobile Audit

```bash
./scripts/mobile-audit.sh https://your-shop.com
```

### 2. Run Lighthouse Mobile Test

```bash
./scripts/lighthouse-mobile.sh https://your-shop.com --iterations=3
```

### 3. Add Service Worker

```html
<!-- In your base template -->
<script type="module" src="/path/to/register.js"></script>
```

### 4. Add PWA Manifest

```html
<link rel="manifest" href="/manifest.json">
<meta name="theme-color" content="#1a1a1a">
```

## Key Components

### Service Worker (`sw.js`)

Implements multiple caching strategies:

| Strategy | Use Case |
|----------|----------|
| Cache First | CSS, JS, fonts |
| Network First | API calls |
| Stale While Revalidate | Images |
| Network Only | Checkout, cart |

### Touch Optimization

Ensures all interactive elements meet accessibility guidelines:

- WCAG 2.2 (AA): 24×24 CSS pixels minimum
- WCAG 2.1 (AAA): 44×44 CSS pixels minimum
- Material Design: 48×48 dp recommended

```css
/* Include in your theme */
@import 'touch-targets.css';
```

### Swipe Gestures

```javascript
import { SwipeGesture, ProductGallery } from './swipe-gestures.js';

// Product gallery with swipe
const gallery = new ProductGallery(element, images, {
    loop: true,
    autoplay: false
});
```

### Responsive Images

```twig
{% sw_include '@Storefront/component/responsive-picture.html.twig' with {
    media: product.cover.media,
    alt: product.name,
    lazy: true,
    priority: false,
    sizes: '(max-width: 480px) 100vw, 50vw'
} %}
```

### Network-Aware Loading

Adapts image quality based on connection:

- 4G: Full quality
- 3G: 70% quality
- 2G/Slow: 40% quality
- Data Saver: Minimal

```javascript
import { NetworkAwareImages } from './network-aware-images.js';
NetworkAwareImages.init();
```

### Mobile Checkout

One-page checkout with:

- 37% higher conversion vs multi-page
- Accordion sections
- Touch-optimized inputs (48px)
- Sticky order summary
- Express checkout options

## Core Web Vitals Targets

| Metric | Good | Needs Work | Poor |
|--------|------|------------|------|
| LCP | ≤2.5s | 2.5-4s | >4s |
| INP | ≤200ms | 200-500ms | >500ms |
| CLS | ≤0.1 | 0.1-0.25 | >0.25 |

## Mobile-First Indexing Checklist

Since July 2024, Google uses mobile-only indexing:

- [ ] Same content on mobile and desktop
- [ ] Viewport meta tag with `width=device-width`
- [ ] No `user-scalable=no` (accessibility)
- [ ] Touch targets ≥44px
- [ ] Font size ≥16px for inputs
- [ ] No content hidden only on mobile
- [ ] Same structured data on both

## Performance Tips

1. **Images**: Use srcset + sizes, serve WebP/AVIF
2. **Touch**: Minimum 44×44px touch targets
3. **Checkout**: One-page, guest checkout, express options
4. **Fonts**: Use `font-display: swap`
5. **JS**: Defer non-critical, use code splitting
6. **Service Worker**: Cache static assets, network-first for API

## Testing

### Chrome DevTools

1. Open DevTools (F12)
2. Toggle Device Toolbar (Ctrl+Shift+M)
3. Select mobile device preset
4. Enable CPU throttling (4x slowdown)
5. Enable network throttling (3G)

### Real Device Testing

1. Enable USB debugging on Android
2. Connect device via USB
3. Open `chrome://inspect` in Chrome
4. Find your device and click "Inspect"

## Resources

- [Google Mobile-First Indexing](https://developers.google.com/search/docs/crawling-indexing/mobile/mobile-sites-mobile-first-indexing)
- [Core Web Vitals](https://web.dev/articles/vitals)
- [WCAG Touch Target Size](https://www.w3.org/WAI/WCAG21/Understanding/target-size.html)
- [Service Worker Strategies](https://developer.chrome.com/docs/workbox/caching-strategies-overview/)
