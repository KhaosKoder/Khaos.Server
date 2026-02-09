<template>
  <v-container fluid class="pa-4">
    <v-row>
      <!-- Left Sidebar - Conversations & Prompts -->
      <v-col cols="12" md="3">
        <v-card class="mb-4">
          <v-card-title class="d-flex align-center">
            <v-icon class="mr-2">mdi-message-text</v-icon>
            Conversations
            <v-spacer></v-spacer>
            <v-btn icon size="small" color="primary" @click="newConversation">
              <v-icon>mdi-plus</v-icon>
            </v-btn>
          </v-card-title>
          <v-divider></v-divider>
          <v-list density="compact" style="max-height: 200px; overflow-y: auto;">
            <v-list-item
              v-for="conv in conversations"
              :key="conv.id"
              :active="currentConversationId === conv.id"
              @click="loadConversation(conv.id)"
            >
              <v-list-item-title>{{ conv.name }}</v-list-item-title>
              <v-list-item-subtitle>{{ conv.messageCount }} messages</v-list-item-subtitle>
              <template v-slot:append>
                <v-btn icon size="x-small" @click.stop="deleteConversation(conv.id)">
                  <v-icon size="small">mdi-delete</v-icon>
                </v-btn>
              </template>
            </v-list-item>
            <v-list-item v-if="conversations.length === 0">
              <v-list-item-title class="text-grey">No saved conversations</v-list-item-title>
            </v-list-item>
          </v-list>
        </v-card>

        <v-card class="mb-4">
          <v-card-title class="d-flex align-center">
            <v-icon class="mr-2">mdi-bookmark</v-icon>
            Saved Prompts
            <v-spacer></v-spacer>
            <v-btn icon size="small" color="primary" @click="showSavePromptDialog = true">
              <v-icon>mdi-plus</v-icon>
            </v-btn>
          </v-card-title>
          <v-divider></v-divider>
          <v-list density="compact" style="max-height: 200px; overflow-y: auto;">
            <v-list-item
              v-for="prompt in prompts"
              :key="prompt.id"
              @click="usePrompt(prompt)"
            >
              <v-list-item-title>{{ prompt.name }}</v-list-item-title>
              <v-list-item-subtitle>{{ prompt.category }}</v-list-item-subtitle>
              <template v-slot:append>
                <v-btn icon size="x-small" @click.stop="deletePrompt(prompt.id)">
                  <v-icon size="small">mdi-delete</v-icon>
                </v-btn>
              </template>
            </v-list-item>
            <v-list-item v-if="prompts.length === 0">
              <v-list-item-title class="text-grey">No saved prompts</v-list-item-title>
            </v-list-item>
          </v-list>
        </v-card>

        <!-- System Prompts Library -->
        <v-card class="mb-4">
          <v-card-title class="d-flex align-center">
            <v-icon class="mr-2">mdi-robot</v-icon>
            System Prompts
            <v-spacer></v-spacer>
            <v-btn icon size="small" color="primary" @click="showSaveSystemPromptDialog = true" :disabled="!systemPrompt">
              <v-icon>mdi-content-save</v-icon>
            </v-btn>
          </v-card-title>
          <v-divider></v-divider>
          <v-list density="compact" style="max-height: 150px; overflow-y: auto;">
            <v-list-item
              v-for="sp in systemPrompts"
              :key="sp.id"
              :active="activeSystemPromptId === sp.id"
              @click="loadSystemPrompt(sp)"
            >
              <v-list-item-title>{{ sp.name }}</v-list-item-title>
              <template v-slot:append>
                <v-btn icon size="x-small" @click.stop="deleteSystemPrompt(sp.id)">
                  <v-icon size="small">mdi-delete</v-icon>
                </v-btn>
              </template>
            </v-list-item>
            <v-list-item v-if="systemPrompts.length === 0">
              <v-list-item-title class="text-grey">No saved system prompts</v-list-item-title>
            </v-list-item>
          </v-list>
        </v-card>

        <v-card>
          <v-card-title>
            <v-icon class="mr-2">mdi-cog</v-icon>
            Settings
          </v-card-title>
          <v-card-text>
            <v-select
              v-model="selectedModel"
              :items="models"
              item-title="name"
              item-value="name"
              label="Model"
              density="compact"
              hide-details
              class="mb-3"
            ></v-select>
            <v-textarea
              v-model="systemPrompt"
              label="System Prompt (applies to all messages)"
              rows="3"
              density="compact"
              hide-details
              placeholder="You are a helpful assistant..."
              @input="activeSystemPromptId = null"
            ></v-textarea>
            <div v-if="systemPrompt" class="text-caption text-success mt-1">
              <v-icon size="small" class="mr-1">mdi-check-circle</v-icon>
              System prompt active
            </div>
          </v-card-text>
        </v-card>
      </v-col>

      <!-- Main Chat Area -->
      <v-col cols="12" md="9">
        <v-card class="d-flex flex-column" style="height: calc(100vh - 120px);">
          <!-- Chat Header -->
          <v-card-title class="d-flex align-center py-2">
            <span>{{ currentConversationName }}</span>
            <v-spacer></v-spacer>
            <v-btn variant="text" size="small" @click="saveConversation" :disabled="messages.length === 0">
              <v-icon class="mr-1">mdi-content-save</v-icon>
              Save
            </v-btn>
            <v-btn variant="text" size="small" @click="exportConversation" :disabled="messages.length === 0">
              <v-icon class="mr-1">mdi-download</v-icon>
              Export
            </v-btn>
            <v-btn variant="text" size="small" @click="clearChat">
              <v-icon class="mr-1">mdi-delete</v-icon>
              Clear
            </v-btn>
          </v-card-title>
          <v-divider></v-divider>

          <!-- Messages Area -->
          <v-card-text class="flex-grow-1 overflow-y-auto pa-4" ref="messagesContainer">
            <div v-if="messages.length === 0" class="text-center text-grey py-8">
              <v-icon size="64" class="mb-4">mdi-chat-outline</v-icon>
              <p>Start a conversation or load a saved one</p>
            </div>
            
            <div v-for="(msg, i) in messages" :key="i" class="mb-4">
              <div :class="msg.role === 'user' ? 'd-flex justify-end' : 'd-flex justify-start'">
                <div class="message-container" :class="msg.role === 'user' ? 'user-message' : 'assistant-message'">
                  <div class="message-header d-flex align-center mb-1">
                    <v-icon size="small" class="mr-1">{{ msg.role === 'user' ? 'mdi-account' : 'mdi-robot' }}</v-icon>
                    <span class="text-caption">{{ msg.role === 'user' ? 'You' : selectedModel }}</span>
                    <v-spacer></v-spacer>
                    <v-btn icon size="x-small" @click="copyMessage(msg.content)" title="Copy">
                      <v-icon size="small">mdi-content-copy</v-icon>
                    </v-btn>
                    <v-btn icon size="x-small" @click="saveAsPrompt(msg.content)" title="Save as prompt">
                      <v-icon size="small">mdi-bookmark-plus</v-icon>
                    </v-btn>
                  </div>
                  <div class="message-content">{{ msg.content }}</div>
                  <div v-if="msg.attachments && msg.attachments.length > 0" class="mt-2">
                    <v-chip v-for="(att, j) in msg.attachments" :key="j" size="small" class="mr-1">
                      <v-icon start size="small">mdi-file</v-icon>
                      {{ att.name }}
                    </v-chip>
                  </div>
                </div>
              </div>
            </div>

            <div v-if="loading" class="d-flex justify-start mb-4">
              <div class="message-container assistant-message">
                <v-progress-circular indeterminate size="20" class="mr-2"></v-progress-circular>
                <span>Thinking...</span>
              </div>
            </div>
          </v-card-text>

          <!-- Input Area -->
          <v-divider></v-divider>
          <div class="pa-4">
            <!-- Attached Files Preview -->
            <div v-if="attachedFiles.length > 0" class="mb-2">
              <v-chip
                v-for="(file, i) in attachedFiles"
                :key="i"
                closable
                @click:close="removeFile(i)"
                class="mr-1 mb-1"
                size="small"
              >
                <v-icon start size="small">mdi-file</v-icon>
                {{ file.name }}
              </v-chip>
            </div>

            <v-textarea
              v-model="input"
              label="Type your message..."
              rows="4"
              auto-grow
              max-rows="10"
              hide-details
              :disabled="loading"
              @keydown.ctrl.enter="send"
              class="mb-2"
            >
              <template v-slot:append-inner>
                <v-btn icon size="small" @click="triggerFileUpload" :disabled="loading" title="Attach file">
                  <v-icon>mdi-paperclip</v-icon>
                </v-btn>
              </template>
            </v-textarea>
            
            <div class="d-flex align-center">
              <span class="text-caption text-grey">Ctrl+Enter to send</span>
              <v-spacer></v-spacer>
              <v-btn
                color="primary"
                @click="send"
                :loading="loading"
                :disabled="!input.trim() && attachedFiles.length === 0"
              >
                <v-icon class="mr-1">mdi-send</v-icon>
                Send
              </v-btn>
            </div>
          </div>
        </v-card>
      </v-col>
    </v-row>

    <!-- Hidden file input -->
    <input type="file" ref="fileInput" @change="handleFileUpload" multiple style="display: none" />

    <!-- Save Prompt Dialog -->
    <v-dialog v-model="showSavePromptDialog" max-width="500">
      <v-card>
        <v-card-title>Save Prompt</v-card-title>
        <v-card-text>
          <v-text-field v-model="newPromptName" label="Prompt Name" class="mb-2"></v-text-field>
          <v-select
            v-model="newPromptCategory"
            :items="['general', 'code', 'analysis', 'writing', 'custom']"
            label="Category"
            class="mb-2"
          ></v-select>
          <v-textarea v-model="newPromptContent" label="Prompt Content" rows="5"></v-textarea>
        </v-card-text>
        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn @click="showSavePromptDialog = false">Cancel</v-btn>
          <v-btn color="primary" @click="savePrompt">Save</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Save Conversation Dialog -->
    <v-dialog v-model="showSaveConversationDialog" max-width="400">
      <v-card>
        <v-card-title>Save Conversation</v-card-title>
        <v-card-text>
          <v-text-field v-model="conversationName" label="Conversation Name"></v-text-field>
          <div class="text-caption text-grey mt-2" v-if="systemPrompt">
            <v-icon size="small" class="mr-1">mdi-information</v-icon>
            System prompt will be saved with this conversation
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn @click="showSaveConversationDialog = false">Cancel</v-btn>
          <v-btn color="primary" @click="doSaveConversation">Save</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Save System Prompt Dialog -->
    <v-dialog v-model="showSaveSystemPromptDialog" max-width="400">
      <v-card>
        <v-card-title>Save System Prompt</v-card-title>
        <v-card-text>
          <v-text-field v-model="newSystemPromptName" label="Name" placeholder="e.g., Rude Assistant"></v-text-field>
          <div class="text-caption text-grey mt-2">
            Current system prompt will be saved for reuse.
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn @click="showSaveSystemPromptDialog = false">Cancel</v-btn>
          <v-btn color="primary" @click="saveSystemPrompt">Save</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Snackbar for notifications -->
    <v-snackbar v-model="snackbar" :timeout="2000">{{ snackbarText }}</v-snackbar>
  </v-container>
</template>

<script setup lang="ts">
import { ref, onMounted, nextTick } from 'vue'

interface Message {
  role: 'user' | 'assistant'
  content: string
  attachments?: { name: string; content: string }[]
}

interface Conversation {
  id: string
  name: string
  messageCount: number
  createdAt: string
}

interface Prompt {
  id: string
  name: string
  content: string
  category: string
}

interface SystemPrompt {
  id: string
  name: string
  content: string
}

// State
const messages = ref<Message[]>([])
const input = ref('')
const loading = ref(false)
const selectedModel = ref('qwen2.5:3b')
const models = ref<{ name: string }[]>([])
const systemPrompt = ref('')
const attachedFiles = ref<{ name: string; content: string }[]>([])

// Conversations & Prompts
const conversations = ref<Conversation[]>([])
const prompts = ref<Prompt[]>([])
const systemPrompts = ref<SystemPrompt[]>([])
const activeSystemPromptId = ref<string | null>(null)
const currentConversationId = ref<string | null>(null)
const currentConversationName = ref('New Conversation')

// Dialogs
const showSavePromptDialog = ref(false)
const showSaveConversationDialog = ref(false)
const showSaveSystemPromptDialog = ref(false)
const newPromptName = ref('')
const newPromptCategory = ref('general')
const newPromptContent = ref('')
const newSystemPromptName = ref('')
const conversationName = ref('')

// UI
const snackbar = ref(false)
const snackbarText = ref('')
const messagesContainer = ref<HTMLElement | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)

const notify = (text: string) => {
  snackbarText.value = text
  snackbar.value = true
}

const scrollToBottom = async () => {
  await nextTick()
  if (messagesContainer.value) {
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
  }
}

// Chat functions
const send = async () => {
  if ((!input.value.trim() && attachedFiles.value.length === 0) || loading.value) return

  let messageContent = input.value
  
  // Include file contents in the message
  if (attachedFiles.value.length > 0) {
    messageContent += '\n\n--- Attached Files ---\n'
    for (const file of attachedFiles.value) {
      messageContent += `\n[${file.name}]\n${file.content}\n`
    }
  }

  // Build conversation context with system prompt
  // System prompt should apply to ALL messages, not just the first one
  let conversationContext = ''
  
  // Add system prompt at the beginning of context
  if (systemPrompt.value) {
    conversationContext += `System: ${systemPrompt.value}\n\n`
  }
  
  // Include recent conversation history for context (last 10 exchanges max)
  const recentMessages = messages.value.slice(-20)
  for (const msg of recentMessages) {
    conversationContext += `${msg.role === 'user' ? 'User' : 'Assistant'}: ${msg.content}\n\n`
  }
  
  // Add current message
  conversationContext += `User: ${messageContent}`

  const userMessage: Message = {
    role: 'user',
    content: input.value,
    attachments: attachedFiles.value.length > 0 ? [...attachedFiles.value] : undefined
  }
  messages.value.push(userMessage)
  
  input.value = ''
  attachedFiles.value = []
  loading.value = true
  scrollToBottom()

  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: conversationContext, model: selectedModel.value })
    })
    const data = await res.json()
    messages.value.push({ role: 'assistant', content: data.response })
  } catch (e) {
    messages.value.push({ role: 'assistant', content: 'Error: Could not get response' })
  }

  loading.value = false
  scrollToBottom()
}

const clearChat = () => {
  messages.value = []
  currentConversationId.value = null
  currentConversationName.value = 'New Conversation'
}

// File handling
const triggerFileUpload = () => {
  fileInput.value?.click()
}

const handleFileUpload = async (e: Event) => {
  const files = (e.target as HTMLInputElement).files
  if (!files) return

  for (const file of files) {
    const content = await file.text()
    attachedFiles.value.push({ name: file.name, content })
  }
  
  // Reset input so same file can be selected again
  if (fileInput.value) fileInput.value.value = ''
}

const removeFile = (index: number) => {
  attachedFiles.value.splice(index, 1)
}

// Conversation management
const loadConversations = async () => {
  try {
    const res = await fetch('/api/conversations')
    conversations.value = await res.json()
  } catch (e) {
    console.error('Failed to load conversations')
  }
}

const loadConversation = async (id: string) => {
  try {
    const res = await fetch(`/api/conversations/${id}`)
    const data = await res.json()
    messages.value = data.messages || []
    currentConversationId.value = id
    currentConversationName.value = data.name
    systemPrompt.value = data.systemPrompt || ''
    scrollToBottom()
  } catch (e) {
    notify('Failed to load conversation')
  }
}

const newConversation = () => {
  clearChat()
  systemPrompt.value = ''
}

const saveConversation = () => {
  conversationName.value = currentConversationName.value
  showSaveConversationDialog.value = true
}

const doSaveConversation = async () => {
  try {
    const payload = {
      name: conversationName.value,
      messages: messages.value,
      systemPrompt: systemPrompt.value
    }

    if (currentConversationId.value) {
      await fetch(`/api/conversations/${currentConversationId.value}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...payload, id: currentConversationId.value, createdAt: new Date().toISOString() })
      })
    } else {
      const res = await fetch('/api/conversations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      const data = await res.json()
      currentConversationId.value = data.id
    }

    currentConversationName.value = conversationName.value
    showSaveConversationDialog.value = false
    loadConversations()
    notify('Conversation saved')
  } catch (e) {
    notify('Failed to save conversation')
  }
}

const deleteConversation = async (id: string) => {
  if (!confirm('Delete this conversation?')) return
  try {
    await fetch(`/api/conversations/${id}`, { method: 'DELETE' })
    if (currentConversationId.value === id) {
      clearChat()
    }
    loadConversations()
    notify('Conversation deleted')
  } catch (e) {
    notify('Failed to delete conversation')
  }
}

const exportConversation = () => {
  const data = {
    name: currentConversationName.value,
    exportedAt: new Date().toISOString(),
    messages: messages.value,
    systemPrompt: systemPrompt.value
  }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${currentConversationName.value.replace(/\s+/g, '-')}.json`
  a.click()
}

// Prompt management
const loadPrompts = async () => {
  try {
    const res = await fetch('/api/prompts')
    prompts.value = await res.json()
  } catch (e) {
    console.error('Failed to load prompts')
  }
}

const usePrompt = (prompt: Prompt) => {
  input.value = prompt.content
}

const saveAsPrompt = (content: string) => {
  newPromptContent.value = content
  newPromptName.value = ''
  newPromptCategory.value = 'general'
  showSavePromptDialog.value = true
}

const savePrompt = async () => {
  if (!newPromptName.value || !newPromptContent.value) return
  try {
    await fetch('/api/prompts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: newPromptName.value,
        content: newPromptContent.value,
        category: newPromptCategory.value
      })
    })
    showSavePromptDialog.value = false
    loadPrompts()
    notify('Prompt saved')
  } catch (e) {
    notify('Failed to save prompt')
  }
}

const deletePrompt = async (id: string) => {
  try {
    await fetch(`/api/prompts/${id}`, { method: 'DELETE' })
    loadPrompts()
    notify('Prompt deleted')
  } catch (e) {
    notify('Failed to delete prompt')
  }
}

// System Prompt management
const loadSystemPrompts = async () => {
  try {
    const res = await fetch('/api/system-prompts')
    systemPrompts.value = await res.json()
  } catch (e) {
    console.error('Failed to load system prompts')
  }
}

const loadSystemPrompt = (sp: SystemPrompt) => {
  systemPrompt.value = sp.content
  activeSystemPromptId.value = sp.id
  notify(`Loaded: ${sp.name}`)
}

const saveSystemPrompt = async () => {
  if (!newSystemPromptName.value || !systemPrompt.value) return
  try {
    const res = await fetch('/api/system-prompts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: newSystemPromptName.value,
        content: systemPrompt.value
      })
    })
    const data = await res.json()
    activeSystemPromptId.value = data.id
    showSaveSystemPromptDialog.value = false
    newSystemPromptName.value = ''
    loadSystemPrompts()
    notify('System prompt saved')
  } catch (e) {
    notify('Failed to save system prompt')
  }
}

const deleteSystemPrompt = async (id: string) => {
  try {
    await fetch(`/api/system-prompts/${id}`, { method: 'DELETE' })
    if (activeSystemPromptId.value === id) {
      activeSystemPromptId.value = null
    }
    loadSystemPrompts()
    notify('System prompt deleted')
  } catch (e) {
    notify('Failed to delete system prompt')
  }
}

// Utility
const copyMessage = async (content: string) => {
  await navigator.clipboard.writeText(content)
  notify('Copied to clipboard')
}

// Load models
const loadModels = async () => {
  try {
    const res = await fetch('/api/chat/models')
    const data = await res.json()
    models.value = data.models || []
    if (models.value.length > 0) {
      selectedModel.value = models.value[0].name
    }
  } catch (e) {
    console.error('Failed to load models')
  }
}

onMounted(() => {
  loadModels()
  loadConversations()
  loadPrompts()
  loadSystemPrompts()
})
</script>

<style scoped>
.message-container {
  max-width: 80%;
  padding: 12px 16px;
  border-radius: 12px;
  word-break: break-word;
  white-space: pre-wrap;
}

.user-message {
  background-color: rgb(var(--v-theme-primary));
  color: white;
  border-bottom-right-radius: 4px;
}

.assistant-message {
  background-color: rgb(var(--v-theme-surface-variant));
  border-bottom-left-radius: 4px;
}

.message-content {
  line-height: 1.5;
}

.message-header {
  opacity: 0.7;
  font-size: 0.75rem;
}
</style>
