<template>
  <div>
    <h1 class="text-h4 mb-4">Redis Cache Manager</h1>

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

    <!-- Key list -->
    <v-card>
      <v-card-title>All Keys</v-card-title>
      <v-card-text>
        <v-table v-if="Object.keys(items).length > 0">
          <thead>
            <tr>
              <th>Key</th>
              <th>Value</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(value, key) in items" :key="key">
              <td>{{ key }}</td>
              <td>{{ value }}</td>
              <td>
                <v-btn icon size="small" color="error" @click="deleteKey(key as string)">
                  <v-icon>mdi-delete</v-icon>
                </v-btn>
              </td>
            </tr>
          </tbody>
        </v-table>
        <p v-else class="text-grey">No keys in cache</p>
      </v-card-text>
    </v-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const items = ref<Record<string, string>>({})
const newKey = ref('')
const newValue = ref('')
const saving = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)

const fetchAll = async () => {
  const res = await fetch('/api/redis')
  items.value = await res.json()
}

const addKey = async () => {
  if (!newKey.value) return
  saving.value = true
  await fetch(`/api/redis/${newKey.value}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ value: newValue.value })
  })
  newKey.value = ''
  newValue.value = ''
  saving.value = false
  await fetchAll()
}

const deleteKey = async (key: string) => {
  await fetch(`/api/redis/${key}`, { method: 'DELETE' })
  await fetchAll()
}

const exportAll = () => {
  const blob = new Blob([JSON.stringify(items.value, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'redis-export.json'
  a.click()
}

const triggerImport = () => {
  fileInput.value?.click()
}

const importFile = async (e: Event) => {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  const text = await file.text()
  const data = JSON.parse(text)
  await fetch('/api/redis/bulk', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  })
  await fetchAll()
}

const clearAll = async () => {
  if (confirm('Are you sure you want to delete ALL keys?')) {
    await fetch('/api/redis', { method: 'DELETE' })
    await fetchAll()
  }
}

onMounted(fetchAll)
</script>
