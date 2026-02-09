import { test, expect } from '@playwright/test';

// ============================================================================
// UI Tests - Test all frontend functionality
// ============================================================================

test.describe('Navigation', () => {
  test('homepage loads and shows health status', async ({ page }) => {
    await page.goto('/');
    
    // Should show the app title
    await expect(page.locator('text=Khaos Server Dashboard')).toBeVisible();
    
    // Wait for health data to load - new tile-based dashboard shows status separately
    // Use .first() since "Redis" appears in multiple places (tile, nav, etc)
    await expect(page.locator('.text-h6:has-text("Redis")').first()).toBeVisible({ timeout: 10000 });
    await expect(page.locator('text=connected').first()).toBeVisible({ timeout: 10000 });
  });

  test('can navigate to Redis page', async ({ page }) => {
    await page.goto('/');
    await page.click('text=Redis');
    await expect(page).toHaveURL(/.*\/redis/);
    await expect(page.locator('text=Redis Cache Manager')).toBeVisible();
  });

  test('can navigate to Chat page', async ({ page }) => {
    await page.goto('/');
    await page.click('text=Chat');
    await expect(page).toHaveURL(/.*\/chat/);
    // New enhanced chat has Conversations sidebar - use card title
    await expect(page.locator('.v-card-title:has-text("Conversations")')).toBeVisible();
  });
});

test.describe('Redis UI', () => {
  test.beforeEach(async ({ request, page }) => {
    // Clear Redis before each test
    await request.delete('/api/redis');
    await page.goto('/redis');
  });

  test('shows empty state when no keys', async ({ page }) => {
    await expect(page.locator('text=No keys in cache')).toBeVisible();
  });

  test('can add a new key/value pair', async ({ page }) => {
    // Vuetify text fields - fill by finding the input within the component
    const keyInput = page.locator('input').first();
    const valueInput = page.locator('input').nth(1);
    
    await keyInput.fill('ui-test-key');
    await valueInput.fill('ui-test-value');
    
    // Click Add button
    await page.click('button:has-text("Add")');
    
    // Wait for the table to update
    await page.waitForTimeout(500); // Allow time for API call
    
    // Verify the key appears in the table
    await expect(page.locator('td:has-text("ui-test-key")')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('td:has-text("ui-test-value")')).toBeVisible();
  });

  test('can delete a key', async ({ page, request }) => {
    // Pre-populate a key via API
    await request.put('/api/redis/delete-ui-key', { data: { value: 'delete-me' } });
    
    // Refresh the page to see the key
    await page.reload();
    await expect(page.locator('td:has-text("delete-ui-key")')).toBeVisible();
    
    // Click delete button for this row
    const row = page.locator('tr', { has: page.locator('td:has-text("delete-ui-key")') });
    await row.locator('button[color="error"], button:has(.mdi-delete)').click();
    
    // Wait for deletion
    await page.waitForResponse(resp => resp.url().includes('/api/redis'));
    
    // Verify key is gone
    await expect(page.locator('td:has-text("delete-ui-key")')).not.toBeVisible();
  });

  test('can clear all keys', async ({ page, request }) => {
    // Pre-populate keys
    await request.put('/api/redis/clear-key-1', { data: { value: 'v1' } });
    await request.put('/api/redis/clear-key-2', { data: { value: 'v2' } });
    
    await page.reload();
    
    // Verify keys are shown
    await expect(page.locator('td:has-text("clear-key-1")')).toBeVisible();
    await expect(page.locator('td:has-text("clear-key-2")')).toBeVisible();
    
    // Handle the confirm dialog
    page.on('dialog', dialog => dialog.accept());
    
    // Click Clear All
    await page.click('button:has-text("Clear All")');
    
    // Wait for response
    await page.waitForResponse(resp => resp.url().includes('/api/redis'));
    
    // Verify empty state
    await expect(page.locator('text=No keys in cache')).toBeVisible();
  });

  test('displays multiple keys in table', async ({ page, request }) => {
    // Pre-populate multiple keys
    await request.put('/api/redis/multi-key-1', { data: { value: 'multi-value-1' } });
    await request.put('/api/redis/multi-key-2', { data: { value: 'multi-value-2' } });
    await request.put('/api/redis/multi-key-3', { data: { value: 'multi-value-3' } });
    
    await page.reload();
    
    // Verify all keys are displayed
    await expect(page.locator('td:has-text("multi-key-1")')).toBeVisible();
    await expect(page.locator('td:has-text("multi-key-2")')).toBeVisible();
    await expect(page.locator('td:has-text("multi-key-3")')).toBeVisible();
  });
});

test.describe('Chat UI', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/chat');
  });

  test('shows chat interface elements', async ({ page }) => {
    // Enhanced chat has sidebars for Conversations and Prompts - use card titles
    await expect(page.locator('.v-card-title:has-text("Conversations")')).toBeVisible();
    await expect(page.locator('.v-card-title:has-text("Saved Prompts")')).toBeVisible();
    await expect(page.locator('.v-card-title:has-text("Settings")')).toBeVisible();
    
    // Should have a textarea for message input (larger input area)
    await expect(page.locator('textarea').first()).toBeVisible();
  });

  test('can send a message and receive response', async ({ page }) => {
    // Wait for the chat page to fully load
    await page.waitForLoadState('networkidle');
    
    // Type a message in the main input textarea (label "Type your message...")
    const textarea = page.getByLabel('Type your message...');
    await textarea.click();
    await textarea.pressSequentially('Hi', { delay: 50 });
    
    // Wait for the Send button to become enabled
    const sendButton = page.locator('button:has(.mdi-send)');
    await expect(sendButton).toBeEnabled({ timeout: 5000 });
    
    // Click the Send button
    await sendButton.click();
    
    // Wait for assistant response - the chat uses message-container class
    // Wait for second message (first is user, second is assistant)
    await expect(page.locator('.message-container').nth(1)).toBeVisible({ timeout: 60000 });
    
    // Should now have at least 2 messages (user + assistant)
    const msgCount = await page.locator('.message-container').count();
    expect(msgCount).toBeGreaterThanOrEqual(2);
  });

  test('shows model name', async ({ page }) => {
    // The chat interface should show which model is being used
    await expect(page.locator('text=/qwen|llama|phi|mistral/i')).toBeVisible({ timeout: 10000 });
  });
});

test.describe('Home Dashboard', () => {
  test('shows service status cards', async ({ page }) => {
    await page.goto('/');
    
    // Wait for page to load and show health status
    await expect(page.locator('text=Khaos Server Dashboard')).toBeVisible();
    
    // New tile-based dashboard shows Redis and Ollama tiles - use specific selector
    await expect(page.locator('.text-h6:has-text("Redis")').first()).toBeVisible({ timeout: 10000 });
    await expect(page.locator('.text-h6:has-text("Ollama")')).toBeVisible();
    
    // Should show Quick Actions section
    await expect(page.locator('.v-card-title:has-text("Quick Actions")')).toBeVisible();
    
    // Should show System Info section
    await expect(page.locator('.v-card-title:has-text("System Info")')).toBeVisible();
  });
});
