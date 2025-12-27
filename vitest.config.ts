import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/JavaScript/**/*.test.{js,ts}'],
    environment: 'node',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'clover'],
      include: ['chapters/**/*.js'],
      exclude: ['chapters/**/scripts/*.sh'],
    },
    globals: true,
  },
});
