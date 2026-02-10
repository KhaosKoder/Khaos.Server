import { createApp } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'
import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import '@mdi/font/css/materialdesignicons.css'
import 'vuetify/styles'
import App from './App.vue'
import Home from './views/Home.vue'
import Chat from './views/Chat.vue'
import Redis from './views/Redis.vue'
import Data from './views/Data.vue'
import Filesystem from './views/Filesystem.vue'
import Disk from './views/Disk.vue'
import Rag from './views/Rag.vue'

const vuetify = createVuetify({
  components,
  directives,
  theme: {
    defaultTheme: 'dark'
  }
})

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: Home },
    { path: '/chat', component: Chat },
    { path: '/redis', component: Redis },
    { path: '/data', component: Data },
    { path: '/filesystem', component: Filesystem },
    { path: '/disk', component: Disk },
    { path: '/rag', component: Rag }
  ]
})

createApp(App)
  .use(vuetify)
  .use(router)
  .mount('#app')
