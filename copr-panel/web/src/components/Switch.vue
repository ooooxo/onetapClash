<script setup lang="ts">
const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ (e: 'update:modelValue', v: boolean): void }>()
</script>
<template>
  <div class="sw" :class="{ on: props.modelValue }" @click="emit('update:modelValue', !props.modelValue)" />
</template>
<style scoped>
.sw{width:42px;height:24px;border-radius:var(--r-pill);background:var(--panel-hi);position:relative;flex:none;cursor:pointer;transition:background var(--t-med) var(--ease-out)}
.sw::after{content:"";position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:var(--r-pill);background:#fff;transition:transform var(--t-med) var(--spring);box-shadow:0 1px 3px rgba(0,0,0,.3)}
.sw.on{background:var(--accent)}.sw.on::after{transform:translateX(18px)}
</style>
