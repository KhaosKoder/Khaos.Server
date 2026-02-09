<template>
  <div>
    <h1 class="text-h4 mb-2">Khaos Server Dashboard</h1>
    <p class="text-subtitle-1 text-grey mb-6">Your local AI development environment</p>

    <!-- Status Tiles Row -->
    <v-row>
      <v-col cols="12" sm="6" md="3">
        <v-card class="pa-4" :color="health?.redis === 'connected' ? 'success' : 'error'" variant="tonal">
          <div class="d-flex align-center">
            <v-avatar color="white" size="48" class="mr-4">
              <v-icon :color="health?.redis === 'connected' ? 'success' : 'error'" size="28">mdi-database</v-icon>
            </v-avatar>
            <div>
              <div class="text-h6 font-weight-bold">Redis</div>
              <div class="text-body-2">{{ health?.redis || 'Checking...' }}</div>
            </div>
          </div>
        </v-card>
      </v-col>

      <v-col cols="12" sm="6" md="3">
        <v-card class="pa-4" :color="health?.ollama === 'connected' ? 'success' : 'warning'" variant="tonal">
          <div class="d-flex align-center">
            <v-avatar color="white" size="48" class="mr-4">
              <v-icon :color="health?.ollama === 'connected' ? 'success' : 'warning'" size="28">mdi-robot</v-icon>
            </v-avatar>
            <div>
              <div class="text-h6 font-weight-bold">Ollama</div>
              <div class="text-body-2">{{ health?.ollama || 'Checking...' }}</div>
            </div>
          </div>
        </v-card>
      </v-col>

      <v-col cols="12" sm="6" md="3">
        <v-card class="pa-4" color="primary" variant="tonal">
          <div class="d-flex align-center">
            <v-avatar color="white" size="48" class="mr-4">
              <v-icon color="primary" size="28">mdi-message-text</v-icon>
            </v-avatar>
            <div>
              <div class="text-h4 font-weight-bold">{{ conversationCount }}</div>
              <div class="text-body-2">Conversations</div>
            </div>
          </div>
        </v-card>
      </v-col>

      <v-col cols="12" sm="6" md="3">
        <v-card class="pa-4" color="secondary" variant="tonal">
          <div class="d-flex align-center">
            <v-avatar color="white" size="48" class="mr-4">
              <v-icon color="secondary" size="28">mdi-brain</v-icon>
            </v-avatar>
            <div>
              <div class="text-h4 font-weight-bold">{{ modelCount }}</div>
              <div class="text-body-2">AI Models</div>
            </div>
          </div>
        </v-card>
      </v-col>
    </v-row>

    <!-- Quick Actions & Info Row -->
    <v-row class="mt-4">
      <v-col cols="12" md="8">
        <v-card>
          <v-card-title class="d-flex align-center">
            <v-icon class="mr-2" color="primary">mdi-rocket-launch</v-icon>
            Quick Actions
          </v-card-title>
          <v-card-text>
            <v-row>
              <v-col cols="12" sm="4">
                <v-card to="/chat" class="text-center pa-4 cursor-pointer" variant="outlined" hover>
                  <v-icon size="48" color="primary" class="mb-2">mdi-chat</v-icon>
                  <div class="text-h6">Chat</div>
                  <div class="text-caption text-grey">Talk to the AI</div>
                </v-card>
              </v-col>
              <v-col cols="12" sm="4">
                <v-card to="/redis" class="text-center pa-4 cursor-pointer" variant="outlined" hover>
                  <v-icon size="48" color="orange" class="mb-2">mdi-database-search</v-icon>
                  <div class="text-h6">Redis</div>
                  <div class="text-caption text-grey">Manage cache</div>
                </v-card>
              </v-col>
              <v-col cols="12" sm="4">
                <v-card href="/swagger" target="_blank" class="text-center pa-4 cursor-pointer" variant="outlined" hover>
                  <v-icon size="48" color="green" class="mb-2">mdi-api</v-icon>
                  <div class="text-h6">API Docs</div>
                  <div class="text-caption text-grey">Swagger UI</div>
                </v-card>
              </v-col>
            </v-row>
          </v-card-text>
        </v-card>
      </v-col>

      <v-col cols="12" md="4">
        <v-card height="100%">
          <v-card-title class="d-flex align-center">
            <v-icon class="mr-2" color="info">mdi-information</v-icon>
            System Info
          </v-card-title>
          <v-card-text>
            <v-list density="compact">
              <v-list-item>
                <template v-slot:prepend>
                  <v-icon size="small" color="grey">mdi-harddisk</v-icon>
                </template>
                <v-list-item-title>Storage</v-list-item-title>
                <v-list-item-subtitle>{{ redisInfo.persistence }}</v-list-item-subtitle>
              </v-list-item>
              <v-list-item>
                <template v-slot:prepend>
                  <v-icon size="small" color="grey">mdi-key</v-icon>
                </template>
                <v-list-item-title>Redis Keys</v-list-item-title>
                <v-list-item-subtitle>{{ redisInfo.keyCount }} total</v-list-item-subtitle>
              </v-list-item>
              <v-list-item>
                <template v-slot:prepend>
                  <v-icon size="small" color="grey">mdi-bookmark</v-icon>
                </template>
                <v-list-item-title>Saved Prompts</v-list-item-title>
                <v-list-item-subtitle>{{ promptCount }} prompts</v-list-item-subtitle>
              </v-list-item>
              <v-list-item>
                <template v-slot:prepend>
                  <v-icon size="small" color="grey">mdi-clock</v-icon>
                </template>
                <v-list-item-title>Status</v-list-item-title>
                <v-list-item-subtitle>{{ health?.status || 'Unknown' }}</v-list-item-subtitle>
              </v-list-item>
            </v-list>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>

    <!-- Models List -->
    <v-row class="mt-4">
      <v-col cols="12">
        <v-card>
          <v-card-title class="d-flex align-center">
            <v-icon class="mr-2" color="purple">mdi-brain</v-icon>
            Available Models
            <v-spacer></v-spacer>
            <v-chip size="small" color="primary">{{ modelCount }} installed</v-chip>
          </v-card-title>
          <v-card-text>
            <v-chip-group v-if="models.length > 0">
              <v-chip
                v-for="model in models"
                :key="model.name"
                variant="outlined"
                color="primary"
                class="ma-1"
              >
                <v-icon start size="small">mdi-cube</v-icon>
                {{ model.name }}
                <span class="ml-2 text-grey text-caption">{{ formatSize(model.size) }}</span>
              </v-chip>
            </v-chip-group>
            <p v-else class="text-grey">No models loaded. Run: ollama pull qwen2.5:3b</p>
          </v-card-text>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const health = ref<any>(null)
const conversationCount = ref(0)
const promptCount = ref(0)
const modelCount = ref(0)
const models = ref<any[]>([])
const redisInfo = ref({
  persistence: 'RDB snapshots',
  keyCount: 0
})

const formatSize = (bytes: number) => {
  if (!bytes) return ''
  const gb = bytes / (1024 * 1024 * 1024)
  return gb >= 1 ? `${gb.toFixed(1)}GB` : `${(bytes / (1024 * 1024)).toFixed(0)}MB`
}

onMounted(async () => {
  try {
    const [healthRes, convRes, promptsRes, modelsRes, redisRes] = await Promise.all([
      fetch('/api/health'),
      fetch('/api/conversations'),
      fetch('/api/prompts'),
      fetch('/api/chat/models'),
      fetch('/api/redis')
    ])
    
    health.value = await healthRes.json()
    
    const convs = await convRes.json()
    conversationCount.value = Array.isArray(convs) ? convs.length : 0
    
    const prompts = await promptsRes.json()
    promptCount.value = Array.isArray(prompts) ? prompts.length : 0
    
    const modelsData = await modelsRes.json()
    models.value = modelsData.models || []
    modelCount.value = models.value.length
    
    const redisData = await redisRes.json()
    redisInfo.value.keyCount = Object.keys(redisData).length
  } catch (e) {
    console.error('Failed to fetch dashboard data', e)
  }
})
</script>

<style scoped>
.cursor-pointer {
  cursor: pointer;
}
</style>