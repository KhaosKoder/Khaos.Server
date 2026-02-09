<template>
  <div>
    <h1 class="text-h4 mb-4">LLM Chat</h1>

    <v-card class="mb-4" style="height: 400px; overflow-y: auto;">
      <v-card-text>
        <div v-for="(msg, i) in messages" :key="i" class="mb-3">
          <div :class="msg.role === 'user' ? 'd-flex justify-end' : 'd-flex justify-start'">
            <div 
              :class="[
                'message-bubble', 
                'pa-3', 
                'rounded-lg',
                msg.role === 'user' ? 'bg-primary' : 'bg-grey-darken-3'
              ]"
            >
              {{ msg.content }}
            </div>
          </div>
        </div>
        <div v-if="loading" class="text-center">
          <v-progress-circular indeterminate size="24"></v-progress-circular>
          <span class="ml-2">Thinking...</span>
        </div>
      </v-card-text>
    </v-card>

    <v-text-field
      v-model="input"
      label="Type your message..."
      append-inner-icon="mdi-send"
      @click:append-inner="send"
      @keyup.enter="send"
      :disabled="loading"
    ></v-text-field>

    <p class="text-caption text-grey">Model: {{ model }}</p>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const messages = ref<Array<{ role: string; content: string }>>([])
const input = ref('')
const loading = ref(false)
const model = ref('qwen2.5:3b')

const send = async () => {
  if (!input.value.trim() || loading.value) return

  const userMessage = input.value
  messages.value.push({ role: 'user', content: userMessage })
  input.value = ''
  loading.value = true

  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: userMessage, model: model.value })
    })
    const data = await res.json()
    messages.value.push({ role: 'assistant', content: data.response })
  } catch (e) {
    messages.value.push({ role: 'assistant', content: 'Error: Could not get response' })
  }

  loading.value = false
}

onMounted(async () => {
  try {
    const res = await fetch('/api/chat/models')
    const data = await res.json()
    if (data.models?.length > 0) {
      model.value = data.models[0].name
    }
  } catch (e) {
    console.error('Could not fetch models')
  }
})
</script>

<style scoped>
.message-bubble {
  max-width: 80%;
  word-break: break-word;
  white-space: pre-wrap;
  overflow-wrap: break-word;
}
</style>
