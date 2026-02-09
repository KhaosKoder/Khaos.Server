import { test, expect, APIRequestContext } from '@playwright/test';

// ============================================================================
// API Tests - Test all backend endpoints directly
// ============================================================================

test.describe('API Health Check', () => {
  test('GET /api/health returns healthy status', async ({ request }) => {
    const response = await request.get('/api/health');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.status).toBe('healthy');
    expect(data.redis).toBe('connected');
    expect(data.ollama).toBe('connected');
    expect(data.timestamp).toBeDefined();
  });
});

test.describe('Redis API', () => {
  // Clean state before Redis tests
  test.beforeEach(async ({ request }) => {
    await request.delete('/api/redis');
  });

  test('PUT /api/redis/{key} - creates a new key', async ({ request }) => {
    const response = await request.put('/api/redis/test-key-1', {
      data: { value: 'test-value-1' }
    });
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.key).toBe('test-key-1');
    expect(data.value).toBe('test-value-1');
  });

  test('GET /api/redis/{key} - retrieves existing key', async ({ request }) => {
    // First create a key
    await request.put('/api/redis/get-test-key', {
      data: { value: 'get-test-value' }
    });

    // Then retrieve it
    const response = await request.get('/api/redis/get-test-key');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.key).toBe('get-test-key');
    expect(data.value).toBe('get-test-value');
  });

  test('GET /api/redis/{key} - returns 404 for missing key', async ({ request }) => {
    const response = await request.get('/api/redis/nonexistent-key-xyz');
    expect(response.status()).toBe(404);
  });

  test('DELETE /api/redis/{key} - removes a key', async ({ request }) => {
    // Create a key
    await request.put('/api/redis/delete-test-key', {
      data: { value: 'to-be-deleted' }
    });

    // Verify it exists
    let response = await request.get('/api/redis/delete-test-key');
    expect(response.ok()).toBeTruthy();

    // Delete it
    response = await request.delete('/api/redis/delete-test-key');
    expect(response.status()).toBe(204);

    // Verify it's gone
    response = await request.get('/api/redis/delete-test-key');
    expect(response.status()).toBe(404);
  });

  test('GET /api/redis - lists all keys', async ({ request }) => {
    // Create multiple keys
    await request.put('/api/redis/list-key-1', { data: { value: 'value-1' } });
    await request.put('/api/redis/list-key-2', { data: { value: 'value-2' } });
    await request.put('/api/redis/list-key-3', { data: { value: 'value-3' } });

    // Get all
    const response = await request.get('/api/redis');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data['list-key-1']).toBe('value-1');
    expect(data['list-key-2']).toBe('value-2');
    expect(data['list-key-3']).toBe('value-3');
  });

  test('POST /api/redis/bulk - bulk import', async ({ request }) => {
    const bulkData = {
      'bulk-key-1': 'bulk-value-1',
      'bulk-key-2': 'bulk-value-2',
      'bulk-key-3': 'bulk-value-3'
    };

    const response = await request.post('/api/redis/bulk', {
      data: bulkData
    });
    expect(response.ok()).toBeTruthy();
    
    const result = await response.json();
    expect(result.count).toBe(3);

    // Verify all keys exist
    const allKeys = await request.get('/api/redis');
    const data = await allKeys.json();
    expect(data['bulk-key-1']).toBe('bulk-value-1');
    expect(data['bulk-key-2']).toBe('bulk-value-2');
    expect(data['bulk-key-3']).toBe('bulk-value-3');
  });

  test('DELETE /api/redis - clears all keys', async ({ request }) => {
    // Create some keys
    await request.put('/api/redis/clear-key-1', { data: { value: 'v1' } });
    await request.put('/api/redis/clear-key-2', { data: { value: 'v2' } });

    // Clear all
    const response = await request.delete('/api/redis');
    expect(response.status()).toBe(204);

    // Verify empty
    const allKeys = await request.get('/api/redis');
    const data = await allKeys.json();
    expect(Object.keys(data).length).toBe(0);
  });

  test('PUT /api/redis/{key} - updates existing key', async ({ request }) => {
    // Create
    await request.put('/api/redis/update-key', { data: { value: 'original' } });
    
    // Update
    await request.put('/api/redis/update-key', { data: { value: 'updated' } });

    // Verify
    const response = await request.get('/api/redis/update-key');
    const data = await response.json();
    expect(data.value).toBe('updated');
  });
});

test.describe('Chat API', () => {
  test('GET /api/chat/models - lists available models', async ({ request }) => {
    const response = await request.get('/api/chat/models');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.models).toBeDefined();
    expect(Array.isArray(data.models)).toBeTruthy();
    expect(data.models.length).toBeGreaterThan(0);
    
    // Check model structure
    const model = data.models[0];
    expect(model.name).toBeDefined();
    expect(model.size).toBeDefined();
  });

  test('POST /api/chat - sends message and gets response', async ({ request }) => {
    const response = await request.post('/api/chat', {
      data: {
        message: 'What is 2+2? Reply with just the number.'
      }
    });
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.model).toBeDefined();
    expect(data.message).toBe('What is 2+2? Reply with just the number.');
    expect(data.response).toBeDefined();
    expect(data.response.length).toBeGreaterThan(0);
    // The answer should contain "4"
    expect(data.response).toMatch(/4/);
  });

  test('POST /api/chat - respects model parameter', async ({ request }) => {
    const response = await request.post('/api/chat', {
      data: {
        message: 'Say hello',
        model: 'qwen2.5:3b'
      }
    });
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.model).toBe('qwen2.5:3b');
  });
});
