#!/bin/bash

###############################################################################
# Partytown Setup Script
#
# Installiert und konfiguriert Partytown für Third-Party Scripts in Shopware 6.
# Partytown verschiebt Third-Party Scripts in Web Workers für bessere Performance.
#
# Usage:
#   ./partytown-setup.sh
#   ./partytown-setup.sh --uninstall
#
# @author Mehmet Gökçe
# @since 1.0.0
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SHOPWARE_ROOT="${SHOPWARE_ROOT:-$(pwd)}"
THEME_PATH="${SHOPWARE_ROOT}/custom/plugins/YourTheme"
PUBLIC_PATH="${SHOPWARE_ROOT}/public"
PARTYTOWN_VERSION="0.10.2"

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠  $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not installed"
        exit 1
    fi
}

###############################################################################
# Installation Functions
###############################################################################

install_partytown() {
    print_header "Installing Partytown for Shopware 6"

    # Check prerequisites
    print_step "Checking prerequisites..."
    check_command "npm"
    check_command "node"

    if [ ! -d "$SHOPWARE_ROOT" ]; then
        print_error "Shopware root directory not found: $SHOPWARE_ROOT"
        exit 1
    fi

    print_success "Prerequisites OK"
    echo ""

    # Install Partytown
    print_step "Installing Partytown via npm..."
    cd "$SHOPWARE_ROOT"

    if [ ! -f "package.json" ]; then
        print_warning "Creating package.json..."
        npm init -y
    fi

    npm install --save @builder.io/partytown@${PARTYTOWN_VERSION}
    print_success "Partytown installed"
    echo ""

    # Copy Partytown files to public directory
    print_step "Copying Partytown library files..."
    mkdir -p "${PUBLIC_PATH}/~partytown"

    if [ -d "node_modules/@builder.io/partytown/lib" ]; then
        cp -r node_modules/@builder.io/partytown/lib/* "${PUBLIC_PATH}/~partytown/"
        print_success "Partytown files copied to public/~partytown/"
    else
        print_error "Partytown library files not found"
        exit 1
    fi
    echo ""

    # Create configuration file
    print_step "Creating Partytown configuration..."
    create_partytown_config
    print_success "Configuration created"
    echo ""

    # Create integration snippets
    print_step "Creating integration snippets..."
    create_integration_snippets
    print_success "Snippets created"
    echo ""

    # Instructions
    print_header "Installation Complete!"
    echo -e "${GREEN}Next Steps:${NC}"
    echo ""
    echo "1. Add Partytown snippet to your theme's base template:"
    echo "   ${YELLOW}templates/base.html.twig${NC}"
    echo ""
    echo "2. Include the snippet before closing </head> tag:"
    echo "   ${YELLOW}{% include '@Storefront/storefront/partytown/init.html.twig' %}${NC}"
    echo ""
    echo "3. Move your third-party scripts to Partytown:"
    echo "   ${YELLOW}<script type=\"text/partytown\">...</script>${NC}"
    echo ""
    echo "4. Build your theme:"
    echo "   ${YELLOW}bin/build-storefront.sh${NC}"
    echo ""
    echo "Examples and documentation:"
    echo "   ${YELLOW}${SHOPWARE_ROOT}/partytown-examples/${NC}"
    echo ""
}

create_partytown_config() {
    cat > "${PUBLIC_PATH}/partytown-config.js" << 'EOF'
/**
 * Partytown Configuration for Shopware 6
 *
 * @see https://partytown.builder.io/configuration
 */
partytown = {
    // Forward specific methods/properties to main thread
    forward: [
        // Google Analytics
        'dataLayer.push',
        'gtag',

        // Facebook Pixel
        'fbq',

        // Google Tag Manager
        'google_tag_manager',

        // Custom events
        'dataLayer',
    ],

    // Resolve URLs for external scripts
    resolveUrl: function(url, location, type) {
        // Allow Google services
        if (url.hostname.includes('google-analytics.com') ||
            url.hostname.includes('googletagmanager.com') ||
            url.hostname.includes('google.com')) {
            return url;
        }

        // Allow Facebook
        if (url.hostname.includes('facebook.net') ||
            url.hostname.includes('facebook.com')) {
            return url;
        }

        // Allow other common CDNs
        if (url.hostname.includes('cloudflare.com') ||
            url.hostname.includes('jsdelivr.net') ||
            url.hostname.includes('unpkg.com')) {
            return url;
        }

        return url;
    },

    // Debug mode (set to false in production)
    debug: false,

    // Log method calls
    logCalls: false,

    // Log get/set operations
    logGetters: false,
    logSetters: false,

    // Log image requests
    logImageRequests: false,

    // Log script execution
    logScriptExecution: false,

    // Log stack traces
    logStackTraces: false,
};
EOF
}

create_integration_snippets() {
    SNIPPETS_DIR="${SHOPWARE_ROOT}/templates/storefront/partytown"
    mkdir -p "$SNIPPETS_DIR"

    # Init snippet
    cat > "${SNIPPETS_DIR}/init.html.twig" << 'EOF'
{#
  Partytown Initialization
  Include this in your base template before closing </head> tag
#}
<script>
    // Partytown configuration
    {% include '@Storefront/storefront/partytown/config.html.twig' %}
</script>

{# Partytown library #}
<script src="/~partytown/partytown.js"></script>
EOF

    # Config snippet
    cat > "${SNIPPETS_DIR}/config.html.twig" << 'EOF'
{# Partytown Configuration #}
<script src="/partytown-config.js"></script>
EOF

    # Google Analytics example
    cat > "${SNIPPETS_DIR}/google-analytics.html.twig" << 'EOF'
{#
  Google Analytics 4 with Partytown

  Usage:
    {% include '@Storefront/storefront/partytown/google-analytics.html.twig' with {
        measurementId: 'G-XXXXXXXXXX'
    } %}
#}
{% if measurementId is defined %}
<script type="text/partytown" async src="https://www.googletagmanager.com/gtag/js?id={{ measurementId }}"></script>
<script type="text/partytown">
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', '{{ measurementId }}');
</script>
{% endif %}
EOF

    # Google Tag Manager example
    cat > "${SNIPPETS_DIR}/google-tag-manager.html.twig" << 'EOF'
{#
  Google Tag Manager with Partytown

  Usage:
    {% include '@Storefront/storefront/partytown/google-tag-manager.html.twig' with {
        containerId: 'GTM-XXXXXXX'
    } %}
#}
{% if containerId is defined %}
<script type="text/partytown">
    (function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
    new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
    j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
    'https://www.googletagmanager.com/gtm.js?id='+i+dl;j.type='text/partytown';
    f.parentNode.insertBefore(j,f);
    })(window,document,'script','dataLayer','{{ containerId }}');
</script>

{# NoScript fallback #}
<noscript>
    <iframe src="https://www.googletagmanager.com/ns.html?id={{ containerId }}"
            height="0" width="0" style="display:none;visibility:hidden"></iframe>
</noscript>
{% endif %}
EOF

    # Facebook Pixel example
    cat > "${SNIPPETS_DIR}/facebook-pixel.html.twig" << 'EOF'
{#
  Facebook Pixel with Partytown

  Usage:
    {% include '@Storefront/storefront/partytown/facebook-pixel.html.twig' with {
        pixelId: 'XXXXXXXXXXXXXXX'
    } %}
#}
{% if pixelId is defined %}
<script type="text/partytown">
    !function(f,b,e,v,n,t,s)
    {if(f.fbq)return;n=f.fbq=function(){n.callMethod?
    n.callMethod.apply(n,arguments):n.queue.push(arguments)};
    if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
    n.queue=[];t=b.createElement(e);t.async=!0;
    t.src=v;t.type='text/partytown';s=b.getElementsByTagName(e)[0];
    s.parentNode.insertBefore(t,s)}(window, document,'script',
    'https://connect.facebook.net/en_US/fbevents.js');

    fbq('init', '{{ pixelId }}');
    fbq('track', 'PageView');
</script>

<noscript>
    <img height="1" width="1" style="display:none"
         src="https://www.facebook.com/tr?id={{ pixelId }}&ev=PageView&noscript=1"/>
</noscript>
{% endif %}
EOF

    # Create examples directory
    EXAMPLES_DIR="${SHOPWARE_ROOT}/partytown-examples"
    mkdir -p "$EXAMPLES_DIR"

    cat > "${EXAMPLES_DIR}/README.md" << 'EOF'
# Partytown Integration Examples

## Basic Usage

### 1. Include Partytown in Base Template

In your theme's `templates/base.html.twig`, add before closing `</head>`:

```twig
{% include '@Storefront/storefront/partytown/init.html.twig' %}
```

### 2. Load Third-Party Scripts

#### Google Analytics 4
```twig
{% include '@Storefront/storefront/partytown/google-analytics.html.twig' with {
    measurementId: 'G-XXXXXXXXXX'
} %}
```

#### Google Tag Manager
```twig
{% include '@Storefront/storefront/partytown/google-tag-manager.html.twig' with {
    containerId: 'GTM-XXXXXXX'
} %}
```

#### Facebook Pixel
```twig
{% include '@Storefront/storefront/partytown/facebook-pixel.html.twig' with {
    pixelId: 'XXXXXXXXXXXXXXX'
} %}
```

### 3. Custom Scripts

For custom third-party scripts, use `type="text/partytown"`:

```html
<script type="text/partytown" src="https://example.com/analytics.js"></script>

<script type="text/partytown">
    // Your third-party code here
    console.log('Running in Web Worker!');
</script>
```

## Performance Testing

Before Partytown:
```bash
npm run lighthouse -- https://your-shop.com
```

After Partytown:
```bash
npm run lighthouse -- https://your-shop.com
```

Compare Blocking Time and Total Blocking Time metrics.

## Troubleshooting

### Script not working in Partytown

1. Check browser console for errors
2. Enable debug mode in `partytown-config.js`:
   ```js
   debug: true,
   logCalls: true,
   ```

3. Add required methods to `forward` array if needed

### CORS Issues

Some scripts may require CORS configuration. Use Partytown's proxy:

```twig
<script type="text/partytown" data-partytown-resolve-url="true">
    // Your script
</script>
```

## Best Practices

1. **Only use for third-party scripts** - Don't use for critical first-party code
2. **Test thoroughly** - Not all scripts work in Web Workers
3. **Monitor performance** - Use Chrome DevTools to verify improvements
4. **Progressive enhancement** - Provide noscript fallbacks

## Resources

- [Partytown Documentation](https://partytown.builder.io/)
- [Shopware Performance Guide](https://developer.shopware.com/docs/guides/hosting/performance/)
EOF
}

###############################################################################
# Uninstallation
###############################################################################

uninstall_partytown() {
    print_header "Uninstalling Partytown"

    print_step "Removing Partytown files..."
    rm -rf "${PUBLIC_PATH}/~partytown"
    rm -f "${PUBLIC_PATH}/partytown-config.js"
    print_success "Files removed"
    echo ""

    print_step "Removing npm package..."
    cd "$SHOPWARE_ROOT"
    npm uninstall @builder.io/partytown
    print_success "Package removed"
    echo ""

    print_warning "Note: Template files and examples are kept. Remove manually if needed:"
    echo "  - templates/storefront/partytown/"
    echo "  - partytown-examples/"
    echo ""

    print_success "Partytown uninstalled"
}

###############################################################################
# Main
###############################################################################

main() {
    if [ "$1" = "--uninstall" ]; then
        uninstall_partytown
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Usage: $0 [--uninstall|--help]"
        echo ""
        echo "Install Partytown for Shopware 6 to run third-party scripts in Web Workers."
        echo ""
        echo "Options:"
        echo "  --uninstall    Remove Partytown installation"
        echo "  --help         Show this help message"
        echo ""
        exit 0
    else
        install_partytown
    fi
}

main "$@"
