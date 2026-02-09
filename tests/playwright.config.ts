import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false, // Run tests sequentially for predictable state
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'test-report', open: 'never' }]
  ],
  use: {
    baseURL: 'https://127.0.0.1', // Use IPv4 explicitly (WSL doesn't bind to IPv6)
    ignoreHTTPSErrors: true, // Self-signed cert
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'on', // Record video of all tests
  },
  timeout: 60000, // 60 seconds per test (LLM can be slow)
});
