<template>
  <div>
    <h1 class="text-h4 mb-2">Filesystem Browser</h1>
    <p class="text-grey mb-4">Browse and manage files on the server</p>

    <!-- Path input and controls -->
    <v-card class="mb-4">
      <v-card-title>Browse Directory</v-card-title>
      <v-card-text>
        <v-row align="center">
          <v-col cols="8">
            <v-text-field
              v-model="currentPath"
              label="Path"
              density="compact"
              prepend-icon="mdi-folder"
              @keyup.enter="listFiles"
              clearable
            ></v-text-field>
          </v-col>
          <v-col cols="2">
            <v-checkbox v-model="recursive" label="Recursive" density="compact" hide-details></v-checkbox>
          </v-col>
          <v-col cols="2">
            <v-btn color="primary" @click="listFiles" :loading="loading">
              <v-icon left>mdi-folder-search</v-icon> Browse
            </v-btn>
          </v-col>
        </v-row>
        
        <!-- Quick paths -->
        <div class="mt-2">
          <span class="text-caption text-grey mr-2">Quick paths:</span>
          <v-chip size="small" class="mr-1" @click="goToPath('/opt/khaos')">Apps</v-chip>
          <v-chip size="small" class="mr-1" @click="goToPath('/var/log/khaos')">Logs</v-chip>
          <v-chip size="small" class="mr-1" @click="goToPath('/home/khaos')">Home</v-chip>
          <v-chip size="small" class="mr-1" @click="goToPath('/tmp')">Temp</v-chip>
        </div>
      </v-card-text>
    </v-card>

    <!-- Error display -->
    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" closable @click:close="error = ''">
      {{ error }}
    </v-alert>

    <!-- File info panel (when a file is selected) -->
    <v-card v-if="selectedFile" class="mb-4">
      <v-card-title>
        <v-icon class="mr-2">{{ selectedFile.type === 'directory' ? 'mdi-folder' : 'mdi-file' }}</v-icon>
        {{ selectedFile.name }}
        <v-spacer></v-spacer>
        <v-btn icon size="small" @click="selectedFile = null">
          <v-icon>mdi-close</v-icon>
        </v-btn>
      </v-card-title>
      <v-card-text>
        <v-row>
          <v-col cols="6">
            <p><strong>Path:</strong> <code>{{ selectedFile.path }}</code></p>
            <p><strong>Type:</strong> {{ selectedFile.type }}</p>
            <p v-if="selectedFile.size !== null"><strong>Size:</strong> {{ formatSize(selectedFile.size) }}</p>
          </v-col>
          <v-col cols="6">
            <p><strong>Created:</strong> {{ formatDate(selectedFile.createdAt) }}</p>
            <p><strong>Modified:</strong> {{ formatDate(selectedFile.modifiedAt) }}</p>
          </v-col>
        </v-row>
        
        <v-divider class="my-3"></v-divider>
        
        <v-btn 
          v-if="selectedFile.type === 'file'" 
          color="primary" 
          size="small" 
          class="mr-2"
          @click="readFile(selectedFile.path)"
          :loading="readingFile"
        >
          <v-icon left>mdi-file-eye</v-icon> View Content
        </v-btn>
        <v-btn 
          v-if="selectedFile.type === 'directory'" 
          color="primary" 
          size="small" 
          class="mr-2"
          @click="goToPath(selectedFile.path)"
        >
          <v-icon left>mdi-folder-open</v-icon> Open Directory
        </v-btn>
        <v-btn 
          v-if="selectedFile.type === 'file'" 
          color="secondary" 
          size="small"
          @click="showCopyDialog = true"
        >
          <v-icon left>mdi-content-copy</v-icon> Copy File
        </v-btn>
      </v-card-text>
    </v-card>

    <!-- File content viewer -->
    <v-card v-if="fileContent" class="mb-4">
      <v-card-title>
        <v-icon class="mr-2">mdi-file-document</v-icon>
        {{ fileContent.name }}
        <v-chip size="x-small" class="ml-2">{{ fileContent.lineCount }} lines</v-chip>
        <v-spacer></v-spacer>
        <v-btn icon size="small" @click="fileContent = null">
          <v-icon>mdi-close</v-icon>
        </v-btn>
      </v-card-title>
      <v-card-text>
        <pre class="file-content">{{ fileContent.content }}</pre>
      </v-card-text>
    </v-card>

    <!-- File listing -->
    <v-card>
      <v-card-title>
        <v-icon class="mr-2">mdi-folder-open</v-icon>
        {{ currentPath || 'Select a path' }}
        <v-chip v-if="entries.length > 0" size="small" class="ml-2">{{ entries.length }} items</v-chip>
      </v-card-title>
      <v-card-text>
        <!-- Parent directory link -->
        <v-list v-if="currentPath && currentPath !== '/'" density="compact">
          <v-list-item @click="goToParent" prepend-icon="mdi-arrow-up">
            <v-list-item-title>..</v-list-item-title>
            <v-list-item-subtitle>Parent directory</v-list-item-subtitle>
          </v-list-item>
        </v-list>

        <v-table v-if="entries.length > 0" density="compact">
          <thead>
            <tr>
              <th>Name</th>
              <th>Type</th>
              <th>Size</th>
              <th>Modified</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr 
              v-for="entry in sortedEntries" 
              :key="entry.path"
              @click="selectEntry(entry)"
              :class="{ 'selected-row': selectedFile?.path === entry.path }"
              style="cursor: pointer;"
            >
              <td>
                <v-icon size="small" class="mr-1">
                  {{ entry.type === 'directory' ? 'mdi-folder' : getFileIcon(entry.name) }}
                </v-icon>
                {{ entry.name }}
              </td>
              <td>
                <v-chip size="x-small" :color="entry.type === 'directory' ? 'blue' : 'grey'">
                  {{ entry.type }}
                </v-chip>
              </td>
              <td>{{ entry.size !== null ? formatSize(entry.size) : '-' }}</td>
              <td class="text-caption">{{ formatDate(entry.modifiedAt) }}</td>
              <td>
                <v-btn 
                  v-if="entry.type === 'directory'" 
                  icon 
                  size="x-small" 
                  @click.stop="goToPath(entry.path)"
                >
                  <v-icon>mdi-folder-open</v-icon>
                </v-btn>
                <v-btn 
                  v-if="entry.type === 'file'" 
                  icon 
                  size="x-small" 
                  @click.stop="readFile(entry.path)"
                >
                  <v-icon>mdi-eye</v-icon>
                </v-btn>
              </td>
            </tr>
          </tbody>
        </v-table>
        <p v-else-if="!loading" class="text-grey">
          {{ currentPath ? 'No files found' : 'Enter a path and click Browse' }}
        </p>
        <v-progress-linear v-if="loading" indeterminate></v-progress-linear>
      </v-card-text>
    </v-card>

    <!-- Copy file dialog -->
    <v-dialog v-model="showCopyDialog" max-width="500">
      <v-card>
        <v-card-title>Copy File</v-card-title>
        <v-card-text>
          <p class="mb-3"><strong>Source:</strong> <code>{{ selectedFile?.path }}</code></p>
          <v-text-field
            v-model="copyDestination"
            label="Destination Path"
            density="compact"
            prepend-icon="mdi-file-move"
          ></v-text-field>
          <v-checkbox v-model="copyOverwrite" label="Overwrite if exists" density="compact"></v-checkbox>
        </v-card-text>
        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn @click="showCopyDialog = false">Cancel</v-btn>
          <v-btn color="primary" @click="copyFile" :loading="copying">Copy</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'

interface FileEntry {
  name: string
  path: string
  type: 'file' | 'directory'
  createdAt: string
  modifiedAt: string
  size: number | null
}

interface FileContent {
  name: string
  path: string
  content: string
  lineCount: number
  size: number
  isBinary: boolean
}

const currentPath = ref('/opt/khaos')
const recursive = ref(false)
const entries = ref<FileEntry[]>([])
const loading = ref(false)
const error = ref('')
const selectedFile = ref<FileEntry | null>(null)
const fileContent = ref<FileContent | null>(null)
const readingFile = ref(false)
const showCopyDialog = ref(false)
const copyDestination = ref('')
const copyOverwrite = ref(false)
const copying = ref(false)

const sortedEntries = computed(() => {
  return [...entries.value].sort((a, b) => {
    // Directories first
    if (a.type !== b.type) {
      return a.type === 'directory' ? -1 : 1
    }
    // Then alphabetically
    return a.name.localeCompare(b.name)
  })
})

const listFiles = async () => {
  if (!currentPath.value) {
    error.value = 'Please enter a path'
    return
  }
  
  loading.value = true
  error.value = ''
  entries.value = []
  selectedFile.value = null
  fileContent.value = null
  
  try {
    const params = new URLSearchParams({ path: currentPath.value })
    if (recursive.value) params.append('recursive', 'true')
    
    const res = await fetch(`/api/filesystem/list?${params}`)
    const data = await res.json()
    
    if (!res.ok) {
      error.value = data.error || 'Failed to list files'
      return
    }
    
    entries.value = data.entries
  } catch (e: any) {
    error.value = e.message || 'Failed to list files'
  } finally {
    loading.value = false
  }
}

const goToPath = (path: string) => {
  currentPath.value = path
  recursive.value = false
  listFiles()
}

const goToParent = () => {
  const parts = currentPath.value.split('/').filter((p: string) => p)
  parts.pop()
  currentPath.value = '/' + parts.join('/')
  listFiles()
}

const selectEntry = (entry: FileEntry) => {
  selectedFile.value = entry
  fileContent.value = null
}

const readFile = async (path: string) => {
  readingFile.value = true
  error.value = ''
  
  try {
    const res = await fetch(`/api/filesystem/read?path=${encodeURIComponent(path)}`)
    const data = await res.json()
    
    if (!res.ok) {
      error.value = data.error || 'Failed to read file'
      return
    }
    
    if (data.isBinary) {
      error.value = 'Cannot display binary file content'
      return
    }
    
    fileContent.value = data
  } catch (e: any) {
    error.value = e.message || 'Failed to read file'
  } finally {
    readingFile.value = false
  }
}

const copyFile = async () => {
  if (!selectedFile.value || !copyDestination.value) return
  
  copying.value = true
  error.value = ''
  
  try {
    const res = await fetch('/api/filesystem/copy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: selectedFile.value.path,
        destination: copyDestination.value,
        overwrite: copyOverwrite.value
      })
    })
    
    const data = await res.json()
    
    if (!res.ok) {
      error.value = data.error || 'Failed to copy file'
      return
    }
    
    showCopyDialog.value = false
    copyDestination.value = ''
    copyOverwrite.value = false
    
    // Refresh the listing
    await listFiles()
  } catch (e: any) {
    error.value = e.message || 'Failed to copy file'
  } finally {
    copying.value = false
  }
}

const formatSize = (bytes: number): string => {
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  if (bytes === 0) return '0 B'
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`
}

const formatDate = (dateStr: string): string => {
  if (!dateStr) return '-'
  return new Date(dateStr).toLocaleString()
}

const getFileIcon = (name: string): string => {
  const ext = name.split('.').pop()?.toLowerCase()
  switch (ext) {
    case 'cs': return 'mdi-language-csharp'
    case 'ts': case 'js': return 'mdi-language-typescript'
    case 'vue': return 'mdi-vuejs'
    case 'py': return 'mdi-language-python'
    case 'json': return 'mdi-code-json'
    case 'md': return 'mdi-language-markdown'
    case 'html': return 'mdi-language-html5'
    case 'css': return 'mdi-language-css3'
    case 'sh': return 'mdi-console'
    case 'log': return 'mdi-file-document-outline'
    case 'txt': return 'mdi-file-document'
    case 'xml': return 'mdi-file-xml-box'
    case 'yml': case 'yaml': return 'mdi-file-cog'
    case 'sql': return 'mdi-database'
    case 'png': case 'jpg': case 'jpeg': case 'gif': return 'mdi-file-image'
    default: return 'mdi-file'
  }
}
</script>

<style scoped>
.file-content {
  background-color: #1e1e1e;
  color: #d4d4d4;
  padding: 16px;
  border-radius: 4px;
  overflow-x: auto;
  max-height: 400px;
  overflow-y: auto;
  font-family: 'Consolas', 'Monaco', monospace;
  font-size: 12px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-wrap: break-word;
}

.selected-row {
  background-color: rgba(var(--v-theme-primary), 0.1);
}
</style>
