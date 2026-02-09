<template>
  <v-app>
    <v-app-bar color="primary" dark>
      <v-app-bar-title>Khaos Server</v-app-bar-title>
      <v-spacer></v-spacer>
      <v-btn to="/" variant="text">Home</v-btn>
      <v-btn to="/chat" variant="text">Chat</v-btn>
      <v-btn to="/redis" variant="text">Redis</v-btn>
      <v-btn href="/swagger" target="_blank" variant="text">API Docs</v-btn>
    </v-app-bar>

    <v-main>
      <v-container fluid class="pa-4">
        <router-view></router-view>
      </v-container>
    </v-main>
  </v-app>
</template>

<script setup lang="ts">
</script>

<style>
html, body, #app {
  height: 100%;
  margin: 0;
}
</style>
