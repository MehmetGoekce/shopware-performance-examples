/**
 * Swipe Gesture Detection for Mobile
 *
 * Provides easy-to-use swipe detection for:
 * - Product galleries
 * - Category carousels
 * - Mobile navigation drawers
 * - Delete/action swipes on lists
 *
 * Usage:
 *   const swipe = new SwipeGesture(element, {
 *       onSwipeLeft: () => gallery.next(),
 *       onSwipeRight: () => gallery.prev(),
 *       threshold: 50
 *   });
 */

export class SwipeGesture {
    /**
     * @param {HTMLElement} element - Element to attach swipe detection to
     * @param {Object} options - Configuration options
     */
    constructor(element, options = {}) {
        this.element = element;
        this.options = {
            threshold: options.threshold || 50,
            restraint: options.restraint || 100,
            allowedTime: options.allowedTime || 300,
            onSwipeLeft: options.onSwipeLeft || null,
            onSwipeRight: options.onSwipeRight || null,
            onSwipeUp: options.onSwipeUp || null,
            onSwipeDown: options.onSwipeDown || null,
            onSwipeStart: options.onSwipeStart || null,
            onSwipeMove: options.onSwipeMove || null,
            onSwipeEnd: options.onSwipeEnd || null,
        };

        this.touchStartX = 0;
        this.touchStartY = 0;
        this.touchEndX = 0;
        this.touchEndY = 0;
        this.startTime = 0;
        this.isSwiping = false;

        this.bindEvents();
    }

    bindEvents() {
        this.element.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: true });
        this.element.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: true });
        this.element.addEventListener('touchend', this.handleTouchEnd.bind(this), { passive: true });
    }

    handleTouchStart(event) {
        const touch = event.touches[0];
        this.touchStartX = touch.clientX;
        this.touchStartY = touch.clientY;
        this.startTime = Date.now();
        this.isSwiping = true;

        if (this.options.onSwipeStart) {
            this.options.onSwipeStart({
                x: this.touchStartX,
                y: this.touchStartY,
            });
        }
    }

    handleTouchMove(event) {
        if (!this.isSwiping) return;

        const touch = event.touches[0];
        this.touchEndX = touch.clientX;
        this.touchEndY = touch.clientY;

        const deltaX = this.touchEndX - this.touchStartX;
        const deltaY = this.touchEndY - this.touchStartY;

        if (this.options.onSwipeMove) {
            this.options.onSwipeMove({
                deltaX,
                deltaY,
                startX: this.touchStartX,
                startY: this.touchStartY,
                currentX: this.touchEndX,
                currentY: this.touchEndY,
            });
        }
    }

    handleTouchEnd(event) {
        if (!this.isSwiping) return;
        this.isSwiping = false;

        const touch = event.changedTouches[0];
        this.touchEndX = touch.clientX;
        this.touchEndY = touch.clientY;

        const elapsedTime = Date.now() - this.startTime;
        const deltaX = this.touchEndX - this.touchStartX;
        const deltaY = this.touchEndY - this.touchStartY;

        if (this.options.onSwipeEnd) {
            this.options.onSwipeEnd({
                deltaX,
                deltaY,
                elapsedTime,
            });
        }

        // Check if swipe meets criteria
        if (elapsedTime <= this.options.allowedTime) {
            this.detectSwipeDirection(deltaX, deltaY);
        }
    }

    detectSwipeDirection(deltaX, deltaY) {
        const absX = Math.abs(deltaX);
        const absY = Math.abs(deltaY);

        // Horizontal swipe
        if (absX >= this.options.threshold && absY <= this.options.restraint) {
            if (deltaX > 0) {
                this.options.onSwipeRight?.();
            } else {
                this.options.onSwipeLeft?.();
            }
        }

        // Vertical swipe
        if (absY >= this.options.threshold && absX <= this.options.restraint) {
            if (deltaY > 0) {
                this.options.onSwipeDown?.();
            } else {
                this.options.onSwipeUp?.();
            }
        }
    }

    destroy() {
        this.element.removeEventListener('touchstart', this.handleTouchStart);
        this.element.removeEventListener('touchmove', this.handleTouchMove);
        this.element.removeEventListener('touchend', this.handleTouchEnd);
    }
}

/**
 * Product Gallery with Swipe
 *
 * Usage:
 *   const gallery = new ProductGallery(element, images);
 */
export class ProductGallery {
    constructor(element, images, options = {}) {
        this.element = element;
        this.images = images;
        this.currentIndex = 0;
        this.options = {
            loop: options.loop ?? true,
            autoplay: options.autoplay ?? false,
            autoplayInterval: options.autoplayInterval ?? 5000,
        };

        this.init();
    }

    init() {
        this.render();
        this.bindSwipe();

        if (this.options.autoplay) {
            this.startAutoplay();
        }
    }

    render() {
        this.element.innerHTML = `
            <div class="gallery-track" style="transform: translateX(0)">
                ${this.images.map((img, i) => `
                    <div class="gallery-slide ${i === 0 ? 'active' : ''}">
                        <img src="${img.src}" alt="${img.alt || ''}" loading="${i === 0 ? 'eager' : 'lazy'}">
                    </div>
                `).join('')}
            </div>
            <div class="gallery-dots">
                ${this.images.map((_, i) => `
                    <button class="gallery-dot ${i === 0 ? 'active' : ''}" data-index="${i}"></button>
                `).join('')}
            </div>
        `;

        this.track = this.element.querySelector('.gallery-track');
        this.dots = this.element.querySelectorAll('.gallery-dot');

        // Dot click handlers
        this.dots.forEach((dot) => {
            dot.addEventListener('click', () => {
                this.goTo(parseInt(dot.dataset.index, 10));
            });
        });
    }

    bindSwipe() {
        this.swipe = new SwipeGesture(this.element, {
            onSwipeLeft: () => this.next(),
            onSwipeRight: () => this.prev(),
            onSwipeMove: ({ deltaX }) => {
                // Live preview during swipe
                const offset = -this.currentIndex * 100 + (deltaX / this.element.offsetWidth) * 100;
                this.track.style.transform = `translateX(${offset}%)`;
                this.track.style.transition = 'none';
            },
            onSwipeEnd: () => {
                this.track.style.transition = 'transform 0.3s ease';
            },
        });
    }

    goTo(index) {
        if (index < 0) {
            index = this.options.loop ? this.images.length - 1 : 0;
        } else if (index >= this.images.length) {
            index = this.options.loop ? 0 : this.images.length - 1;
        }

        this.currentIndex = index;
        this.track.style.transform = `translateX(${-index * 100}%)`;

        // Update dots
        this.dots.forEach((dot, i) => {
            dot.classList.toggle('active', i === index);
        });
    }

    next() {
        this.goTo(this.currentIndex + 1);
    }

    prev() {
        this.goTo(this.currentIndex - 1);
    }

    startAutoplay() {
        this.autoplayTimer = setInterval(() => {
            this.next();
        }, this.options.autoplayInterval);
    }

    stopAutoplay() {
        if (this.autoplayTimer) {
            clearInterval(this.autoplayTimer);
        }
    }

    destroy() {
        this.swipe.destroy();
        this.stopAutoplay();
    }
}

/**
 * Swipe-to-Delete List Item
 *
 * Usage:
 *   const swipeDelete = new SwipeToDelete(listItem, {
 *       onDelete: () => deleteItem(id)
 *   });
 */
export class SwipeToDelete {
    constructor(element, options = {}) {
        this.element = element;
        this.options = {
            threshold: options.threshold || 0.4, // 40% of width
            onDelete: options.onDelete || null,
            deleteText: options.deleteText || 'Löschen',
        };

        this.init();
    }

    init() {
        // Wrap content
        this.wrapper = document.createElement('div');
        this.wrapper.className = 'swipe-content';
        this.wrapper.innerHTML = this.element.innerHTML;
        this.element.innerHTML = '';

        // Add delete button
        this.deleteBtn = document.createElement('div');
        this.deleteBtn.className = 'swipe-delete';
        this.deleteBtn.textContent = this.options.deleteText;

        this.element.appendChild(this.wrapper);
        this.element.appendChild(this.deleteBtn);
        this.element.classList.add('swipe-item');

        this.bindSwipe();
    }

    bindSwipe() {
        let startX = 0;
        let currentX = 0;

        this.swipe = new SwipeGesture(this.wrapper, {
            onSwipeStart: ({ x }) => {
                startX = x;
            },
            onSwipeMove: ({ deltaX }) => {
                if (deltaX > 0) return; // Only allow left swipe

                currentX = Math.max(deltaX, -this.deleteBtn.offsetWidth);
                this.wrapper.style.transform = `translateX(${currentX}px)`;
            },
            onSwipeEnd: ({ deltaX }) => {
                const threshold = this.element.offsetWidth * this.options.threshold;

                if (Math.abs(deltaX) > threshold) {
                    // Delete
                    this.wrapper.style.transform = `translateX(-100%)`;
                    this.element.style.height = '0';
                    this.element.style.opacity = '0';

                    setTimeout(() => {
                        this.options.onDelete?.();
                    }, 300);
                } else {
                    // Reset
                    this.wrapper.style.transform = 'translateX(0)';
                }
            },
        });
    }

    destroy() {
        this.swipe.destroy();
    }
}

// CSS for swipe components (inject or include separately)
const swipeStyles = `
.gallery-track {
    display: flex;
    transition: transform 0.3s ease;
}

.gallery-slide {
    flex: 0 0 100%;
    min-width: 100%;
}

.gallery-slide img {
    width: 100%;
    height: auto;
    object-fit: cover;
}

.gallery-dots {
    display: flex;
    justify-content: center;
    gap: 8px;
    padding: 12px;
}

.gallery-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    border: none;
    background: #ccc;
    cursor: pointer;
    transition: background 0.2s;
}

.gallery-dot.active {
    background: #333;
}

.swipe-item {
    position: relative;
    overflow: hidden;
    transition: height 0.3s, opacity 0.3s;
}

.swipe-content {
    transition: transform 0.3s ease;
    background: white;
    position: relative;
    z-index: 1;
}

.swipe-delete {
    position: absolute;
    right: 0;
    top: 0;
    bottom: 0;
    width: 80px;
    background: #ef4444;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
}
`;

// Inject styles
if (typeof document !== 'undefined') {
    const styleEl = document.createElement('style');
    styleEl.textContent = swipeStyles;
    document.head.appendChild(styleEl);
}
