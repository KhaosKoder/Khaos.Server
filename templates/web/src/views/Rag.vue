<script setup lang="ts">
import { ref, onMounted } from 'vue'

const API_BASE = ''

// Index form
const indexPath = ref('/home/khaos/app')
const indexName = ref('default')
const recursive = ref(true)
const maxFiles = ref(100)
const extensions = ref('.cs,.md,.py,.js,.ts,.json')

// Query form
const question = ref('')
const queryIndexName = ref('default')
const model = ref('llama3.2')

// State
const indexes = ref<any[]>([])
const indexResult = ref<any>(null)
const queryResult = ref<any>(null)
const loading = ref(false)
const error = ref('')

async function loadIndexes() {
  try {
    const res = await fetch(`${API_BASE}/api/rag/indexes`)
    const data = await res.json()
    indexes.value = data.indexes || []
  } catch (e) {
    console.error('Failed to load indexes:', e)
  }
}

async function indexFiles() {
  loading.value = true
  error.value = ''
  indexResult.value = null
  
  try {
    const res = await fetch(`${API_BASE}/api/rag/index`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        path: indexPath.value,
        indexName: indexName.value,
        recursive: recursive.value,
        maxFiles: maxFiles.value,
        extensions: extensions.value.split(',').map(e => e.trim())
      })
    })
    
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Index failed')
    
    indexResult.value = data
    await loadIndexes()
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function queryFiles() {
  if (!question.value.trim()) return
  
  loading.value = true
  error.value = ''
  queryResult.value = null
  
  try {
    const res = await fetch(`${API_BASE}/api/rag/query`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        question: question.value,
        indexName: queryIndexName.value,
        model: model.value
      })
    })
    
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Query failed')
    
    queryResult.value = data
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function deleteIndex(name: string) {
  if (!confirm(`Delete index "${name}"?`)) return
  
  try {
    await fetch(`${API_BASE}/api/rag/index/${name}`, { method: 'DELETE' })
    await loadIndexes()
  } catch (e: any) {
    error.value = e.message
  }
}

onMounted(loadIndexes)
</script>

<template>
  <div class="rag-view">
    <h1>🔍 RAG - File Q&A</h1>
    <p class="subtitle">Ask questions about your files using AI</p>
    
    <!-- Error Alert -->
    <div v-if="error" class="error-alert">
      {{ error }}
      <button @click="error = ''" class="close-btn">×</button>
    </div>
    
    <div class="rag-grid">
      <!-- Index Section -->
      <div class="card">
        <h2>📁 Index Files</h2>
        
        <div class="form-group">
          <label>Path to Index</label>
          <input v-model="indexPath" placeholder="/home/khaos/app" />
        </div>
        
        <div class="form-row">
          <div class="form-group">
            <label>Index Name</label>
            <input v-model="indexName" placeholder="default" />
          </div>
          <div class="form-group">
            <label>Max Files</label>
            <input v-model.number="maxFiles" type="number" min="1" max="500" />
          </div>
        </div>
        
        <div class="form-group">
          <label>Extensions (comma-separated)</label>
          <input v-model="extensions" placeholder=".cs,.md,.py" />
        </div>
        
        <div class="form-group checkbox">
          <input type="checkbox" id="recursive" v-model="recursive" />
          <label for="recursive">Include subdirectories</label>
        </div>
        
        <button @click="indexFiles" :disabled="loading || !indexPath" class="btn primary">
          {{ loading ? 'Indexing...' : '📥 Index Files' }}
        </button>
        
        <!-- Index Result -->
        <div v-if="indexResult" class="result-box success">
          <strong>✅ Indexed {{ indexResult.filesIndexed }} files</strong>
          <div class="file-list">
            <div v-for="file in indexResult.files?.slice(0, 10)" :key="file.path" class="file-item">
              {{ file.name }} <span class="size">({{ file.size }} chars)</span>
            </div>
            <div v-if="indexResult.files?.length > 10" class="more">
              ... and {{ indexResult.files.length - 10 }} more
            </div>
          </div>
        </div>
      </div>
      
      <!-- Query Section -->
      <div class="card">
        <h2>💬 Ask Questions</h2>
        
        <div class="form-row">
          <div class="form-group flex-2">
            <label>Index to Query</label>
            <select v-model="queryIndexName">
              <option value="default">default</option>
              <option v-for="idx in indexes" :key="idx.name" :value="idx.name">
                {{ idx.name }} ({{ idx.fileCount }} files)
              </option>
            </select>
          </div>
          <div class="form-group">
            <label>Model</label>
            <select v-model="model">
              <option value="llama3.2">llama3.2</option>
              <option value="llama3.2:1b">llama3.2:1b</option>
              <option value="codellama">codellama</option>
            </select>
          </div>
        </div>
        
        <div class="form-group">
          <label>Your Question</label>
          <textarea 
            v-model="question" 
            placeholder="What does this code do?" 
            rows="3"
            @keydown.ctrl.enter="queryFiles"
          ></textarea>
        </div>
        
        <button @click="queryFiles" :disabled="loading || !question.trim()" class="btn primary">
          {{ loading ? 'Thinking...' : '🔍 Ask' }}
        </button>
        
        <!-- Query Result -->
        <div v-if="queryResult" class="result-box">
          <div class="answer">
            <strong>Answer:</strong>
            <p>{{ queryResult.answer }}</p>
          </div>
          <div class="sources">
            <strong>Sources used:</strong>
            <span v-for="source in queryResult.sourcesUsed?.slice(0, 5)" :key="source.path" class="source-tag">
              {{ source.name }}
            </span>
          </div>
          <div class="meta">
            Model: {{ queryResult.model }} | Context: {{ queryResult.contextLength }} chars
          </div>
        </div>
      </div>
    </div>
    
    <!-- Indexes List -->
    <div class="card indexes-card">
      <h2>📚 Saved Indexes</h2>
      <div v-if="indexes.length === 0" class="empty">
        No indexes yet. Index some files to get started.
      </div>
      <div v-else class="indexes-list">
        <div v-for="idx in indexes" :key="idx.name" class="index-item">
          <span class="index-name">{{ idx.name }}</span>
          <span class="index-count">{{ idx.fileCount }} files</span>
          <button @click="deleteIndex(idx.name)" class="btn small danger">Delete</button>
        </div>
      </div>
      <button @click="loadIndexes" class="btn small">🔄 Refresh</button>
    </div>
  </div>
</template>

<style scoped>
.rag-view {
  padding: 2rem;
  max-width: 1400px;
  margin: 0 auto;
}

h1 {
  margin: 0;
  font-size: 2rem;
}

.subtitle {
  color: #666;
  margin-top: 0.5rem;
  margin-bottom: 2rem;
}

.rag-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem;
  margin-bottom: 2rem;
}

@media (max-width: 900px) {
  .rag-grid {
    grid-template-columns: 1fr;
  }
}

.card {
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.card h2 {
  margin: 0 0 1.5rem 0;
  font-size: 1.25rem;
  color: #333;
}

.form-group {
  margin-bottom: 1rem;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 500;
  color: #555;
}

.form-group.checkbox {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.form-group.checkbox label {
  margin-bottom: 0;
}

.form-row {
  display: flex;
  gap: 1rem;
}

.form-row .form-group {
  flex: 1;
}

.form-row .form-group.flex-2 {
  flex: 2;
}

input, select, textarea {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid #ddd;
  border-radius: 8px;
  font-size: 1rem;
  box-sizing: border-box;
}

input:focus, select:focus, textarea:focus {
  outline: none;
  border-color: #4a90d9;
  box-shadow: 0 0 0 3px rgba(74, 144, 217, 0.1);
}

textarea {
  resize: vertical;
  min-height: 80px;
}

.btn {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 8px;
  font-size: 1rem;
  cursor: pointer;
  transition: all 0.2s;
}

.btn.primary {
  background: linear-gradient(135deg, #4a90d9, #357abd);
  color: white;
}

.btn.primary:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(74, 144, 217, 0.3);
}

.btn.primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn.small {
  padding: 0.5rem 1rem;
  font-size: 0.875rem;
}

.btn.danger {
  background: #dc3545;
  color: white;
}

.result-box {
  margin-top: 1.5rem;
  padding: 1rem;
  background: #f8f9fa;
  border-radius: 8px;
  border-left: 4px solid #4a90d9;
}

.result-box.success {
  border-left-color: #28a745;
}

.file-list {
  margin-top: 0.75rem;
  font-size: 0.875rem;
}

.file-item {
  padding: 0.25rem 0;
  color: #555;
}

.file-item .size {
  color: #999;
}

.more {
  color: #888;
  font-style: italic;
  margin-top: 0.5rem;
}

.answer {
  margin-bottom: 1rem;
}

.answer p {
  margin: 0.5rem 0;
  white-space: pre-wrap;
  line-height: 1.6;
}

.sources {
  margin-bottom: 0.75rem;
}

.source-tag {
  display: inline-block;
  background: #e9ecef;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  font-size: 0.8rem;
  margin: 0.25rem;
}

.meta {
  font-size: 0.8rem;
  color: #888;
}

.error-alert {
  background: #f8d7da;
  color: #721c24;
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.close-btn {
  background: none;
  border: none;
  font-size: 1.5rem;
  cursor: pointer;
  color: #721c24;
}

.indexes-card {
  margin-top: 1rem;
}

.indexes-list {
  margin-bottom: 1rem;
}

.index-item {
  display: flex;
  align-items: center;
  padding: 0.75rem;
  background: #f8f9fa;
  border-radius: 8px;
  margin-bottom: 0.5rem;
}

.index-name {
  font-weight: 500;
  flex: 1;
}

.index-count {
  color: #666;
  margin-right: 1rem;
}

.empty {
  color: #888;
  font-style: italic;
  padding: 1rem 0;
}
</style>
