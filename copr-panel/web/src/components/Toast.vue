<script setup lang="ts">
import { ui } from '../ui'
</script>
<template>
  <div class="toasts">
    <TransitionGroup name="t">
      <div v-for="t in ui.toasts" :key="t.id" class="toast">{{ t.msg }}</div>
    </TransitionGroup>
  </div>
</template>
<style scoped>
.toasts{position:fixed;bottom:calc(var(--dock) + 16px);left:50%;transform:translateX(-50%);z-index:70;display:flex;flex-direction:column;gap:8px;align-items:center;pointer-events:none}
.toast{background:var(--panel-strong);color:var(--ink);padding:11px 18px;border-radius:var(--r-pill);font-size:13px;font-weight:600;box-shadow:var(--shadow-pop);border:1px solid var(--sep)}
.t-enter-active{transition:transform var(--t-med) var(--ease-out),opacity var(--t-med) var(--ease-out)}
.t-leave-active{transition:transform var(--t-fast) var(--ease-out),opacity var(--t-fast) var(--ease-out)}
.t-enter-from,.t-leave-to{opacity:0;transform:translateY(10px)}
</style>
