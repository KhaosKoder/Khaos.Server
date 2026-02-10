<template>
  <v-app>
    <v-app-bar color="primary" dark>
      <v-app-bar-title>
        <span class="font-weight-bold">{{ instanceName }}</span>
        <v-chip v-if="instanceName !== 'Khaos Server'" size="small" class="ml-2" color="white" variant="outlined">
          {{ instanceName.replace('Khaos ', '') }}
        </v-chip>
      </v-app-bar-title>
      <v-spacer></v-spacer>
      <v-btn to="/" variant="text">Home</v-btn>
      <v-btn to="/chat" variant="text">Chat</v-btn>
      <v-btn to="/rag" variant="text">RAG</v-btn>
      <v-btn to="/redis" variant="text">Redis</v-btn>
      <v-btn to="/data" variant="text">Data</v-btn>
      <v-btn to="/filesystem" variant="text">Files</v-btn>
      <v-btn to="/disk" variant="text">Disk</v-btn>
      <v-btn :href="swaggerUrl" target="_blank" variant="text">API Docs</v-btn>
      
      <!-- Folders Menu -->
      <v-menu>
        <template v-slot:activator="{ props }">
          <v-btn v-bind="props" variant="text" icon>
            <v-icon>mdi-folder-open</v-icon>
          </v-btn>
        </template>
        <v-list density="compact">
          <v-list-subheader>Quick Access</v-list-subheader>
          <v-list-item @click="openPath(paths.models)" prepend-icon="mdi-robot">
            <v-list-item-title>Models Folder</v-list-item-title>
            <v-list-item-subtitle>{{ paths.models }}</v-list-item-subtitle>
          </v-list-item>
          <v-list-item @click="openPath(paths.apps)" prepend-icon="mdi-application">
            <v-list-item-title>Apps Folder</v-list-item-title>
            <v-list-item-subtitle>{{ paths.apps }}</v-list-item-subtitle>
          </v-list-item>
          <v-list-item @click="openPath(paths.cache)" prepend-icon="mdi-cached">
            <v-list-item-title>Cache Folder</v-list-item-title>
            <v-list-item-subtitle>{{ paths.cache }}</v-list-item-subtitle>
          </v-list-item>
          <v-list-item @click="openPath(paths.logs)" prepend-icon="mdi-file-document">
            <v-list-item-title>Logs Folder</v-list-item-title>
            <v-list-item-subtitle>{{ paths.logs }}</v-list-item-subtitle>
          </v-list-item>
        </v-list>
      </v-menu>
    </v-app-bar>

    <v-main>
      <v-container fluid class="pa-4">
        <router-view></router-view>
      </v-container>
    </v-main>
    
    <!-- Snackbar for notifications -->
    <v-snackbar v-model="showSnackbar" :color="snackbarColor" :timeout="3000">
      {{ snackbarMessage }}
    </v-snackbar>
  </v-app>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const instanceName = ref('Khaos Server')
const swaggerUrl = ref('/swagger')
const paths = ref({
  models: '/usr/share/ollama/.ollama/models',
  apps: '/opt/khaos/apps',
  cache: '/mnt/khaos-cache',
  logs: '/var/log/khaos'
})

const showSnackbar = ref(false)
const snackbarMessage = ref('')
const snackbarColor = ref('info')

const loadInstanceInfo = async () => {
  try {
    const response = await fetch('/api/instance')
    if (response.ok) {
      const data = await response.json()
      instanceName.value = data.name
      paths.value = data.paths
      swaggerUrl.value = data.urls?.swagger || '/swagger'
    }
  } catch (error) {
    console.error('Failed to load instance info:', error)
  }
}

const openPath = (path: string) => {
  // Copy path to clipboard and show notification
  navigator.clipboard.writeText(path).then(() => {
    snackbarMessage.value = `Path copied: ${path}`
    snackbarColor.value = 'success'
    showSnackbar.value = true
  }).catch(() => {
    snackbarMessage.value = `Path: ${path}`
    snackbarColor.value = 'info'
    showSnackbar.value = true
  })
}

onMounted(() => {
  loadInstanceInfo()
})
</script>

<style>
html, body, #app {
  height: 100%;
  margin: 0;
}
</style>
