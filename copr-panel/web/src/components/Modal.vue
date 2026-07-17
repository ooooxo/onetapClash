<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import Icon from './Icon.vue'
defineProps<{ wide?: boolean }>()
const emit = defineEmits<{ (e: 'close'): void }>()
function onKey(e: KeyboardEvent) { if (e.key === 'Escape') emit('close') }
onMounted(() => document.addEventListener('keydown', onKey))
onUnmounted(() => document.removeEventListener('keydown', onKey))
</script>
<template>
  <div class="ov" @click.self="emit('close')">
    <div class="mo" :class="{ wide }">
      <button class="mox" aria-label="关闭" @click="emit('close')"><Icon name="close" :size="14" /></button>
      <slot />
    </div>
  </div>
</template>
<style scoped>
.ov{position:fixed;inset:0;z-index:40;background:rgba(4,5,8,.6);backdrop-filter:blur(7px);display:flex;align-items:center;justify-content:center;padding:22px;animation:fade .2s var(--ease-out)}
@keyframes fade{from{opacity:0}}
.mo{width:min(460px,100%);max-height:88vh;overflow:auto;background:var(--panel);border-radius:var(--r-xl);padding:26px;box-shadow:var(--shadow-pop);position:relative;animation:pop .34s var(--spring-soft) both}
.mo.wide{width:min(552px,100%)}
@keyframes pop{from{opacity:0;transform:translateY(12px) scale(.97)}}
.mox{position:absolute;top:16px;right:16px;width:30px;height:30px;border-radius:var(--r-sm);background:var(--inset);color:var(--ink-3);display:flex;align-items:center;justify-content:center}
.mox:hover{background:var(--hover-2);color:var(--ink)}
</style>
