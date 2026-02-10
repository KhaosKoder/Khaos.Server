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
    expect(data.postgres).toBe('connected');
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

// ============================================================================
// Persistent Data API Tests (PostgreSQL + Redis Cache)
// ============================================================================
test.describe('Data API (Persistent)', () => {
  // Clean state before Data tests
  test.beforeEach(async ({ request }) => {
    await request.delete('/api/data');
  });

  test('POST /api/data/{key} - creates a new persistent key', async ({ request }) => {
    const response = await request.post('/api/data/test-persistent-key', {
      data: { value: 'test-persistent-value' }
    });
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.key).toBe('test-persistent-key');
    expect(data.value).toBe('test-persistent-value');
    expect(data.persisted).toBe(true);
    expect(data.createdAt).toBeDefined();
    expect(data.updatedAt).toBeDefined();
  });

  test('GET /api/data/{key} - retrieves from cache on second read', async ({ request }) => {
    // Create a key
    await request.post('/api/data/cache-test-key', {
      data: { value: 'cache-test-value' }
    });

    // First read should be from database (just created, cached)
    let response = await request.get('/api/data/cache-test-key');
    expect(response.ok()).toBeTruthy();
    let data = await response.json();
    expect(data.value).toBe('cache-test-value');
    // After POST, cache is populated so source should be cache
    expect(data.source).toBe('cache');

    // Second read should definitely be from cache
    response = await request.get('/api/data/cache-test-key');
    data = await response.json();
    expect(data.source).toBe('cache');
  });

  test('GET /api/data/{key} - returns 404 for missing key', async ({ request }) => {
    const response = await request.get('/api/data/nonexistent-key-xyz');
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.error).toContain('not found');
  });

  test('PUT /api/data/{key} - updates existing key', async ({ request }) => {
    // Create
    await request.post('/api/data/update-test-key', {
      data: { value: 'original-value' }
    });

    // Update
    const response = await request.put('/api/data/update-test-key', {
      data: { value: 'updated-value' }
    });
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.value).toBe('updated-value');
    expect(data.persisted).toBe(true);
  });

  test('PUT /api/data/{key} - returns 404 for missing key', async ({ request }) => {
    const response = await request.put('/api/data/nonexistent-key', {
      data: { value: 'some-value' }
    });
    expect(response.status()).toBe(404);
  });

  test('DELETE /api/data/{key} - removes key from both cache and database', async ({ request }) => {
    // Create
    await request.post('/api/data/delete-test-key', {
      data: { value: 'to-be-deleted' }
    });

    // Verify it exists
    let response = await request.get('/api/data/delete-test-key');
    expect(response.ok()).toBeTruthy();

    // Delete it
    response = await request.delete('/api/data/delete-test-key');
    expect(response.ok()).toBeTruthy();
    const deleteData = await response.json();
    expect(deleteData.deleted).toBe(true);

    // Verify it's gone
    response = await request.get('/api/data/delete-test-key');
    expect(response.status()).toBe(404);
  });

  test('GET /api/data - lists all persistent keys', async ({ request }) => {
    // Create multiple keys
    await request.post('/api/data/list-key-1', { data: { value: 'value-1' } });
    await request.post('/api/data/list-key-2', { data: { value: 'value-2' } });
    await request.post('/api/data/list-key-3', { data: { value: 'value-3' } });

    // Get all
    const response = await request.get('/api/data');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.count).toBe(3);
    expect(data.items.length).toBe(3);
    
    // Check structure
    const keys = data.items.map((i: any) => i.key);
    expect(keys).toContain('list-key-1');
    expect(keys).toContain('list-key-2');
    expect(keys).toContain('list-key-3');
  });

  test('DELETE /api/data - clears all persistent keys', async ({ request }) => {
    // Create some keys
    await request.post('/api/data/clear-key-1', { data: { value: 'v1' } });
    await request.post('/api/data/clear-key-2', { data: { value: 'v2' } });

    // Clear all
    const response = await request.delete('/api/data');
    expect(response.ok()).toBeTruthy();
    const clearData = await response.json();
    expect(clearData.deleted).toBe(2);

    // Verify empty
    const allKeys = await request.get('/api/data');
    const data = await allKeys.json();
    expect(data.count).toBe(0);
    expect(data.items.length).toBe(0);
  });

  test('Data persists after clearing Redis cache', async ({ request }) => {
    // Create a persistent key
    await request.post('/api/data/persistence-test', {
      data: { value: 'this-should-survive' }
    });

    // Clear Redis (the cache)
    await request.delete('/api/redis');

    // Data should still be retrievable from PostgreSQL
    const response = await request.get('/api/data/persistence-test');
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.value).toBe('this-should-survive');
    expect(data.source).toBe('database'); // Cache was cleared, so comes from DB
  });

  test('JSON values are stored correctly', async ({ request }) => {
    const jsonValue = { nested: { data: [1, 2, 3] }, active: true };
    
    await request.post('/api/data/json-test', {
      data: { value: jsonValue }
    });

    const response = await request.get('/api/data/json-test');
    const data = await response.json();
    
    expect(data.value).toEqual(jsonValue);
  });

  test('POST /api/data/bulk - imports multiple keys at once', async ({ request }) => {
    const bulkData = {
      'bulk-data-1': 'value-1',
      'bulk-data-2': { nested: true },
      'bulk-data-3': [1, 2, 3]
    };
    
    const response = await request.post('/api/data/bulk', {
      data: bulkData
    });
    expect(response.ok()).toBeTruthy();
    
    const result = await response.json();
    expect(result.count).toBe(3);
    expect(result.persisted).toBe(true);

    // Verify all keys exist
    const allKeys = await request.get('/api/data');
    const data = await allKeys.json();
    expect(data.count).toBe(3);
    
    const keys = data.items.map((i: any) => i.key);
    expect(keys).toContain('bulk-data-1');
    expect(keys).toContain('bulk-data-2');
    expect(keys).toContain('bulk-data-3');
  });
});

// ============================================================================
// Filesystem API Tests
// ============================================================================
test.describe('Filesystem API', () => {
  const testPath = '/opt/khaos';  // Known path that should exist

  test('GET /api/filesystem/list - lists files in directory', async ({ request }) => {
    const response = await request.get(`/api/filesystem/list?path=${encodeURIComponent(testPath)}`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.path).toBe(testPath);
    expect(data.count).toBeGreaterThanOrEqual(0);
    expect(Array.isArray(data.entries)).toBeTruthy();
  });

  test('GET /api/filesystem/list - returns entries with metadata', async ({ request }) => {
    const response = await request.get(`/api/filesystem/list?path=${encodeURIComponent(testPath)}`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    if (data.entries.length > 0) {
      const entry = data.entries[0];
      expect(entry.name).toBeDefined();
      expect(entry.path).toBeDefined();
      expect(entry.type).toMatch(/^(file|directory)$/);
      expect(entry.createdAt).toBeDefined();
      expect(entry.modifiedAt).toBeDefined();
    }
  });

  test('GET /api/filesystem/list - supports recursive option', async ({ request }) => {
    const response = await request.get(`/api/filesystem/list?path=${encodeURIComponent(testPath)}&recursive=true`);
    expect(response.ok()).toBeTruthy();
    
    const data = await response.json();
    expect(data.recursive).toBe(true);
  });

  test('GET /api/filesystem/list - returns 404 for missing path', async ({ request }) => {
    const response = await request.get('/api/filesystem/list?path=/nonexistent/path/xyz');
    expect(response.status()).toBe(404);
  });

  test('GET /api/filesystem/list - returns 400 for missing path parameter', async ({ request }) => {
    const response = await request.get('/api/filesystem/list');
    expect(response.status()).toBe(400);
  });

  test('GET /api/filesystem/info - gets file metadata', async ({ request }) => {
    // First get a file from the directory listing
    const listResponse = await request.get(`/api/filesystem/list?path=${encodeURIComponent(testPath)}`);
    const listData = await listResponse.json();
    
    if (listData.entries.length > 0) {
      const entry = listData.entries[0];
      const response = await request.get(`/api/filesystem/info?path=${encodeURIComponent(entry.path)}`);
      expect(response.ok()).toBeTruthy();
      
      const data = await response.json();
      expect(data.name).toBeDefined();
      expect(data.path).toBe(entry.path);
      expect(data.type).toMatch(/^(file|directory)$/);
      expect(data.exists).toBe(true);
      expect(data.createdAt).toBeDefined();
      expect(data.modifiedAt).toBeDefined();
    }
  });

  test('GET /api/filesystem/info - returns 404 for missing path', async ({ request }) => {
    const response = await request.get('/api/filesystem/info?path=/nonexistent/file.txt');
    expect(response.status()).toBe(404);
    
    const data = await response.json();
    expect(data.exists).toBe(false);
  });

  test('GET /api/filesystem/read - reads text file content', async ({ request }) => {
    // Try to read a known config file
    const configPath = '/etc/khaos/khaos.conf';
    const response = await request.get(`/api/filesystem/read?path=${encodeURIComponent(configPath)}`);
    
    if (response.ok()) {
      const data = await response.json();
      expect(data.path).toBe(configPath);
      expect(data.content).toBeDefined();
      expect(data.isBinary).toBe(false);
      expect(data.lineCount).toBeGreaterThan(0);
    }
  });

  test('GET /api/filesystem/read - returns 404 for missing file', async ({ request }) => {
    const response = await request.get('/api/filesystem/read?path=/nonexistent/file.txt');
    expect(response.status()).toBe(404);
  });

  test('POST /api/filesystem/copy - copies a file', async ({ request }) => {
    // Create a test file first by reading an existing one and verify copy works
    const testSource = '/etc/hostname';
    const testDest = '/tmp/hostname-copy-test';
    
    // Clean up any existing test file
    await request.delete(`/api/filesystem/info?path=${encodeURIComponent(testDest)}`);
    
    const response = await request.post('/api/filesystem/copy', {
      data: {
        source: testSource,
        destination: testDest,
        overwrite: true
      }
    });
    
    if (response.ok()) {
      const data = await response.json();
      expect(data.source).toBe(testSource);
      expect(data.destination).toBe(testDest);
      expect(data.copied).toBe(true);
      
      // Verify the copy exists
      const verifyResponse = await request.get(`/api/filesystem/info?path=${encodeURIComponent(testDest)}`);
      expect(verifyResponse.ok()).toBeTruthy();
    }
  });

  test('POST /api/filesystem/copy - returns 404 for missing source', async ({ request }) => {
    const response = await request.post('/api/filesystem/copy', {
      data: {
        source: '/nonexistent/source.txt',
        destination: '/tmp/dest.txt'
      }
    });
    expect(response.status()).toBe(404);
  });

  test('POST /api/filesystem/copy - returns 400 for missing parameters', async ({ request }) => {
    const response = await request.post('/api/filesystem/copy', {
      data: {}
    });
    expect(response.status()).toBe(400);
  });
});
