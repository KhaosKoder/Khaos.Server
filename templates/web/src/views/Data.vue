<template>
  <div>
    <h1 class="text-h4 mb-2">Persistent Data Manager</h1>
    <p class="text-grey mb-4">Data stored in PostgreSQL with Redis caching (5-min TTL)</p>

    <!-- Add new key -->
    <v-card class="mb-4">
      <v-card-title>Add Key/Value</v-card-title>
      <v-card-text>
        <v-row>
          <v-col cols="4">
            <v-text-field v-model="newKey" label="Key" density="compact"></v-text-field>
          </v-col>
          <v-col cols="6">
            <v-text-field v-model="newValue" label="Value" density="compact"></v-text-field>
          </v-col>
          <v-col cols="2">
            <v-btn color="primary" @click="addKey" :loading="saving">Add</v-btn>
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>

    <!-- Bulk actions -->
    <v-card class="mb-4">
      <v-card-title>Bulk Actions</v-card-title>
      <v-card-text>
        <v-btn color="secondary" class="mr-2" @click="exportAll">
          <v-icon left>mdi-download</v-icon> Export JSON
        </v-btn>
        <v-btn color="secondary" class="mr-2" @click="triggerImport">
          <v-icon left>mdi-upload</v-icon> Import JSON
        </v-btn>
        <v-btn color="error" @click="clearAll">
          <v-icon left>mdi-delete</v-icon> Clear All
        </v-btn>
        <input type="file" ref="fileInput" @change="importFile" accept=".json" style="display:none" />
      </v-card-text>
    </v-card>

    <!-- Info banner -->
    <v-alert type="info" variant="tonal" class="mb-4" density="compact">
      <strong>Source column:</strong> Shows if data came from <v-chip size="x-small" color="success">cache</v-chip> (fast) 
      or <v-chip size="x-small" color="primary">database</v-chip> (PostgreSQL). 
      Cache expires after 5 minutes.
    </v-alert>

    <!-- Key list -->
    <v-card>
      <v-card-title>All Keys ({{ items.length }})</v-card-title>
      <v-card-text>
        <v-table v-if="items.length > 0" density="compact">
          <thead>
            <tr>
              <th>Key</th>
              <th>Value</th>
              <th>Created</th>
              <th>Updated</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in items" :key="item.key">
              <td><code>{{ item.key }}</code></td>
              <td>
                <template v-if="editingKey === item.key">
                  <v-text-field
                    v-model="editValue"
                    density="compact"
                    hide-details
                    autofocus
                    @keyup.enter="saveEdit(item.key)"
                    @keyup.escape="cancelEdit"
                  >
                    <template v-slot:append>
                      <v-btn icon size="x-small" color="success" @click="saveEdit(item.key)">
                        <v-icon>mdi-check</v-icon>
                      </v-btn>
                      <v-btn icon size="x-small" @click="cancelEdit">
                        <v-icon>mdi-close</v-icon>
                      </v-btn>
                    </template>
                  </v-text-field>
                </template>
                <template v-else>
                  {{ formatValue(item.value) }}
                </template>
              </td>
              <td class="text-grey text-caption">{{ formatDate(item.createdAt) }}</td>
              <td class="text-grey text-caption">{{ formatDate(item.updatedAt) }}</td>
              <td>
                <v-btn icon size="small" color="primary" @click="startEdit(item.key, item.value)" v-if="editingKey !== item.key">
                  <v-icon>mdi-pencil</v-icon>
                </v-btn>
                <v-btn icon size="small" color="error" @click="deleteKey(item.key)">
                  <v-icon>mdi-delete</v-icon>
                </v-btn>
              </td>
            </tr>
          </tbody>
        </v-table>
        <p v-else class="text-grey">No data stored</p>
      </v-card-text>
    </v-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

interface DataItem {
  key: string
  value: unknown
  createdAt: string
  updatedAt: string
}

const items = ref<DataItem[]>([])
const newKey = ref('')
const newValue = ref('')
const saving = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)
const editingKey = ref<string | null>(null)
const editValue = ref('')

const fetchAll = async () => {
  const res = await fetch('/api/data')
  const data = await res.json()
  items.value = data.items || []
}

const addKey = async () => {
  if (!newKey.value) return
  saving.value = true
  try {
    let valueToStore: unknown = newValue.value
    // Try to parse as JSON if it looks like JSON
    if (newValue.value.startsWith('{') || newValue.value.startsWith('[')) {
      try {
        valueToStore = JSON.parse(newValue.value)
      } catch {
        // Keep as string if not valid JSON
      }
    }
    await fetch(`/api/data/${newKey.value}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ value: valueToStore })
    })
    newKey.value = ''
    newValue.value = ''
    await fetchAll()
  } finally {
    saving.value = false
  }
}

const deleteKey = async (key: string) => {
  await fetch(`/api/data/${key}`, { method: 'DELETE' })
  await fetchAll()
}

const startEdit = (key: string, value: unknown) => {
  editingKey.value = key
  editValue.value = typeof value === 'string' ? value : JSON.stringify(value)
}

const cancelEdit = () => {
  editingKey.value = null
  editValue.value = ''
}

const saveEdit = async (key: string) => {
  let valueToStore: unknown = editValue.value
  // Try to parse as JSON if it looks like JSON
  if (editValue.value.startsWith('{') || editValue.value.startsWith('[')) {
    try {
      valueToStore = JSON.parse(editValue.value)
    } catch {
      // Keep as string if not valid JSON
    }
  }
  await fetch(`/api/data/${key}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ value: valueToStore })
  })
  editingKey.value = null
  editValue.value = ''
  await fetchAll()
}

const formatValue = (value: unknown): string => {
  if (typeof value === 'string') return value
  return JSON.stringify(value)
}

const formatDate = (dateStr: string): string => {
  if (!dateStr) return '-'
  const date = new Date(dateStr)
  return date.toLocaleString()
}

const exportAll = () => {
  const exportData: Record<string, unknown> = {}
  items.value.forEach(item => {
    exportData[item.key] = item.value
  })
  const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'data-export.json'
  a.click()
}

const triggerImport = () => {
  fileInput.value?.click()
}

const importFile = async (e: Event) => {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  const text = await file.text()
  const data = JSON.parse(text) as Record<string, unknown>
  // Use bulk endpoint for efficient import
  await fetch('/api/data/bulk', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  })
  await fetchAll()
}

const clearAll = async () => {
  if (confirm('Are you sure you want to delete ALL persistent data? This cannot be undone.')) {
    await fetch('/api/data', { method: 'DELETE' })
    await fetchAll()
  }
}

onMounted(fetchAll)
</script>
