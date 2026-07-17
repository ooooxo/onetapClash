<script setup lang="ts">
import { icons } from '../icons'
const props = defineProps<{ name: string; size?: number }>()
const inner = () => icons[props.name] || ''
</script>

<template>
  <svg viewBox="0 0 24 24" :width="size || 18" :height="size || 18" fill="currentColor" aria-hidden="true">
    <g transform="translate(12 12) scale(.98) translate(-12 -12)" v-html="inner()" />
  </svg>
</template>
