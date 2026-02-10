<script setup lang="ts">
import { ref, onMounted } from 'vue'

const API_BASE = ''

interface Drive {
  name: string
  label: string
  type: string
  format: string
  totalBytes: number
  freeBytes: number
  usedBytes: number
  totalFormatted: string
  freeFormatted: string
  usedFormatted: string
  percentUsed: number
}

interface Folder {
  path: string
  name: string
  sizeBytes: number
  sizeFormatted: string
  itemCount: number
}

const drives = ref<Drive[]>([])
const folders = ref<Folder[]>([])
const folderPath = ref('/')
const folderDepth = ref(2)
const folderLimit = ref(20)
const loading = ref(false)
const error = ref('')

async function loadDiskInfo() {
  loading.value = true
  error.value = ''
  
  try {
    const res = await fetch(`${API_BASE}/api/disk/info`)
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Failed to load disk info')
    drives.value = data.drives || []
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function loadFolderSizes() {
  loading.value = true
  error.value = ''
  
  try {
    const params = new URLSearchParams({
      path: folderPath.value,
      depth: folderDepth.value.toString(),
      limit: folderLimit.value.toString()
    })
    
    const res = await fetch(`${API_BASE}/api/disk/folders?${params}`)
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Failed to load folders')
    folders.value = data.folders || []
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function analyzePath(path: string) {
  folderPath.value = path
  loadFolderSizes()
}

function getUsageColor(percent: number): string {
  if (percent < 50) return '#28a745'
  if (percent < 80) return '#ffc107'
  return '#dc3545'
}

onMounted(() => {
  loadDiskInfo()
  loadFolderSizes()
})
</script>

<template>
  <div class="disk-view">
    <h1>💾 Disk Information</h1>
    <p class="subtitle">Monitor disk space and find large folders</p>
    
    <!-- Error Alert -->
    <div v-if="error" class="error-alert">
      {{ error }}
      <button @click="error = ''" class="close-btn">×</button>
    </div>
    
    <!-- Drives Section -->
    <div class="section">
      <div class="section-header">
        <h2>📀 Drives</h2>
        <button @click="loadDiskInfo" :disabled="loading" class="btn small">
          🔄 Refresh
        </button>
      </div>
      
      <div v-if="drives.length === 0 && !loading" class="empty">
        No drives found
      </div>
      
      <div class="drives-grid">
        <div v-for="drive in drives" :key="drive.name" class="drive-card">
          <div class="drive-header">
            <span class="drive-name">{{ drive.name }}</span>
            <span class="drive-label">{{ drive.label || drive.type }}</span>
          </div>
          
          <div class="usage-bar">
            <div 
              class="usage-fill" 
              :style="{ 
                width: drive.percentUsed + '%',
                background: getUsageColor(drive.percentUsed)
              }"
            ></div>
          </div>
          
          <div class="drive-stats">
            <div class="stat">
              <span class="stat-label">Used</span>
              <span class="stat-value">{{ drive.usedFormatted }}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Free</span>
              <span class="stat-value">{{ drive.freeFormatted }}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Total</span>
              <span class="stat-value">{{ drive.totalFormatted }}</span>
            </div>
          </div>
          
          <div class="drive-percent">{{ drive.percentUsed }}% used</div>
        </div>
      </div>
    </div>
    
    <!-- Folder Analysis Section -->
    <div class="section">
      <div class="section-header">
        <h2>📁 Folder Sizes</h2>
      </div>
      
      <div class="folder-controls">
        <div class="form-group">
          <label>Path</label>
          <input v-model="folderPath" placeholder="/" @keyup.enter="loadFolderSizes" />
        </div>
        <div class="form-group small">
          <label>Depth</label>
          <input v-model.number="folderDepth" type="number" min="1" max="10" />
        </div>
        <div class="form-group small">
          <label>Limit</label>
          <input v-model.number="folderLimit" type="number" min="5" max="100" />
        </div>
        <button @click="loadFolderSizes" :disabled="loading" class="btn primary">
          {{ loading ? 'Loading...' : '🔍 Analyze' }}
        </button>
      </div>
      
      <div class="quick-paths">
        <span>Quick:</span>
        <button @click="analyzePath('/')" class="path-btn">/</button>
        <button @click="analyzePath('/home')" class="path-btn">/home</button>
        <button @click="analyzePath('/var')" class="path-btn">/var</button>
        <button @click="analyzePath('/tmp')" class="path-btn">/tmp</button>
        <button @click="analyzePath('/home/khaos')" class="path-btn">/home/khaos</button>
      </div>
      
      <div v-if="folders.length === 0 && !loading" class="empty">
        No folders found at this path
      </div>
      
      <div class="folders-table" v-if="folders.length > 0">
        <div class="table-header">
          <span class="col-name">Folder</span>
          <span class="col-size">Size</span>
          <span class="col-items">Items</span>
          <span class="col-action">Action</span>
        </div>
        <div v-for="folder in folders" :key="folder.path" class="table-row">
          <span class="col-name">
            <span class="folder-icon">📁</span>
            {{ folder.name }}
          </span>
          <span class="col-size" :class="{ 'access-denied': folder.sizeBytes < 0 }">
            {{ folder.sizeFormatted }}
          </span>
          <span class="col-items">{{ folder.itemCount >= 0 ? folder.itemCount : '-' }}</span>
          <span class="col-action">
            <button @click="analyzePath(folder.path)" class="btn small" :disabled="folder.sizeBytes < 0">
              Drill
            </button>
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.disk-view {
  padding: 2rem;
  max-width: 1200px;
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

.section {
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  margin-bottom: 2rem;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.5rem;
}

.section-header h2 {
  margin: 0;
  font-size: 1.25rem;
}

.drives-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1.5rem;
}

.drive-card {
  background: #f8f9fa;
  border-radius: 12px;
  padding: 1.25rem;
}

.drive-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 1rem;
}

.drive-name {
  font-weight: 600;
  font-size: 1.1rem;
}

.drive-label {
  color: #666;
  font-size: 0.875rem;
}

.usage-bar {
  height: 12px;
  background: #e9ecef;
  border-radius: 6px;
  overflow: hidden;
  margin-bottom: 1rem;
}

.usage-fill {
  height: 100%;
  border-radius: 6px;
  transition: width 0.3s ease;
}

.drive-stats {
  display: flex;
  justify-content: space-between;
  margin-bottom: 0.75rem;
}

.stat {
  text-align: center;
}

.stat-label {
  display: block;
  font-size: 0.75rem;
  color: #888;
}

.stat-value {
  font-weight: 500;
  font-size: 0.9rem;
}

.drive-percent {
  text-align: center;
  font-size: 0.875rem;
  color: #666;
}

.folder-controls {
  display: flex;
  gap: 1rem;
  align-items: flex-end;
  margin-bottom: 1rem;
}

.form-group {
  flex: 1;
}

.form-group.small {
  flex: 0 0 80px;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-size: 0.875rem;
  color: #555;
}

input {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid #ddd;
  border-radius: 8px;
  font-size: 1rem;
  box-sizing: border-box;
}

.quick-paths {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 1.5rem;
  color: #666;
}

.path-btn {
  padding: 0.25rem 0.75rem;
  background: #e9ecef;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.875rem;
}

.path-btn:hover {
  background: #dee2e6;
}

.btn {
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 8px;
  font-size: 1rem;
  cursor: pointer;
  white-space: nowrap;
}

.btn.primary {
  background: linear-gradient(135deg, #4a90d9, #357abd);
  color: white;
}

.btn.small {
  padding: 0.5rem 1rem;
  font-size: 0.875rem;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.folders-table {
  border: 1px solid #e9ecef;
  border-radius: 8px;
  overflow: hidden;
}

.table-header, .table-row {
  display: grid;
  grid-template-columns: 1fr 120px 80px 80px;
  padding: 0.75rem 1rem;
  align-items: center;
}

.table-header {
  background: #f8f9fa;
  font-weight: 600;
  font-size: 0.875rem;
  color: #555;
}

.table-row {
  border-top: 1px solid #e9ecef;
}

.table-row:hover {
  background: #f8f9fa;
}

.col-name {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.folder-icon {
  font-size: 1.25rem;
}

.col-size {
  text-align: right;
  font-family: monospace;
}

.col-size.access-denied {
  color: #dc3545;
  font-size: 0.8rem;
}

.col-items {
  text-align: center;
  color: #666;
}

.col-action {
  text-align: center;
}

.error-alert {
  background: #f8d7da;
  color: #721c24;
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
  display: flex;
  justify-content: space-between;
}

.close-btn {
  background: none;
  border: none;
  font-size: 1.5rem;
  cursor: pointer;
}

.empty {
  color: #888;
  font-style: italic;
  padding: 2rem;
  text-align: center;
}
</style>
